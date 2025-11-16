import SwiftUI

struct AddNoteView: View {
    @State private var content: String = ""
    @State private var title: String = ""
    @State private var note: NoteItem?
    
    let onSave: (NoteItem) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authService: AuthenticationService
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Title input with clean design
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Note title (optional)", text: $title)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                }
                
                Divider()
                
                // Markdown editor
                MarkdownEditor(text: $content)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 16)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        cancelNote()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        finishNote()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private func finishNote() {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !trimmedContent.isEmpty || !trimmedTitle.isEmpty {
            // No draft exists, create new note (shouldn't happen with auto-save)
            note = NoteItem(
                title: trimmedTitle.isEmpty ? nil : trimmedTitle,
                content: trimmedContent,
                userId: authService.currentUser?.id ?? ""
            )
            onSave(note!)
        }
        
        dismiss()
    }
    
    private func cancelNote() {
        // If there's a draft note and it has no content, we might want to delete it
        // For now, just dismiss
        dismiss()
    }
}
