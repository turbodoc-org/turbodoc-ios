import SwiftUI

enum NoteSaveOutcome {
    case saved(NoteItem)
    case queued
    case failed
}

private enum NoteRestoreError: LocalizedError {
    case pendingSync

    var errorDescription: String? {
        "This note has offline changes waiting to sync. Restore it after those changes are online."
    }
}

struct EditNoteView: View {
    @State private var note: NoteItem
    @State private var originalContent: String
    @State private var originalTitle: String?
    @State private var debounceTask: Task<Void, Never>?
    @State private var isSaving = false
    @State private var saveStatus: SaveStatus = .saved
    @State private var showingDeleteConfirmation: Bool = false
    @State private var didDelete = false
    @State private var showingHistory = false
    @State private var isRestoring = false
    
    let onSave: (NoteItem) async -> NoteSaveOutcome
    let onRestore: (NoteItem) -> Void
    let onFinish: () -> Void
    let onDelete: (NoteItem) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    init(
        note: NoteItem,
        onSave: @escaping (NoteItem) async -> NoteSaveOutcome,
        onRestore: @escaping (NoteItem) -> Void,
        onFinish: @escaping () -> Void,
        onDelete: @escaping (NoteItem) -> Void
    ) {
        self._note = State(initialValue: note)
        self._originalContent = State(initialValue: note.content)
        self._originalTitle = State(initialValue: note.title)
        self.onSave = onSave
        self.onRestore = onRestore
        self.onFinish = onFinish
        self.onDelete = onDelete
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Title editor with elegant design
            VStack(alignment: .leading, spacing: 8) {
                TextField("Note title (optional)", text: Binding(
                    get: { note.title ?? "" },
                    set: { newValue in
                        note.title = newValue.isEmpty ? nil : newValue
                        scheduleAutoSave()
                    }
                ))
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            
            Divider()
            
            MarkdownEditor(text: $note.content)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 16)
            .onChange(of: note.content) {
                scheduleAutoSave()
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                saveStatusLabel
                    .allowsHitTesting(false)

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
                onDelete(note)
                dismiss()
            }
        } message: {
            Text("Are you sure you want to delete \"\(note.displayTitle)\"? This action cannot be undone.")
        }
        .sheet(isPresented: $showingHistory) {
            DocumentHistoryView(note: note) { revision in
                try await restore(revision)
            }
        }
        .onDisappear {
            debounceTask?.cancel()
            guard !didDelete else { return }
            Task {
                _ = await saveIfNeeded()
                onFinish()
            }
        }
    }
    
    private func scheduleAutoSave() {
        guard !isRestoring else { return }
        saveStatus = .unsaved
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
        let hasChanges = note.content != originalContent || note.title != originalTitle
        guard hasChanges else { return true }
        guard !isSaving else { return false }

        isSaving = true
        saveStatus = .saving

        let snapshot = note.copyForSaving()
        snapshot.updateTimestamp()
        let outcome = await onSave(snapshot)
        var savedToServer = false

        switch outcome {
        case .saved(let savedNote):
            // Preserve any edits made while the request was in flight, but
            // adopt the server's new revision head for the next merge.
            note.headRevisionId = savedNote.headRevisionId
            note.version = savedNote.version
            note.updatedAt = savedNote.updatedAt
            note.syncedAt = Date()
            originalContent = snapshot.content
            originalTitle = snapshot.title
            saveStatus = .saved
            savedToServer = true
        case .queued:
            originalContent = snapshot.content
            originalTitle = snapshot.title
            saveStatus = .offline
        case .failed:
            saveStatus = .failed
        }
        isSaving = false

        if note.content != originalContent || note.title != originalTitle {
            return await saveIfNeeded()
        }
        return savedToServer
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
        note = restored
        originalContent = restored.content
        originalTitle = restored.title
        saveStatus = .saved
        onRestore(restored)
        showingHistory = false
        return restored
    }

    @ViewBuilder
    private var saveStatusLabel: some View {
        if saveStatus != .saved {
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
            .foregroundStyle(saveStatus == .failed ? Color.red : Color.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
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
            case .offline: return "icloud.slash"
            case .failed: return "exclamationmark.triangle.fill"
            default: return "circle"
            }
        }
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
                                Text(revision.name ?? "Version \(revision.revision_number)").font(.headline)
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
                    .navigationTitle(revision.name ?? "Version \(revision.revision_number)")
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
