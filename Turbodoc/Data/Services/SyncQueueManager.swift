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
            print("❌ SyncQueue: Failed to queue operation: \(error)")
        }
    }
    
    func queueNoteOperation(type: String, note: NoteItem) {
        let payload = NoteOperationPayload(
            id: note.id,
            title: note.title,
            content: note.content,
            tags: note.tags,
            isFavorite: note.isFavorite,
            version: note.version
        )
        
        guard let data = try? JSONEncoder().encode(payload) else {
            print("❌ SyncQueue: Failed to encode note payload")
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
            print("❌ SyncQueue: Failed to encode bookmark payload")
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
            
            // Process notes batch
            if !noteOps.isEmpty {
                await processBatchOperations(noteOps, entityType: "note", context: context)
            }
            
            // Process bookmarks batch
            if !bookmarkOps.isEmpty {
                await processBatchOperations(bookmarkOps, entityType: "bookmark", context: context)
            }
            
            lastSyncTime = Date()
            loadPendingOperationsCount()
            
        } catch {
            print("❌ SyncQueue: Error processing operations: \(error)")
            lastSyncError = error.localizedDescription
        }
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
                print("❌ SyncQueue: Failed to parse payload: \(error)")
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
                print("❌ SyncQueue: Invalid URL")
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
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ SyncQueue: Invalid response")
                return
            }
            
            if httpResponse.statusCode == 200 {
                // Delete successful operations
                for operation in operations {
                    context.delete(operation)
                }
                try? context.save()
            } else {
                print("❌ SyncQueue: Batch sync failed with status \(httpResponse.statusCode)")
                
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
            print("❌ SyncQueue: Error syncing batch: \(error)")
            
            // Mark operations as failed
            for operation in operations {
                operation.status = "failed"
                operation.retryCount += 1
            }
            try? context.save()
        }
    }
    
    // MARK: - Helpers
    
    func getPendingNoteIds() -> Set<UUID> {
        guard let context = modelContext else { return [] }
        
        do {
            let descriptor = FetchDescriptor<SyncOperation>()
            let operations = try context.fetch(descriptor)
            
            let noteOperations = operations.filter {
                $0.entityType == "note" &&
                ($0.status == "pending" || $0.status == "failed")
            }
            
            return Set(noteOperations.compactMap { $0.entityId })
        } catch {
            print("❌ SyncQueue: Failed to get pending note IDs: \(error)")
            return []
        }
    }
    
    func getPendingNotePayload(for noteId: UUID) -> NoteOperationPayload? {
        guard let context = modelContext else { return nil }
        
        do {
            let descriptor = FetchDescriptor<SyncOperation>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            let operations = try context.fetch(descriptor)
            
            let noteOperations = operations.filter {
                $0.entityType == "note" &&
                $0.entityId == noteId &&
                ($0.status == "pending" || $0.status == "failed")
            }
            
            if let latestOperation = noteOperations.first,
               let payload = latestOperation.payload,
               let notePayload = try? JSONDecoder().decode(NoteOperationPayload.self, from: payload) {
                return notePayload
            }
        } catch {
            print("❌ SyncQueue: Failed to get pending note payload: \(error)")
        }
        
        return nil
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
            print("❌ SyncQueue: Failed to load pending count: \(error)")
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
            print("❌ SyncQueue: Failed to clear operations: \(error)")
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
            print("❌ SyncQueue: Failed to retry operations: \(error)")
        }
    }
}
