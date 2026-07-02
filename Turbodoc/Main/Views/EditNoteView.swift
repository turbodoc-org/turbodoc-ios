import SwiftUI

enum NoteSaveOutcome {
    case saved
    case queued
    case failed
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
    
    let onSave: (NoteItem) async -> NoteSaveOutcome
    let onFinish: () -> Void
    let onDelete: (NoteItem) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    init(
        note: NoteItem,
        onSave: @escaping (NoteItem) async -> NoteSaveOutcome,
        onFinish: @escaping () -> Void,
        onDelete: @escaping (NoteItem) -> Void
    ) {
        self._note = State(initialValue: note)
        self._originalContent = State(initialValue: note.content)
        self._originalTitle = State(initialValue: note.title)
        self.onSave = onSave
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
            .overlay(alignment: .topTrailing) {
                saveStatusLabel
                    .padding(.top, 8)
                    .padding(.trailing, 20)
                    .allowsHitTesting(false)
            }
            .onChange(of: note.content) {
                scheduleAutoSave()
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
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
        .onDisappear {
            debounceTask?.cancel()
            guard !didDelete else { return }
            Task {
                await saveIfNeeded()
                onFinish()
            }
        }
    }
    
    private func scheduleAutoSave() {
        saveStatus = .unsaved
        debounceTask?.cancel()
        debounceTask = Task {
            do {
                try await Task.sleep(for: .seconds(1.2))
            } catch {
                return
            }
            debounceTask = nil
            await saveIfNeeded()
        }
    }
    
    @MainActor
    private func saveIfNeeded() async {
        let hasChanges = note.content != originalContent || note.title != originalTitle
        guard hasChanges, !isSaving else { return }

        isSaving = true
        saveStatus = .saving

        let snapshot = note.copyForSaving()
        snapshot.updateTimestamp()
        let outcome = await onSave(snapshot)

        switch outcome {
        case .saved:
            originalContent = snapshot.content
            originalTitle = snapshot.title
            saveStatus = .saved
        case .queued:
            originalContent = snapshot.content
            originalTitle = snapshot.title
            saveStatus = .offline
        case .failed:
            saveStatus = .failed
        }
        isSaving = false

        if note.content != originalContent || note.title != originalTitle {
            await saveIfNeeded()
        }
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
