import SwiftUI

/// Apple Notes style row: title, then the date and the note's first line.
struct NoteListRowView: View {
    let note: NoteItem
    let onEdit: (NoteItem) -> Void
    let onDelete: (NoteItem) -> Void
    let onToggleFavorite: (NoteItem) -> Void

    var body: some View {
        let metadata = NoteMetadata(note: note)

        Button {
            onEdit(note)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.displayTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(metadata.dateText)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    if let progress = metadata.progressText {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.square")
                                .imageScale(.small)
                            Text(progress)
                        }
                    } else {
                        Text(snippet)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(Theme.faint)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        // Rows read as content, not accent-colored buttons.
        .tint(Color.primary)
        .contextMenu {
            NoteMenuItems(
                note: note,
                onEdit: onEdit,
                onToggleFavorite: onToggleFavorite,
                onDelete: onDelete
            )
        }
    }

    private var snippet: String {
        MarkdownPreviewBlock.snippet(from: note.content, excluding: note.displayTitle)
            ?? "No additional text"
    }
}
