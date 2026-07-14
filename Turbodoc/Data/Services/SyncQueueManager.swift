import Foundation
import SwiftData
import Combine

@Observable
final class SyncQueueManager {
    static let shared = SyncQueueManager()
    
    private var modelContext: ModelContext?
    private var authService: AuthenticationService?
    private var cancellables = Set<AnyCancellable>()
    private var isSyncing = false
    
    private(set) var pendingOperationsCount = 0
    private(set) var lastSyncTime: Date?
    private(set) var lastSyncError: String?
    
    private init() {
        setupNetworkObserver()
    }
    
    func configure(modelContext: ModelContext, authService: AuthenticationService? = nil) {
        self.modelContext = modelContext
        if let authService = authService {
            self.authService = authService
        }
        loadPendingOperationsCount()
    }
    
    private func setupNetworkObserver() {
        NetworkMonitor.shared.connectionStatusChanged
            .sink { [weak self] isConnected in
                if isConnected {
                    Task {
                        await self?.processPendingOperations()
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Queue Operations
    
    func queueOperation(
        type: String,
        entityType: String,
        entityId: UUID? = nil,
        payload: Data
    ) {
        guard let context = modelContext else {
            return
        }
        
        let operation = SyncOperation(
            operationType: type,
            entityType: entityType,
            entityId: entityId,
            payload: payload
        )
        
        context.insert(operation)
        
        do {
            try context.save()
            pendingOperationsCount += 1
            
            // Try to sync immediately if online
            if NetworkMonitor.shared.isConnected {
                Task {
                    await processPendingOperations()
                }
            }
        } catch {
            AppLogger.sync.error(
                "Failed to queue operation: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
    
    func queueNoteOperation(type: String, note: NoteItem) {
        let payload = NoteOperationPayload(
            id: note.id,
            title: note.title,
            content: note.content,
            tags: note.tags,
            isFavorite: note.isFavorite,
            version: note.version,
            headRevisionId: note.headRevisionId
        )
        
        guard let data = try? JSONEncoder().encode(payload) else {
            AppLogger.sync.error("Failed to encode note payload")
            return
        }
        
        queueOperation(
            type: type,
            entityType: "note",
            entityId: note.id,
            payload: data
        )
    }
    
    func queueBookmarkOperation(type: String, bookmark: BookmarkItem) {
        let payload = BookmarkOperationPayload(
            id: bookmark.id,
            title: bookmark.title,
            url: bookmark.url,
            tags: bookmark.tags,
            status: bookmark.status.rawValue,
            isFavorite: bookmark.isFavorite,
            version: bookmark.version
        )
        
        guard let data = try? JSONEncoder().encode(payload) else {
            AppLogger.sync.error("Failed to encode bookmark payload")
            return
        }
        
        queueOperation(
            type: type,
            entityType: "bookmark",
            entityId: bookmark.id,
            payload: data
        )
    }
    
    // MARK: - Processing
    
    func processPendingOperations() async {
        guard let context = modelContext else { return }
        guard NetworkMonitor.shared.isConnected else {
            return
        }
        guard !isSyncing else {
            return
        }
        
        isSyncing = true
        defer { isSyncing = false }
        
        do {
            // Fetch pending operations
            let descriptor = FetchDescriptor<SyncOperation>(
                predicate: #Predicate { $0.status == "pending" || $0.status == "failed" },
                sortBy: [SortDescriptor(\.createdAt)]
            )
            
            let operations = try context.fetch(descriptor)
            
            guard !operations.isEmpty else {
                return
            }
            
            // Group operations by entity type for batch processing
            let noteOps = operations.filter { $0.entityType == "note" }
            let bookmarkOps = operations.filter { $0.entityType == "bookmark" }
            
            // Existing documents must use v2 so offline edits retain their
            // revision base and participate in automatic merging/history.
            // Keep the legacy batch only for locally-created notes because v2
            // currently assigns a new server ID on creation.
            if !noteOps.isEmpty {
                let locallyCreatedIds = Set(
                    noteOps
                        .filter { $0.operationType == "create" }
                        .compactMap(\.entityId)
                )
                let legacyCreateOps = noteOps.filter { operation in
                    guard let entityId = operation.entityId else { return false }
                    return locallyCreatedIds.contains(entityId)
                }
                let documentOps = noteOps.filter { operation in
                    guard let entityId = operation.entityId else { return true }
                    return !locallyCreatedIds.contains(entityId)
                }

                if !documentOps.isEmpty {
                    await processDocumentOperations(documentOps, context: context)
                }
                if !legacyCreateOps.isEmpty {
                    await processBatchOperations(legacyCreateOps, entityType: "note", context: context)
                }
            }
            
            // Process bookmarks batch
            if !bookmarkOps.isEmpty {
                await processBatchOperations(bookmarkOps, entityType: "bookmark", context: context)
            }
            
            lastSyncTime = Date()
            loadPendingOperationsCount()
            
        } catch {
            AppLogger.sync.error(
                "Error processing operations: \(error.localizedDescription, privacy: .public)"
            )
            lastSyncError = error.localizedDescription
        }
    }

    private func processDocumentOperations(
        _ operations: [SyncOperation],
        context: ModelContext
    ) async {
        for operation in operations {
            guard
                let data = operation.payload,
                let payload = try? JSONDecoder().decode(NoteOperationPayload.self, from: data)
            else {
                markFailed(operation, context: context, message: "Invalid queued note payload")
                continue
            }

            do {
                switch operation.operationType {
                case "update":
                    guard let id = operation.entityId ?? payload.id else {
                        throw APIError.networkError
                    }
                    let note = NoteItem(
                        title: payload.title,
                        content: payload.content ?? "",
                        tags: payload.tags ?? [],
                        isFavorite: payload.isFavorite ?? false,
                        version: payload.version ?? 1
                    )
                    note.id = id
                    note.headRevisionId = payload.headRevisionId
                    _ = try await APIService.shared.updateNote(note)
                case "delete":
                    guard let id = operation.entityId ?? payload.id else {
                        throw APIError.networkError
                    }
                    try await APIService.shared.deleteNote(id: id)
                default:
                    // Creates with temporary local IDs are handled by the
                    // legacy batch path above.
                    continue
                }

                context.delete(operation)
                try context.save()
            } catch {
                markFailed(operation, context: context, message: error.localizedDescription)
            }
        }
    }

    private func markFailed(
        _ operation: SyncOperation,
        context: ModelContext,
        message: String
    ) {
        operation.status = "failed"
        operation.retryCount += 1
        operation.lastError = message
        if operation.retryCount >= 3 {
            context.delete(operation)
        }
        try? context.save()
    }
    
    private func processBatchOperations(
        _ operations: [SyncOperation],
        entityType: String,
        context: ModelContext
    ) async {
        // Convert to API format
        var apiOperations: [[String: Any]] = []
        
        for op in operations {
            guard let payload = op.payload else { continue }
            
            do {
                if let dict = try JSONSerialization.jsonObject(with: payload) as? [String: Any] {
                    var apiOp = dict
                    apiOp["operation"] = op.operationType
                    apiOperations.append(apiOp)
                }
            } catch {
                AppLogger.sync.error(
                    "Failed to parse queued payload: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        
        guard !apiOperations.isEmpty else { return }
        
        // Call batch API
        do {
            let endpoint = entityType == "note" ? "/v1/notes/batch" : "/v1/bookmarks/batch"
            
            // Build request
            var urlComponents = APIConfig.baseURLComponents
            urlComponents.path = endpoint
            
            guard let url = urlComponents.url else {
                AppLogger.sync.fault("Batch sync URL is invalid")
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // Add authentication token
            if let authService = authService,
               let token = await authService.getCurrentAuthToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            } else {
                return
            }
            
            let requestBody = ["operations": apiOperations]
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            // Perform request
            let (_, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                AppLogger.sync.error("Batch sync returned an invalid response")
                return
            }
            
            if httpResponse.statusCode == 200 {
                // Delete successful operations
                for operation in operations {
                    context.delete(operation)
                }
                try? context.save()
            } else {
                AppLogger.sync.error(
                    "Batch sync failed with status \(httpResponse.statusCode, privacy: .public)"
                )
                
                // Mark operations as failed
                for operation in operations {
                    operation.status = "failed"
                    operation.retryCount += 1
                    
                    // Delete if too many retries
                    if operation.retryCount >= 3 {
                        context.delete(operation)
                    }
                }
                try? context.save()
            }
        } catch {
            AppLogger.sync.error(
                "Error syncing batch: \(error.localizedDescription, privacy: .public)"
            )
            
            // Mark operations as failed
            for operation in operations {
                operation.status = "failed"
                operation.retryCount += 1
            }
            try? context.save()
        }
    }
    
    // MARK: - Helpers
    
    func getPendingNotePayloads() -> [UUID: NoteOperationPayload] {
        guard let context = modelContext else { return [:] }
        
        do {
            let descriptor = FetchDescriptor<SyncOperation>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            let operations = try context.fetch(descriptor)

            var payloads: [UUID: NoteOperationPayload] = [:]
            for operation in operations
            where operation.entityType == "note"
                && (operation.status == "pending" || operation.status == "failed") {
                guard
                    let id = operation.entityId,
                    payloads[id] == nil,
                    let data = operation.payload,
                    let payload = try? JSONDecoder().decode(NoteOperationPayload.self, from: data)
                else { continue }
                payloads[id] = payload
            }
            return payloads
        } catch {
            AppLogger.sync.error(
                "Failed to load pending notes: \(error.localizedDescription, privacy: .public)"
            )
            return [:]
        }
    }

    func hasPendingNoteOperation(for noteId: UUID) -> Bool {
        getPendingNotePayloads()[noteId] != nil
    }
    
    private func loadPendingOperationsCount() {
        guard let context = modelContext else { return }
        
        do {
            let descriptor = FetchDescriptor<SyncOperation>(
                predicate: #Predicate { $0.status == "pending" || $0.status == "failed" }
            )
            let operations = try context.fetch(descriptor)
            pendingOperationsCount = operations.count
        } catch {
            AppLogger.sync.error(
                "Failed to load pending count: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
    
    func clearAllOperations() {
        guard let context = modelContext else { return }
        
        do {
            let descriptor = FetchDescriptor<SyncOperation>()
            let operations = try context.fetch(descriptor)
            
            for operation in operations {
                context.delete(operation)
            }
            
            try context.save()
            pendingOperationsCount = 0
        } catch {
            AppLogger.sync.error(
                "Failed to clear operations: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
    
    func retryFailed() async {
        guard let context = modelContext else { return }
        
        do {
            let descriptor = FetchDescriptor<SyncOperation>(
                predicate: #Predicate { $0.status == "failed" }
            )
            let failedOps = try context.fetch(descriptor)
            
            for op in failedOps {
                op.status = "pending"
                op.retryCount += 1
            }
            
            try context.save()
            
            await processPendingOperations()
        } catch {
            AppLogger.sync.error(
                "Failed to retry operations: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
