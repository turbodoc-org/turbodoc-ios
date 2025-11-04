import SwiftUI

struct EditNoteView: View {
    @State private var note: NoteItem
    @State private var originalContent: String
    @State private var originalTitle: String?
    @State private var saveTimer: Timer?
    @State private var isAutoSaving: Bool = false
    @State private var showingDeleteConfirmation: Bool = false
    
    let onSave: (NoteItem) -> Void
    let onDelete: (NoteItem) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    init(note: NoteItem, onSave: @escaping (NoteItem) -> Void, onDelete: @escaping (NoteItem) -> Void) {
        self._note = State(initialValue: note)
        self._originalContent = State(initialValue: note.content)
        self._originalTitle = State(initialValue: note.title)
        self.onSave = onSave
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
                .padding(.vertical, (note.title?.isEmpty ?? true) ? 16 : 8)
            }
            .background(
                Rectangle()
                    .fill(Color(.systemGray6))
                    .opacity((note.title?.isEmpty ?? true) ? 0 : 1)
            )
            
            Divider()
            
            // Content editor with improved styling
            VStack(alignment: .leading, spacing: 0) {
                TextEditor(text: $note.content)
                    .font(.body)
                    .lineSpacing(2)
                    .padding(.horizontal, 16)
                    .padding(.vertical, note.content.isEmpty ? 20 : 8)
                    .background(Color(.systemBackground))
                    .onChange(of: note.content) {
                        scheduleAutoSave()
                    }
                    .overlay(alignment: .topLeading) {
                        if note.content.isEmpty {
                            Text("Start writing your note...")
                                .font(.body)
                                .foregroundColor(.secondary.opacity(0.6))
                                .padding(.horizontal, 21)
                                .padding(.vertical, 28)
                                .allowsHitTesting(false)
                        }
                    }
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
            saveIfNeeded()
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
}
