import SwiftUI

struct NoteCardView: View {
    let note: NoteItem
    let onEdit: (NoteItem) -> Void
    let onDelete: (NoteItem) -> Void
    let onToggleFavorite: (NoteItem) -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        cardContent
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .aspectRatio(1, contentMode: .fit) // Keep square aspect ratio
            .background(cardBackground)
            .overlay(alignment: .topTrailing) {
                favoriteButton
            }
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .shadow(
                color: Color.black.opacity(0.1),
                radius: isPressed ? 2 : 6,
                x: 0,
                y: isPressed ? 1 : 3
            )
            .animation(.easeInOut(duration: 0.15), value: isPressed)
            .onTapGesture {
                HapticManager.shared.light()
                onEdit(note)
            }
            .onLongPressGesture(minimumDuration: 0.5) {
                HapticManager.shared.medium()
                onDelete(note)
            }
    }
    
    private var favoriteButton: some View {
        Button(action: {
            HapticManager.shared.light()
            onToggleFavorite(note)
        }) {
            Image(systemName: note.isFavorite ? "star.fill" : "star")
                .font(.system(size: 12))
                .foregroundColor(note.isFavorite ? .yellow : .gray)
                .padding(8)
        }
        .buttonStyle(.plain)
    }
    
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with title
            VStack(alignment: .leading, spacing: 8) {
                Text(note.displayTitle)
                    .font(.headline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                if !note.content.isEmpty {
                    Text(note.previewContent)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(5)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 16)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(.systemGray3), lineWidth: 1)
            )
    }
    
    private func wordCount(_ text: String) -> Int {
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        return words.filter { !$0.isEmpty }.count
    }
}
