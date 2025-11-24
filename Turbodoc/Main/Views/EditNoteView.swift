import SwiftUI

struct EditNoteView: View {
    @State private var note: NoteItem
    @State private var originalContent: String
    @State private var originalTitle: String?
    @State private var saveTimer: Timer?
    @State private var isAutoSaving: Bool = false
    @State private var showingDeleteConfirmation: Bool = false
    
    let onSave: (NoteItem) -> Void
    let onFinish: () -> Void
    let onDelete: (NoteItem) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    init(note: NoteItem, onSave: @escaping (NoteItem) -> Void, onFinish: @escaping () -> Void, onDelete: @escaping (NoteItem) -> Void) {
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
            
            // Markdown editor
            MarkdownEditor(
                text: $note.content,
                disableMarkdown: containsEmojis(note.content)
            )
            .id("markdown-editor-\(note.id)-\(containsEmojis(note.content))")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
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
                onDelete(note)
                dismiss()
            }
        } message: {
            Text("Are you sure you want to delete \"\(note.displayTitle)\"? This action cannot be undone.")
        }
        .onDisappear {
            finishEditing()
            saveTimer?.invalidate()
        }
    }
    
    private func scheduleAutoSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
            saveIfNeeded()
        }
    }
    
    private func saveIfNeeded() {
        let hasChanges = note.content != originalContent || note.title != originalTitle
        
        if hasChanges {
            isAutoSaving = true
            note.updateTimestamp()
            onSave(note)
            originalContent = note.content
            originalTitle = note.title
            
            // Hide saving indicator after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                isAutoSaving = false
            }
        }
    }
    
    private func finishEditing() {
        saveIfNeeded()
        onFinish()
    }
    
    // MARK: - Emoji Detection
    
    /// Checks if the text contains emojis that could cause crashes with markdown rendering
    private func containsEmojis(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            // Check for actual emoji characters that cause NSTextStorage issues
            if scalar.properties.isEmoji && scalar.properties.isEmojiPresentation {
                return true
            }
            if scalar.properties.isEmojiModifier || scalar.properties.isEmojiModifierBase {
                return true
            }
        }
        return false
    }
}
