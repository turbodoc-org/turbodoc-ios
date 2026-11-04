import SwiftUI
import Combine

enum NoteSaveOutcome {
    case saved(DocumentSaveResult)
    /// Offline: the edits are queued and stay unsynced in the editor.
    case queued
    /// The server refused the save. Retried on the next edit.
    case failed
    /// The note was deleted on another device.
    case deleted
}

private enum NoteRestoreError: LocalizedError {
    case pendingSync
    
    var errorDescription: String? {
        "This note has offline changes waiting to sync. Restore it after those changes are online."
    }
}

struct EditNoteView: View {
    @State private var note: NoteItem
    /// The last document this editor agreed on with the server. Its revision
    /// is the base of every save, so the server merges in anything newer.
    @State private var synced: SyncedState
    /// The offline queue held edits for this note when it was opened, or
    /// took a save while offline. The editor sends them itself.
    @State private var hasQueuedEdits = false
    @State private var debounceTask: Task<Void, Never>?
    @State private var statusDismissTask: Task<Void, Never>?
    @State private var isSaving = false
    @State private var saveStatus: SaveStatus = .saved
    @State private var isSaveStatusVisible = false
    @State private var showingDeleteConfirmation: Bool = false
    @State private var didDelete = false
    @State private var showingHistory = false
    @State private var isRestoring = false
    @State private var showsConflictNotice = false
    @State private var conflictNoticeTask: Task<Void, Never>?
    @State private var wasDeletedElsewhere = false
    @State private var showingDeletedElsewhere = false
    @State private var editorController = MarkdownEditorController()
    /// Highest version another device's save was reported at.
    @State private var latestRemoteVersion = 0
    
    /// Saves a snapshot of the note on top of the given base revision.
    let onSave: (NoteItem, String?) async -> NoteSaveOutcome
    /// A newer server version was loaded (restore, or another device's edit).
    let onServerUpdate: (NoteItem) -> Void
    let onFinish: () -> Void
    let onDelete: (NoteItem) -> Void
    /// Saves the draft as a new note (after it was deleted elsewhere).
    let onKeepCopy: (NoteItem) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var authService: AuthenticationService
    
    init(
        note: NoteItem,
        onSave: @escaping (NoteItem, String?) async -> NoteSaveOutcome,
        onServerUpdate: @escaping (NoteItem) -> Void,
        onFinish: @escaping () -> Void,
        onDelete: @escaping (NoteItem) -> Void,
        onKeepCopy: @escaping (NoteItem) -> Void
    ) {
        self._note = State(initialValue: note)
        self._synced = State(initialValue: SyncedState(note))
        self.onSave = onSave
        self.onServerUpdate = onServerUpdate
        self.onFinish = onFinish
        self.onDelete = onDelete
        self.onKeepCopy = onKeepCopy
    }
    
    private var draft: NoteDraft {
        NoteDraft(note)
    }
    
    /// True while the server lacks something the editor holds.
    private var needsSave: Bool {
        hasQueuedEdits || NoteSync.hasUnsyncedEdits(draft, synced)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Title editor with elegant design
            VStack(alignment: .leading, spacing: 8) {
                TextField("Note title (optional)", text: Binding(
                    get: { note.title ?? "" },
                    set: { newValue in
                        note.title = newValue.isEmpty ? nil : newValue
                        draftChanged()
                    }
                ))
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            
            Divider()
            
            MarkdownEditor(text: $note.content, controller: editorController)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 16)
                .onChange(of: note.content) {
                    draftChanged()
                }
        }
        .overlay(alignment: .top) {
            if showsConflictNotice {
                conflictNotice
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                saveStatusLabel
                    .padding(.leading, 8)
                    .allowsHitTesting(false)
                
                MarkdownEditorHistoryButtons(controller: editorController)
                
                Menu {
                    Button {
                        showingHistory = true
                    } label: {
                        Label("Version History", systemImage: "clock.arrow.circlepath")
                    }
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete Note", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.primary)
                }
            }
        }
        .alert("Delete Note", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                didDelete = true
                debounceTask?.cancel()
                statusDismissTask?.cancel()
                onDelete(note)
                dismiss()
            }
        } message: {
            Text("Are you sure you want to delete \"\(note.displayTitle)\"? This action cannot be undone.")
        }
        .alert("Note Deleted", isPresented: $showingDeletedElsewhere) {
            Button("Keep a Copy") {
                keepCopy()
            }
            Button("Discard", role: .destructive) {
                dismiss()
            }
        } message: {
            Text("This note was deleted on another device.")
        }
        .sheet(isPresented: $showingHistory) {
            DocumentHistoryView(note: note) { revision in
                try await restore(revision)
            }
        }
        .onAppear {
            takeOwnership()
        }
        .task(id: note.id) {
            await followOtherDevices()
        }
        .onChange(of: scenePhase) {
            // Back from the background: catch up on edits made meanwhile.
            if scenePhase == .active {
                Task { await loadServerVersion() }
            }
        }
        .onReceive(NetworkMonitor.shared.connectionStatusChanged) { isConnected in
            // Back online: this editor sends its own unsynced edits.
            guard isConnected, needsSave, !wasDeletedElsewhere else { return }
            Task { await saveIfNeeded() }
        }
        .onDisappear {
            debounceTask?.cancel()
            statusDismissTask?.cancel()
            conflictNoticeTask?.cancel()
            let noteId = note.id
            guard !didDelete, !wasDeletedElsewhere else {
                SyncQueueManager.shared.clearActiveEditor(noteId)
                if wasDeletedElsewhere { onFinish() }
                return
            }
            Task {
                while isSaving {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                _ = await saveIfNeeded()
                if needsSave || wasDeletedElsewhere {
                    // Not saved (offline, refused, or deleted meanwhile). The
                    // queue keeps retrying and recovers a deleted note as a
                    // copy, so the edits are never dropped.
                    SyncQueueManager.shared.queueNoteOperation(
                        type: "update",
                        note: note.copyForSaving(),
                        baseRevisionId: synced.revisionId
                    )
                }
                SyncQueueManager.shared.clearActiveEditor(noteId)
                onFinish()
            }
        }
    }
    
    /// While open, the editor syncs this note itself, including edits the
    /// queue still held for it.
    private func takeOwnership() {
        SyncQueueManager.shared.setActiveEditor(note.id)
        
        guard
            !hasQueuedEdits,
            let pending = SyncQueueManager.shared.pendingNoteOperation(for: note.id),
            pending.type != "delete"
        else { return }
        
        hasQueuedEdits = true
        if pending.type == "update" {
            // The queued edits started from this revision, so it stays the base.
            synced.revisionId = pending.payload.baseRevisionId
        }
        if NetworkMonitor.shared.isConnected {
            Task { await saveIfNeeded() }
        }
    }
    
    /// Loads other devices' edits while the note is open. Ends when the view
    /// goes away, which also closes the Realtime channel.
    private func followOtherDevices() async {
        // The list's copy may be older than the server's.
        await loadServerVersion()
        
        for await event in authService.noteUpdates(id: note.id) {
            switch event {
            case .updated(let version):
                // Echoes of this editor's own saves are already in `synced`.
                if let version {
                    latestRemoteVersion = max(latestRemoteVersion, version)
                    guard version > synced.version else { continue }
                }
                await loadServerVersion()
            case .resubscribed:
                // Saves made while disconnected were not reported.
                await loadServerVersion()
            }
        }
    }
    
    /// Fetches the note and loads it if the editor is idle. With unsaved
    /// edits, or a save in flight, the editor keeps its text and its base:
    /// the next save merges with the newer version instead.
    @MainActor
    private func loadServerVersion() async {
        guard
            !wasDeletedElsewhere,
            !isRestoring,
            !hasQueuedEdits,
            NetworkMonitor.shared.isConnected
        else { return }
        
        let remote: NoteItem
        do {
            remote = try await APIService.shared.fetchDocument(id: note.id)
        } catch let error as APIError where error.statusCode == 404 {
            // Without a revision the note may simply not be created yet.
            guard synced.revisionId != nil, !isSaving, !wasDeletedElsewhere, !didDelete else { return }
            wasDeletedElsewhere = true
            debounceTask?.cancel()
            debounceTask = nil
            showingDeletedElsewhere = true
            return
        } catch {
            AppLogger.notes.error(
                "Could not load the latest note: \(error.localizedDescription, privacy: .public)"
            )
            return
        }
        
        latestRemoteVersion = max(latestRemoteVersion, remote.version)
        await takeUnpostedEdits()
        guard
            !hasQueuedEdits,
            let decision = NoteSync.onRemote(
                remote: ServerDocument(remote),
                synced: synced,
                latest: draft,
                saving: isSaving
            )
        else { return }
        
        synced = decision.synced
        if let adopt = decision.adopt {
            applyServerDraft(adopt)
        }
        note.headRevisionId = remote.headRevisionId
        note.version = remote.version
        note.updatedAt = remote.updatedAt
        note.isFavorite = remote.isFavorite
        note.tags = remote.tags
        onServerUpdate(remote)
    }
    
    private func draftChanged() {
        guard !isRestoring, !wasDeletedElsewhere else { return }
        guard needsSave else {
            // Back to the synced text: undone, or the server's version was
            // just loaded. Nothing to save.
            debounceTask?.cancel()
            debounceTask = nil
            if saveStatus == .unsaved { setSaveStatus(.saved) }
            return
        }
        setSaveStatus(.unsaved)
        debounceTask?.cancel()
        debounceTask = Task {
            do {
                try await Task.sleep(for: .seconds(1.2))
            } catch {
                return
            }
            debounceTask = nil
            _ = await saveIfNeeded()
        }
    }
    
    @MainActor
    @discardableResult
    private func saveIfNeeded() async -> Bool {
        guard !wasDeletedElsewhere else { return false }
        guard needsSave else { return true }
        guard !isSaving else { return false }
        
        isSaving = true
        setSaveStatus(.saving)
        
        let sent = draft
        let snapshot = note.copyForSaving()
        snapshot.updateTimestamp()
        // Always the revision the editor's edits started from, never just
        // the newest head it heard about.
        let outcome = await onSave(snapshot, synced.revisionId)
        var savedToServer = false
        
        switch outcome {
        case .saved(let result):
            await takeUnpostedEdits()
            let decision = NoteSync.afterSave(
                sent: sent,
                latest: draft,
                response: result.syncResponse
            )
            // Set before loading the server's draft, so the change it causes
            // compares equal and does not schedule another save.
            synced = decision.synced
            hasQueuedEdits = false
            if let adopt = decision.adopt {
                applyServerDraft(adopt)
            }
            note.headRevisionId = result.note.headRevisionId
            note.version = result.note.version
            note.updatedAt = result.note.updatedAt
            note.syncedAt = Date()
            // This save already contains anything queued for the note.
            SyncQueueManager.shared.removePendingNoteUpdates(for: note.id)
            if result.conflicts > 0 {
                presentConflictNotice()
            }
            setSaveStatus(.saved)
            savedToServer = true
        case .queued:
            // The edits stay unsynced: the base is still the last revision
            // the server confirmed.
            hasQueuedEdits = true
            setSaveStatus(.offline)
        case .failed:
            setSaveStatus(.failed)
        case .deleted:
            wasDeletedElsewhere = true
            debounceTask?.cancel()
            debounceTask = nil
            setSaveStatus(.failed)
            showingDeletedElsewhere = true
        }
        isSaving = false
        
        // Typing continued during the save: send the rest.
        if savedToServer && needsSave {
            return await saveIfNeeded()
        }
        // Another device saved while this save was in flight and the
        // response did not include it: load it now that the editor is idle.
        if savedToServer && latestRemoteVersion > synced.version {
            Task { await loadServerVersion() }
        }
        return savedToServer
    }
    
    /// Typing from the last fraction of a second may not have reached Swift
    /// yet. Take it before deciding whether server content may replace the
    /// editor's.
    @MainActor
    private func takeUnpostedEdits() async {
        if let markdown = await editorController.flushPendingEdits(), markdown != note.content {
            note.content = markdown
        }
    }
    
    /// Loads the server's version into the editor. `synced` already matches
    /// it, so `draftChanged` sees nothing to save.
    private func applyServerDraft(_ adopt: NoteDraft) {
        note.title = adopt.title.isEmpty ? nil : adopt.title
        note.content = adopt.content
    }
    
    private func keepCopy() {
        let copy = NoteItem(
            title: note.title,
            content: note.content,
            tags: note.tags,
            userId: note.userId,
            isFavorite: note.isFavorite
        )
        onKeepCopy(copy)
        dismiss()
    }
    
    @MainActor
    private func restore(_ revision: APIDocumentRevision) async throws -> NoteItem {
        debounceTask?.cancel()
        debounceTask = nil
        
        // The restore must be the last server write. Finish an active save,
        // then flush any draft that had not reached the debounce yet.
        while isSaving {
            try await Task.sleep(for: .milliseconds(50))
        }
        let savedToServer = await saveIfNeeded()
        while isSaving {
            try await Task.sleep(for: .milliseconds(50))
        }
        guard
            savedToServer,
            !SyncQueueManager.shared.hasPendingNoteOperation(for: note.id)
        else {
            throw NoteRestoreError.pendingSync
        }
        
        isRestoring = true
        defer { isRestoring = false }
        
        let restored = try await APIService.shared.restoreDocumentRevision(
            documentId: note.id,
            revisionId: revision.id
        )
        synced = SyncedState(restored)
        hasQueuedEdits = false
        note = restored
        setSaveStatus(.saved)
        onServerUpdate(restored)
        showingHistory = false
        return restored
    }
    
    private var conflictNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.triangle.merge")
                .foregroundStyle(.secondary)
            Text("This note was also edited on another device. Where you both changed the same passage, both versions were kept.")
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                dismissConflictNotice()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
    
    private func presentConflictNotice() {
        conflictNoticeTask?.cancel()
        withAnimation(.easeOut(duration: 0.25)) {
            showsConflictNotice = true
        }
        conflictNoticeTask = Task {
            do {
                try await Task.sleep(for: .seconds(8))
            } catch {
                return
            }
            dismissConflictNotice()
        }
    }
    
    private func dismissConflictNotice() {
        conflictNoticeTask?.cancel()
        conflictNoticeTask = nil
        withAnimation(.easeInOut(duration: 0.25)) {
            showsConflictNotice = false
        }
    }
    
    @ViewBuilder
    private var saveStatusLabel: some View {
        if isSaveStatusVisible {
            HStack(spacing: 5) {
                if saveStatus == .saving {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: saveStatus.icon)
                }
                Text(saveStatus.label)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(
                saveStatus == .failed
                ? Color.red
                : saveStatus == .saved ? Color.green.opacity(0.85) : Color.secondary
            )
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .transition(.saveStatusBadge)
            .animation(.easeInOut(duration: 0.2), value: saveStatus)
        }
    }
    
    @MainActor
    private func setSaveStatus(_ status: SaveStatus) {
        statusDismissTask?.cancel()
        
        withAnimation(.easeOut(duration: 0.24)) {
            saveStatus = status
            isSaveStatusVisible = true
        }
        
        guard status == .saved else { return }
        statusDismissTask = Task {
            do {
                try await Task.sleep(for: .seconds(1.1))
            } catch {
                return
            }
            
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.4)) {
                isSaveStatusVisible = false
            }
        }
    }
    
    private enum SaveStatus: Equatable {
        case saved
        case unsaved
        case saving
        case offline
        case failed
        
        var label: String {
            switch self {
            case .saved: return "Saved"
            case .unsaved: return "Unsaved"
            case .saving: return "Saving"
            case .offline: return "Saved offline"
            case .failed: return "Save failed"
            }
        }
        
        var icon: String {
            switch self {
            case .saved: return "checkmark.circle.fill"
            case .offline: return "icloud.slash"
            case .failed: return "exclamationmark.triangle.fill"
            default: return "circle"
            }
        }
    }
}

private struct SaveStatusRevealModifier: ViewModifier {
    let progress: CGFloat
    
    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .scaleEffect(x: progress, y: 1, anchor: .trailing)
    }
}

private extension AnyTransition {
    static var saveStatusBadge: AnyTransition {
        .modifier(
            active: SaveStatusRevealModifier(progress: 0),
            identity: SaveStatusRevealModifier(progress: 1)
        )
    }
}

private struct DocumentHistoryView: View {
    let note: NoteItem
    let onRestore: (APIDocumentRevision) async throws -> NoteItem
    @State private var revisions: [APIDocumentRevision] = []
    @State private var selected: APIDocumentRevision?
    @State private var loading = true
    @State private var restoring = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Loading history…")
                } else if revisions.isEmpty {
                    ContentUnavailableView("No Versions", systemImage: "clock", description: Text("A version appears after the first save."))
                } else {
                    List(revisions) { revision in
                        Button {
                            selected = revision
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(revision.displayName).font(.headline)
                                Text(revision.change_summary ?? revision.device_id ?? "Automatic revision")
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Version History")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .task { await load() }
            .alert("History unavailable", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
                .sheet(item: $selected) { revision in
                    NavigationStack {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                Text(revision.title.isEmpty ? "Untitled Note" : revision.title).font(.title2.bold())
                                Text(revision.markdown).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding()
                        }
                        .navigationTitle(revision.displayName)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Restore") { Task { await restore(revision) } }.disabled(restoring)
                            }
                        }
                    }
                }
        }
    }
    
    @MainActor private func load() async {
        do { revisions = try await APIService.shared.fetchDocumentRevisions(id: note.id) }
        catch { errorMessage = error.localizedDescription }
        loading = false
    }
    
    @MainActor private func restore(_ revision: APIDocumentRevision) async {
        restoring = true
        defer { restoring = false }
        do { _ = try await onRestore(revision) }
        catch { errorMessage = error.localizedDescription }
    }
}
