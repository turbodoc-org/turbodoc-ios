import SwiftUI

struct NoteListRowView: View {
    let note: NoteItem
    let onEdit: (NoteItem) -> Void
    let onDelete: (NoteItem) -> Void
    
    var body: some View {
        Button(action: {
            onEdit(note)
        }) {
            HStack(spacing: 12) {
                // Note icon
                Image(systemName: "note.text")
                    .font(.footnote)
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.blue.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.displayTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            contextMenuContent
        }
    }
    
    @ViewBuilder
    private var contextMenuContent: some View {
        Button(action: {
            onEdit(note)
        }) {
            Label("Edit Note", systemImage: "pencil")
        }
        
        Button(action: copyContent) {
            Label("Copy Content", systemImage: "doc.on.doc")
        }
        
        Button(action: shareNote) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        
        Divider()
        
        Button(role: .destructive) {
            HapticManager.shared.warning()
            onDelete(note)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
    
    private func copyContent() {
        HapticManager.shared.selection()
        UIPasteboard.general.string = note.content
    }
    
    private func shareNote() {
        HapticManager.shared.selection()
        let activityVC = UIActivityViewController(
            activityItems: [note.content],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityVC, animated: true)
        }
    }
}
