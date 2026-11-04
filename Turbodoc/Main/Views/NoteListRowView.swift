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
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        // The default style gives the standard row highlight on tap.
        .buttonStyle(.automatic)
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
            onDelete(note)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
    
    private func copyContent() {
        UIPasteboard.general.string = note.content
        HapticManager.shared.success()
    }
    
    private func shareNote() {
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
