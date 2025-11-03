import SwiftUI

struct NoteCardView: View {
    let note: NoteItem
    let onEdit: (NoteItem) -> Void
    let onDelete: (NoteItem) -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        cardContent
            .frame(width: 160, height: 160) // Fixed square size
            .background(cardBackground)
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .shadow(
                color: Color.black.opacity(0.1),
                radius: isPressed ? 2 : 6,
                x: 0,
                y: isPressed ? 1 : 3
            )
            .animation(.easeInOut(duration: 0.15), value: isPressed)
            .onTapGesture {
                onEdit(note)
            }
            .onLongPressGesture {
                onDelete(note)
            }
            .onPressStateChanged { pressed in
                isPressed = pressed
            }
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
                
                if !note.content.isEmpty {
                    Text(note.previewContent)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(5)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(1)
                }
            }
            .padding(.top, 16)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            
            Spacer()
        }
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

// Custom modifier for press state
struct PressStateModifier: ViewModifier {
    let onPressStateChanged: (Bool) -> Void
    
    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        onPressStateChanged(true)
                    }
                    .onEnded { _ in
                        onPressStateChanged(false)
                    }
            )
    }
}

extension View {
    func onPressStateChanged(_ action: @escaping (Bool) -> Void) -> some View {
        self.modifier(PressStateModifier(onPressStateChanged: action))
    }
}
