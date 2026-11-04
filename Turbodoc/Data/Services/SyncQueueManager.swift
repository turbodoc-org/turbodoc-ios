import Foundation
import SwiftData
import Combine

extension Notification.Name {
    /// Posted on the main actor after the offline queue changed a note on the
    /// server. The notification's `object` is a `NoteQueueEvent`.
    static let noteQueueDidSync = Notification.Name("turbodoc.noteQueueDidSync")
}

enum NoteQueueEvent {
    /// A queued create or update reached the server. This is the server's
    /// (possibly merged) document.
    case saved(NoteItem)
    /// The note no longer exists on the server.
    case removed(UUID)
    /// The note was deleted on another device while it had queued edits. The
    /// edits were saved as a new note.
    case recovered(originalId: UUID, copy: NoteItem)
}

@MainActor
@Observable
final class SyncQueueManager {
    static let shared = SyncQueueManager()

    @ObservationIgnored private var modelContext: ModelContext?
    @ObservationIgnored private var authService: AuthenticationService?
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var isSyncing = false
    @ObservationIgnored private var needsAnotherPass = false
    /// The note an open editor is syncing itself. Its queued operations wait
    /// until the editor closes.
    @ObservationIgnored private var activeEditorNoteId: UUID?
    /// Earliest next attempt per operation ID. Kept in memory only, so a
    /// relaunch retries straight away.
    @ObservationIgnored private var notBefore: [UUID: Date] = [:]
    @ObservationIgnored private var retryTask: Task<Void, Never>?

    private(set) var pendingOperationsCount = 0
    private(set) var lastSyncTime: Date?
    private(set) var lastSyncError: String?

    private static let maxRetryDelay: TimeInterval = 300

    private init() {
        setupNetworkObserver()
    }

    func configure(modelContext: ModelContext, authService: AuthenticationService? = nil) {
        self.modelContext = modelContext
        if let authService = authService {
            self.authService = authService
        }
        collapseStoredNoteOperations()
        loadPendingOperationsCount()
    }

    private func setupNetworkObserver() {
        NetworkMonitor.shared.connectionStatusChanged
            .sink { [weak self] isConnected in
                guard isConnected else { return }
                Task { @MainActor in
                    guard let self else { return }
                    // Waits were for the network; try everything again now.
                    self.notBefore.removeAll()
                    await self.processPendingOperations()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Editor ownership

    /// While a note is open in an editor, the editor saves it directly and
    /// the queue leaves that note's operations alone.
    func setActiveEditor(_ noteId: UUID) {
        activeEditorNoteId = noteId
    }

    func clearActiveEditor(_ noteId: UUID) {
        guard activeEditorNoteId == noteId else { return }
        activeEditorNoteId = nil
        if hasPendingNoteOperation(for: noteId) {
            Task { await processPendingOperations() }
        }
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

        context.insert(
            SyncOperation(
                operationType: type,
                entityType: entityType,
                entityId: entityId,
                payload: payload
            )
        )
        saveQueue(context)
    }

    /// Queues a note change. Operations for the same note are collapsed, so
    /// the server receives one merged change per note:
    /// - an update to a pending create stays a create with the newer text;
    /// - an update to a pending update keeps the earliest base and takes the
    ///   newest title and content;
    /// - a delete removes pending creates and updates. If a create was
    ///   pending, the note never reached the server and nothing is queued.
    ///
    /// `baseRevisionId` is the revision these edits started from (the
    /// editor's synced revision), not the latest head the app heard about.
    func queueNoteOperation(type: String, note: NoteItem, baseRevisionId: String?) {
        guard let context = modelContext else { return }
        let payload = NoteOperationPayload(
            id: note.id,
            title: note.title,
            content: note.content,
            tags: note.tags,
            isFavorite: note.isFavorite,
            version: note.version,
            headRevisionId: baseRevisionId
        )
        enqueueNote(type: type, noteId: note.id, payload: payload, context: context)
        saveQueue(context)
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

    private func enqueueNote(
        type: String,
        noteId: UUID,
        payload: NoteOperationPayload,
        context: ModelContext
    ) {
        let existing = pendingNoteOperations(for: noteId)

        switch type {
        case "delete":
            let neverReachedServer = existing.contains { $0.operationType == "create" }
            let alreadyQueued = existing.contains { $0.operationType == "delete" }
            for operation in existing where operation.operationType != "delete" {
                notBefore[operation.id] = nil
                context.delete(operation)
            }
            if !neverReachedServer && !alreadyQueued {
                insertNoteOperation(type: "delete", noteId: noteId, payload: payload, context: context)
            }

        case "update":
            // A note that is waiting to be deleted takes no more edits.
            guard !existing.contains(where: { $0.operationType == "delete" }) else { return }

            if let create = existing.first(where: { $0.operationType == "create" }) {
                var merged = Self.decode(create.payload) ?? payload
                merged.title = payload.title
                merged.content = payload.content
                merged.tags = payload.tags
                merged.isFavorite = payload.isFavorite
                merged.version = payload.version
                replacePayload(of: create, with: merged)
            } else if let update = existing.first(where: { $0.operationType == "update" }) {
                var merged = payload
                if let earlier = Self.decode(update.payload) {
                    merged.baseRevisionId = earlier.baseRevisionId
                    merged.recoveryId = earlier.recoveryId
                }
                replacePayload(of: update, with: merged)
            } else {
                insertNoteOperation(type: "update", noteId: noteId, payload: payload, context: context)
            }

        default:
            if let create = existing.first(where: { $0.operationType == "create" }) {
                replacePayload(of: create, with: payload)
            } else {
                insertNoteOperation(type: type, noteId: noteId, payload: payload, context: context)
            }
        }
    }

    private func insertNoteOperation(
        type: String,
        noteId: UUID,
        payload: NoteOperationPayload,
        context: ModelContext
    ) {
        guard let data = Self.encode(payload) else {
            AppLogger.sync.error("Failed to encode note payload")
            return
        }
        context.insert(
            SyncOperation(
                operationType: type,
                entityType: "note",
                entityId: noteId,
                payload: data
            )
        )
    }

    private func replacePayload(of operation: SyncOperation, with payload: NoteOperationPayload) {
        guard let data = Self.encode(payload) else {
            AppLogger.sync.error("Failed to encode note payload")
            return
        }
        operation.payload = data
        // New content deserves a fresh attempt.
        operation.status = "pending"
        operation.retryCount = 0
        operation.lastError = nil
        notBefore[operation.id] = nil
    }

    private func saveQueue(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            AppLogger.sync.error(
                "Failed to queue operation: \(error.localizedDescription, privacy: .public)"
            )
        }
        loadPendingOperationsCount()

        // Try to sync immediately if online
        if NetworkMonitor.shared.isConnected {
            Task {
                await processPendingOperations()
            }
        }
    }

    /// Older builds queued every edit separately. Collapse what they left
    /// behind with the same rules as new operations.
    private func collapseStoredNoteOperations() {
        guard let context = modelContext else { return }
        let operations = fetchPendingOperations().filter { $0.entityType == "note" }
        let byNote = Dictionary(grouping: operations.filter { $0.entityId != nil }) { $0.entityId! }
        var changed = false

        for (noteId, group) in byNote where group.count > 1 {
            let replay = group.compactMap { operation -> (String, NoteOperationPayload)? in
                Self.decode(operation.payload).map { (operation.operationType, $0) }
            }
            // Undecodable operations stay as they are, to be reported as failed.
            for operation in group where Self.decode(operation.payload) != nil {
                context.delete(operation)
            }
            try? context.save()
            for (type, payload) in replay {
                enqueueNote(type: type, noteId: noteId, payload: payload, context: context)
                try? context.save()
            }
            changed = true
        }

        if changed {
            AppLogger.sync.notice("Collapsed queued note operations from an older build")
        }
    }

    // MARK: - Processing

    func processPendingOperations() async {
        guard let context = modelContext else { return }
        guard NetworkMonitor.shared.isConnected else {
            return
        }
        guard !isSyncing else {
            needsAnotherPass = true
            return
        }

        isSyncing = true
        repeat {
            needsAnotherPass = false
            let operations = fetchPendingOperations()

            let noteOps = operations.filter { $0.entityType == "note" }
            let bookmarkOps = operations.filter { $0.entityType == "bookmark" }

            if !noteOps.isEmpty {
                await processNoteOperations(noteOps.map(\.id))
            }

            if !bookmarkOps.isEmpty {
                await processBatchOperations(bookmarkOps, entityType: "bookmark", context: context)
            }

            if !operations.isEmpty {
                lastSyncTime = Date()
            }
            loadPendingOperationsCount()
        } while needsAnotherPass && NetworkMonitor.shared.isConnected
        isSyncing = false

        scheduleRetry()
    }

    /// Sends note operations one at a time. The list is re-read before each
    /// one, since edits may have been collapsed into it meanwhile.
    private func processNoteOperations(_ operationIds: [UUID]) async {
        for operationId in operationIds {
            guard NetworkMonitor.shared.isConnected else { return }
            guard let operation = fetchOperation(operationId) else { continue }
            guard let noteId = operation.entityId else {
                recordFailure(operationId, message: "Queued note operation has no note ID", retryable: false)
                continue
            }
            if noteId == activeEditorNoteId { continue }
            if let wait = notBefore[operationId], wait > Date() { continue }

            guard
                let sent = operation.payload,
                let payload = Self.decode(sent)
            else {
                recordFailure(operationId, message: "Invalid queued note payload", retryable: false)
                continue
            }

            do {
                switch operation.operationType {
                case "create":
                    let result = try await pushCreate(noteId: noteId, payload: payload)
                    completeNoteOperation(
                        operationId,
                        sent: sent,
                        savedRevisionId: result.submittedRevisionId ?? result.note.headRevisionId
                    )
                    post(.saved(result.note))

                case "update":
                    try await pushUpdate(
                        operationId: operationId,
                        noteId: noteId,
                        payload: payload,
                        sent: sent
                    )

                case "delete":
                    do {
                        try await APIService.shared.deleteNote(id: noteId)
                    } catch let error as APIError where error.statusCode == 404 {
                        // Already gone.
                    }
                    completeNoteOperation(operationId, sent: sent, savedRevisionId: nil)
                    post(.removed(noteId))

                default:
                    recordFailure(
                        operationId,
                        message: "Unknown note operation \(operation.operationType)",
                        retryable: false
                    )
                }
            } catch {
                handleNoteFailure(operationId, error: error)
                // Offline: the rest would fail the same way.
                if let apiError = error as? APIError, case .networkError = apiError { return }
            }
        }
    }

    private func pushUpdate(
        operationId: UUID,
        noteId: UUID,
        payload: NoteOperationPayload,
        sent: Data
    ) async throws {
        do {
            let result = try await APIService.shared.saveDocument(
                id: noteId,
                title: payload.title ?? "",
                content: payload.content ?? "",
                // Favorite and tags are not edited offline. Omitting them
                // keeps whatever the server has.
                isFavorite: nil,
                baseRevisionId: payload.baseRevisionId
            )
            completeNoteOperation(
                operationId,
                sent: sent,
                savedRevisionId: result.submittedRevisionId ?? result.note.headRevisionId
            )
            post(.saved(result.note))
        } catch let error as APIError where error.statusCode == 404 {
            try await recoverDeletedNote(operationId: operationId, noteId: noteId, payload: payload)
        }
    }

    /// The note was deleted on another device while it had queued edits.
    /// Keep the edits as a new note titled "<title> (recovered)".
    private func recoverDeletedNote(
        operationId: UUID,
        noteId: UUID,
        payload: NoteOperationPayload
    ) async throws {
        var payload = payload
        let recoveryId = payload.recoveryId ?? UUID()
        if payload.recoveryId == nil, let operation = fetchOperation(operationId) {
            // Fix the copy's ID first, so a retry cannot create two copies.
            payload.recoveryId = recoveryId
            operation.payload = Self.encode(payload)
            try? modelContext?.save()
        }
        guard let sent = fetchOperation(operationId)?.payload ?? Self.encode(payload) else { return }

        let copy = NoteItem(
            title: Self.recoveredTitle(payload.title),
            content: payload.content ?? "",
            tags: payload.tags ?? [],
            isFavorite: payload.isFavorite ?? false
        )
        copy.id = recoveryId
        let created = try await APIService.shared.createDocument(copy)

        if let context = modelContext, let operation = fetchOperation(operationId) {
            if operation.payload == sent {
                context.delete(operation)
            } else if var newer = Self.decode(operation.payload) {
                // More edits arrived meanwhile: they belong to the copy now.
                newer.id = recoveryId
                newer.title = Self.recoveredTitle(newer.title)
                newer.baseRevisionId = created.headRevisionId
                newer.recoveryId = nil
                operation.entityId = recoveryId
                operation.operationType = "update"
                replacePayload(of: operation, with: newer)
            }
            try? context.save()
        }
        notBefore[operationId] = nil

        AppLogger.sync.notice(
            "Note \(noteId.uuidString, privacy: .public) was deleted elsewhere; queued edits saved as \(recoveryId.uuidString, privacy: .public)"
        )
        post(.recovered(originalId: noteId, copy: created))
    }

    private static func recoveredTitle(_ title: String?) -> String {
        let base = (title?.isEmpty == false) ? title! : "Untitled Note"
        return "\(base) (recovered)"
    }

    /// Creates the note under its local ID. Replaying a create that already
    /// reached the server returns the stored document; the queued text is
    /// then saved on top of it.
    private func pushCreate(noteId: UUID, payload: NoteOperationPayload) async throws -> DocumentSaveResult {
        let note = payload.makeNote(id: noteId)
        let created = try await APIService.shared.createDocument(note)
        guard NoteDraft(created) != NoteDraft(note) else {
            return DocumentSaveResult(
                note: created,
                merged: false,
                conflicts: 0,
                submittedRevisionId: created.headRevisionId
            )
        }
        return try await APIService.shared.saveDocument(
            id: noteId,
            title: note.title ?? "",
            content: note.content,
            isFavorite: nil,
            baseRevisionId: created.headRevisionId
        )
    }

    /// The request for an operation succeeded. If newer edits were collapsed
    /// into it meanwhile, keep it as an update based on the revision that
    /// holds what was just sent. Otherwise it is done.
    private func completeNoteOperation(_ operationId: UUID, sent: Data, savedRevisionId: String?) {
        notBefore[operationId] = nil
        guard let context = modelContext, let operation = fetchOperation(operationId) else { return }

        if operation.payload == sent {
            context.delete(operation)
        } else if var newer = Self.decode(operation.payload) {
            newer.baseRevisionId = savedRevisionId
            operation.operationType = "update"
            replacePayload(of: operation, with: newer)
        }
        try? context.save()
    }

    /// Never drops a note operation. Transient failures retry with backoff;
    /// other client errors are marked failed, kept, and retried less often.
    private func handleNoteFailure(_ operationId: UUID, error: Error) {
        let status = (error as? APIError)?.statusCode
        let retryable: Bool
        if let status {
            // "Changing too quickly", rate limited, or a server hiccup.
            retryable = status == 409 || status == 429 || (500...599).contains(status)
        } else {
            // Offline, or a response that could not be read.
            retryable = true
        }
        recordFailure(operationId, message: error.localizedDescription, retryable: retryable)
        AppLogger.sync.error(
            "Note operation failed (status \(status ?? 0, privacy: .public)): \(error.localizedDescription, privacy: .public)"
        )
    }

    private func recordFailure(_ operationId: UUID, message: String, retryable: Bool) {
        guard let operation = fetchOperation(operationId) else { return }
        operation.status = retryable ? "pending" : "failed"
        operation.retryCount += 1
        operation.lastError = message
        notBefore[operationId] = Date().addingTimeInterval(Self.retryDelay(attempt: operation.retryCount))
        try? modelContext?.save()
        lastSyncError = message
    }

    private static func retryDelay(attempt: Int) -> TimeInterval {
        min(maxRetryDelay, 2 * pow(2, Double(max(0, attempt - 1))))
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        retryTask = nil
        let liveIds = Set(fetchPendingOperations().map(\.id))
        notBefore = notBefore.filter { liveIds.contains($0.key) }
        guard let next = notBefore.values.min() else { return }

        let delay = max(1, next.timeIntervalSinceNow)
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.processPendingOperations()
        }
    }

    private func post(_ event: NoteQueueEvent) {
        NotificationCenter.default.post(name: .noteQueueDidSync, object: event)
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
            let endpoint = "/v1/bookmarks/batch"

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

    // MARK: - Editor helpers

    /// The queued change for a note, if any: its type and payload.
    func pendingNoteOperation(for noteId: UUID) -> (type: String, payload: NoteOperationPayload)? {
        guard
            let operation = pendingNoteOperations(for: noteId).last,
            let payload = Self.decode(operation.payload)
        else { return nil }
        return (operation.operationType, payload)
    }

    func hasPendingCreate(for noteId: UUID) -> Bool {
        pendingNoteOperations(for: noteId).contains { $0.operationType == "create" }
    }

    /// Sends a note's queued create now, for an editor that owns the note.
    /// Returns nil when no create is queued.
    func pushPendingCreate(for noteId: UUID) async throws -> DocumentSaveResult? {
        guard
            let operation = pendingNoteOperations(for: noteId).first(where: { $0.operationType == "create" }),
            let sent = operation.payload,
            let payload = Self.decode(sent)
        else { return nil }

        let operationId = operation.id
        let result = try await pushCreate(noteId: noteId, payload: payload)
        completeNoteOperation(
            operationId,
            sent: sent,
            savedRevisionId: result.submittedRevisionId ?? result.note.headRevisionId
        )
        loadPendingOperationsCount()
        return result
    }

    /// After an editor saved a note: its queued updates are contained in
    /// that save.
    func removePendingNoteUpdates(for noteId: UUID) {
        removePendingNoteOperations(for: noteId) { $0.operationType == "update" }
    }

    /// After a note was deleted on the server.
    func discardPendingNoteOperations(for noteId: UUID) {
        removePendingNoteOperations(for: noteId) { _ in true }
    }

    private func removePendingNoteOperations(for noteId: UUID, where shouldRemove: (SyncOperation) -> Bool) {
        guard let context = modelContext else { return }
        let operations = pendingNoteOperations(for: noteId).filter(shouldRemove)
        guard !operations.isEmpty else { return }
        for operation in operations {
            notBefore[operation.id] = nil
            context.delete(operation)
        }
        try? context.save()
        loadPendingOperationsCount()
    }

    // MARK: - Helpers

    func getPendingNotePayloads() -> [UUID: NoteOperationPayload] {
        var payloads: [UUID: NoteOperationPayload] = [:]
        for operation in fetchPendingOperations().reversed()
        where operation.entityType == "note" && operation.operationType != "delete" {
            guard
                let id = operation.entityId,
                payloads[id] == nil,
                let payload = Self.decode(operation.payload)
            else { continue }
            payloads[id] = payload
        }
        return payloads
    }

    /// Notes waiting to be deleted on the server.
    func pendingNoteDeletions() -> Set<UUID> {
        Set(
            fetchPendingOperations()
                .filter { $0.entityType == "note" && $0.operationType == "delete" }
                .compactMap(\.entityId)
        )
    }

    func hasPendingNoteOperation(for noteId: UUID) -> Bool {
        !pendingNoteOperations(for: noteId).isEmpty
    }

    private func pendingNoteOperations(for noteId: UUID) -> [SyncOperation] {
        fetchPendingOperations().filter { $0.entityType == "note" && $0.entityId == noteId }
    }

    /// Pending and failed operations, oldest first.
    private func fetchPendingOperations() -> [SyncOperation] {
        guard let context = modelContext else { return [] }
        do {
            let descriptor = FetchDescriptor<SyncOperation>(
                predicate: #Predicate { $0.status == "pending" || $0.status == "failed" },
                sortBy: [SortDescriptor(\.createdAt)]
            )
            return try context.fetch(descriptor)
        } catch {
            AppLogger.sync.error(
                "Failed to load pending operations: \(error.localizedDescription, privacy: .public)"
            )
            return []
        }
    }

    private func fetchOperation(_ id: UUID) -> SyncOperation? {
        guard let context = modelContext else { return nil }
        var descriptor = FetchDescriptor<SyncOperation>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func decode(_ data: Data?) -> NoteOperationPayload? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(NoteOperationPayload.self, from: data)
    }

    private static func encode(_ payload: NoteOperationPayload) -> Data? {
        try? JSONEncoder().encode(payload)
    }

    private func loadPendingOperationsCount() {
        pendingOperationsCount = fetchPendingOperations().count
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
            notBefore.removeAll()
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
                notBefore[op.id] = nil
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

extension NoteOperationPayload {
    func makeNote(id: UUID) -> NoteItem {
        let note = NoteItem(
            title: title,
            content: content ?? "",
            tags: tags ?? [],
            isFavorite: isFavorite ?? false,
            version: version ?? 1
        )
        note.id = id
        note.headRevisionId = baseRevisionId
        return note
    }
}
