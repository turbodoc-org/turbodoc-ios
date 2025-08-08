import SwiftUI

struct AddNoteView: View {
    @State private var content: String = ""
    @State private var title: String = ""
    @State private var isAutoSaving: Bool = false
    @State private var saveTimer: Timer?
    @State private var draftNote: NoteItem?
    
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
                        .padding(.vertical, title.isEmpty ? 16 : 8)
                        .onChange(of: title) {
                            scheduleAutoSave()
                        }
                }
                .background(
                    Rectangle()
                        .fill(Color(.systemGray6))
                        .opacity(title.isEmpty ? 0 : 1)
                )
                
                Divider()
                
                // Content editor with improved styling
                VStack(alignment: .leading, spacing: 0) {
                    if !content.isEmpty {
                        HStack {
                            Text("CONTENT")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                                .padding(.leading, 20)
                                .padding(.top, 16)
                            
                            Spacer()
                            
                            if isAutoSaving {
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    Text("Saving...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.trailing, 20)
                                .padding(.top, 16)
                            }
                        }
                    }
                    
                    TextEditor(text: $content)
                        .font(.body)
                        .lineSpacing(2)
                        .padding(.horizontal, 16)
                        .padding(.vertical, content.isEmpty ? 20 : 8)
                        .background(Color(.systemBackground))
                        .onChange(of: content) {
                            scheduleAutoSave()
                        }
                        .overlay(alignment: .topLeading) {
                            if content.isEmpty {
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
            .onDisappear {
                saveTimer?.invalidate()
            }
        }
    }
    
    private func scheduleAutoSave() {
        saveTimer?.invalidate()
        
        // Only auto-save if there's content
        let hasContent = !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        if hasContent {
            saveTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
                autoSaveNote()
            }
        }
    }
    
    private func autoSaveNote() {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Don't save completely empty notes
        guard !trimmedContent.isEmpty || !trimmedTitle.isEmpty else { return }
        
        isAutoSaving = true
        
        if let existingNote = draftNote {
            // Update existing draft
            existingNote.title = trimmedTitle.isEmpty ? nil : trimmedTitle
            existingNote.content = trimmedContent
            existingNote.updateTimestamp()
            onSave(existingNote)
        } else {
            // Create new draft
            let note = NoteItem(
                title: trimmedTitle.isEmpty ? nil : trimmedTitle,
                content: trimmedContent,
                userId: authService.currentUser?.id ?? ""
            )
            draftNote = note
            onSave(note)
        }
        
        // Hide saving indicator after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            isAutoSaving = false
        }
    }
    
    private func finishNote() {
        // Final save before dismissing
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !trimmedContent.isEmpty || !trimmedTitle.isEmpty {
            if let existingNote = draftNote {
                existingNote.title = trimmedTitle.isEmpty ? nil : trimmedTitle
                existingNote.content = trimmedContent
                existingNote.updateTimestamp()
                onSave(existingNote)
            } else {
                let note = NoteItem(
                    title: trimmedTitle.isEmpty ? nil : trimmedTitle,
                    content: trimmedContent,
                    userId: authService.currentUser?.id ?? ""
                )
                onSave(note)
            }
        }
        
        dismiss()
    }
    
    private func cancelNote() {
        // If there's a draft note and it has no content, we might want to delete it
        // For now, just dismiss
        dismiss()
    }
}
