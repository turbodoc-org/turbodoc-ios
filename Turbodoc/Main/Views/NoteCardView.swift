import SwiftUI

/// Gallery card: a "paper" preview of the note's Markdown on top, title and
/// date below.
struct NoteCardView: View {
    let note: NoteItem
    let onEdit: (NoteItem) -> Void
    let onDelete: (NoteItem) -> Void
    let onToggleFavorite: (NoteItem) -> Void

    var body: some View {
        Button {
            onEdit(note)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                paper

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.noteAccent)

                        Text(note.displayTitle)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            // Same height for every card, so rows line up.
                            .lineLimit(2, reservesSpace: true)
                    }

                    Text(NoteMetadata(note: note).text)
                        .font(.caption)
                        .foregroundStyle(Theme.faint)
                        .lineLimit(1)
                        .padding(.leading, 21)
                }
                .padding(.horizontal, 6)
            }
            .padding(5)
            .padding(.bottom, 7)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Theme.surface, in: cardShape)
            .overlay(cardShape.strokeBorder(Theme.line, lineWidth: 1))
        }
        .buttonStyle(CardPressButtonStyle())
        .contentShape(.contextMenuPreview, cardShape)
        .contextMenu {
            NoteMenuItems(
                note: note,
                onEdit: onEdit,
                onToggleFavorite: onToggleFavorite,
                onDelete: onDelete
            )
        }
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
    }

    private var paper: some View {
        let blocks = previewBlocks
        return VStack(alignment: .leading, spacing: 5) {
            if blocks.isEmpty {
                Text("No additional text")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.faint)
            } else {
                MarkdownPreviewBlocks(blocks: blocks)
            }
            Spacer(minLength: 0)
        }
        .padding([.top, .horizontal], 11)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 118)
        .background(Theme.thumb)
        .overlay(alignment: .bottom) {
            // Fade long notes out instead of cutting a line in half.
            LinearGradient(colors: [Theme.thumb.opacity(0), Theme.thumb], startPoint: .top, endPoint: .bottom)
                .frame(height: 22)
        }
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Theme.thumbLine, lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            if note.isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.favorite)
                    .padding(8)
                    .accessibilityLabel("Favorite")
            }
        }
    }

    /// The note's blocks, minus a first heading that just repeats the title.
    private var previewBlocks: [MarkdownPreviewBlock] {
        var blocks = MarkdownPreviewBlock.parse(note.content, limit: 7)
        if case .heading(let text)? = blocks.first, text == note.displayTitle {
            blocks.removeFirst()
        } else if case .paragraph(let text)? = blocks.first, note.title == nil, text.hasPrefix(note.displayTitle) {
            blocks.removeFirst()
        }
        return blocks
    }
}

/// "Yesterday · 1 of 3 done"
struct NoteMetadata {
    let note: NoteItem

    var dateText: String { note.updatedAt.compactDisplay }

    var progressText: String? {
        let progress = MarkdownPreviewBlock.taskProgress(in: note.content)
        guard progress.total > 0 else { return nil }
        return "\(progress.done) of \(progress.total) done"
    }

    var text: String {
        [dateText, progressText].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Context menu shared by note cards and rows.
struct NoteMenuItems: View {
    let note: NoteItem
    let onEdit: (NoteItem) -> Void
    let onToggleFavorite: (NoteItem) -> Void
    let onDelete: (NoteItem) -> Void

    var body: some View {
        Button {
            onEdit(note)
        } label: {
            Label("Open", systemImage: "doc.text")
        }

        Button {
            onToggleFavorite(note)
        } label: {
            Label(
                note.isFavorite ? "Unfavorite" : "Favorite",
                systemImage: note.isFavorite ? "star.slash" : "star"
            )
        }

        Button {
            UIPasteboard.general.string = note.content
            HapticManager.shared.success()
        } label: {
            Label("Copy Text", systemImage: "doc.on.doc")
        }

        ShareLink(item: note.content, subject: Text(note.displayTitle)) {
            Label("Share", systemImage: "square.and.arrow.up")
        }

        Divider()

        Button(role: .destructive) {
            onDelete(note)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}
