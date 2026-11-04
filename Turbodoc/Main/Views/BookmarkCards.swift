import SwiftUI

extension BookmarkItem {
    /// "cloudflare.com" for "https://www.cloudflare.com/…".
    var domain: String {
        guard let url, let host = URL(string: url)?.host else { return url ?? "" }
        return host.replacingOccurrences(of: "www.", with: "")
    }
}

// MARK: - Gallery card

/// Two-column gallery card: preview image on top, title and metadata below.
struct BookmarkGalleryCard: View {
    let bookmark: BookmarkItem
    let onDelete: (BookmarkItem) -> Void
    let onUpdate: (BookmarkItem, BookmarkChanges) -> Void
    let onToggleFavorite: (BookmarkItem) -> Void

    @State private var showingEditor = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 9) {
                BookmarkPreview(bookmark: bookmark)
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(bookmark.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        // Same height for every card, so rows line up.
                        .lineLimit(2, reservesSpace: true)

                    BookmarkMeta(bookmark: bookmark, showsUnreadDot: true)
                        .font(.caption)
                }
                .padding(.horizontal, 6)
            }
            .padding(5)
            .padding(.bottom, 7)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Theme.surface, in: cardShape)
            .overlay {
                cardShape.strokeBorder(
                    bookmark.isLinkBroken ? Theme.danger : Theme.line,
                    lineWidth: 1
                )
            }
        }
        .buttonStyle(CardPressButtonStyle())
        // Kept outside the card's button so tapping them doesn't open the link.
        .overlay(alignment: .topTrailing) {
            if !bookmark.isLinkBroken {
                favoriteButton.padding(11)
            }
        }
        .overlay(alignment: .topLeading) {
            if bookmark.isLinkBroken {
                BrokenLinkBadge().padding(12)
            }
        }
        .contentShape(.contextMenuPreview, cardShape)
        .contextMenu {
            BookmarkMenuItems(
                bookmark: bookmark,
                onEdit: { showingEditor = true },
                onUpdate: onUpdate,
                onToggleFavorite: onToggleFavorite,
                onDelete: onDelete
            )
        }
        .sheet(isPresented: $showingEditor) {
            BookmarkEditView(bookmark: bookmark) { changes in
                onUpdate(bookmark, changes)
            }
        }
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
    }

    private var favoriteButton: some View {
        Button {
            onToggleFavorite(bookmark)
        } label: {
            Image(systemName: bookmark.isFavorite ? "star.fill" : "star")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(bookmark.isFavorite ? Theme.favorite : .primary)
                .frame(width: 28, height: 28)
                .background(.ultraThinMaterial, in: Circle())
                // A comfortable touch target around the small visual.
                .frame(width: 44, height: 44, alignment: .topTrailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(-8)
        .accessibilityLabel(bookmark.isFavorite ? "Unfavorite" : "Favorite")
    }

    private func open() {
        guard let urlString = bookmark.url, let url = URL(string: urlString) else { return }
        openURL(url)
    }
}

// MARK: - List row

/// Compact row: thumbnail, title and metadata, unread dot or favorite star.
struct BookmarkListRow: View {
    let bookmark: BookmarkItem
    let onDelete: (BookmarkItem) -> Void
    let onUpdate: (BookmarkItem, BookmarkChanges) -> Void
    let onToggleFavorite: (BookmarkItem) -> Void

    @State private var showingEditor = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                BookmarkPreview(bookmark: bookmark, compact: true)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        if bookmark.isLinkBroken {
                            Image(systemName: "link")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(Theme.danger, in: Circle())
                                .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 2))
                                .offset(x: 4, y: 4)
                        }
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(bookmark.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)

                    BookmarkMeta(bookmark: bookmark, showsUnreadDot: false)
                        .font(.footnote)
                }
                // Start the separator under the text, like Mail.
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }

                Spacer(minLength: 0)

                if bookmark.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.favorite)
                } else if bookmark.status == .unread && !bookmark.isLinkBroken {
                    Circle()
                        .fill(Theme.unread)
                        .frame(width: 9, height: 9)
                        .accessibilityLabel("Unread")
                }
            }
            .contentShape(Rectangle())
        }
        .contextMenu {
            BookmarkMenuItems(
                bookmark: bookmark,
                onEdit: { showingEditor = true },
                onUpdate: onUpdate,
                onToggleFavorite: onToggleFavorite,
                onDelete: onDelete
            )
        }
        .sheet(isPresented: $showingEditor) {
            BookmarkEditView(bookmark: bookmark) { changes in
                onUpdate(bookmark, changes)
            }
        }
    }

    private func open() {
        guard let urlString = bookmark.url, let url = URL(string: urlString) else { return }
        openURL(url)
    }
}

// MARK: - Shared pieces

/// "● cloudflare.com · 2d", or the failure reason for a broken link.
struct BookmarkMeta: View {
    let bookmark: BookmarkItem
    let showsUnreadDot: Bool

    var body: some View {
        HStack(spacing: 5) {
            if bookmark.isLinkBroken {
                Label(bookmark.linkFailureDescription, systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(.titleAndIcon)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.danger)
            } else {
                if showsUnreadDot && bookmark.status == .unread {
                    Circle()
                        .fill(Theme.unread)
                        .frame(width: 7, height: 7)
                        .accessibilityLabel("Unread")
                }
                Text(details)
                    .foregroundStyle(Theme.faint)
            }
        }
        .lineLimit(1)
    }

    private var details: String {
        var parts = [bookmark.domain, bookmark.timeAdded.compactDisplay]
        if bookmark.status == .archived { parts.insert("Archived", at: 0) }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// The bookmark's OG image, or a letter tile on a soft background while it
/// loads or when the page has none.
struct BookmarkPreview: View {
    let bookmark: BookmarkItem
    var compact = false

    @State private var imageURL: String?

    init(bookmark: BookmarkItem, compact: Bool = false) {
        self.bookmark = bookmark
        self.compact = compact
        _imageURL = State(initialValue: bookmark.ogImageURL)
    }

    var body: some View {
        ZStack {
            fallback

            if let imageURL, let url = URL(string: imageURL) {
                Color.clear
                    .overlay {
                        RemoteImage(url: url) { Color.clear }
                    }
                    .clipped()
            }
        }
        // Desaturate dead links so they stand out at a glance.
        .grayscale(bookmark.isLinkBroken ? 1 : 0)
        .opacity(bookmark.isLinkBroken ? 0.55 : 1)
        .task(id: bookmark.url) { await loadImageURL() }
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        Theme.thumb
            .overlay {
                VStack(spacing: 7) {
                    Text(initial)
                        .font(.system(size: compact ? 15 : 19, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: compact ? 30 : 38, height: compact ? 30 : 38)
                        .background(
                            fallbackGradient(for: bookmark.domain),
                            in: RoundedRectangle(cornerRadius: compact ? 9 : 11, style: .continuous)
                        )

                    if !compact {
                        Text(bookmark.domain)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.faint)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                    }
                }
            }
    }

    private var initial: String {
        bookmark.domain.first.map { String($0).uppercased() } ?? "•"
    }

    @MainActor
    private func loadImageURL() async {
        if let known = bookmark.ogImageURL {
            imageURL = known
            return
        }
        guard let url = bookmark.url else { return }
        // Looked up earlier this session (possibly with no image found).
        if let lookedUp = OGImageLookupCache.result(for: url) {
            imageURL = lookedUp
            return
        }
        // A dead link has no page to read an image from.
        guard !bookmark.isLinkBroken else { return }

        let fetched = try? await APIService.shared.fetchOgImage(for: url).ogImage
        // Scrolled away before the lookup finished: try again next time.
        guard !Task.isCancelled else { return }
        OGImageLookupCache.store(fetched, for: url)
        bookmark.ogImageURL = fetched
        imageURL = fetched
    }
}

/// Context menu shared by gallery cards and list rows.
struct BookmarkMenuItems: View {
    let bookmark: BookmarkItem
    let onEdit: () -> Void
    let onUpdate: (BookmarkItem, BookmarkChanges) -> Void
    let onToggleFavorite: (BookmarkItem) -> Void
    let onDelete: (BookmarkItem) -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        if let url {
            Button {
                openURL(url)
            } label: {
                Label("Open Link", systemImage: "safari")
            }

            Button {
                UIPasteboard.general.url = url
                HapticManager.shared.success()
            } label: {
                Label("Copy Link", systemImage: "doc.on.doc")
            }

            ShareLink(item: url, subject: Text(bookmark.title)) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }

        Button(action: onEdit) {
            Label("Edit", systemImage: "pencil")
        }

        Divider()

        Button {
            onToggleFavorite(bookmark)
        } label: {
            Label(
                bookmark.isFavorite ? "Unfavorite" : "Favorite",
                systemImage: bookmark.isFavorite ? "star.slash" : "star"
            )
        }

        if bookmark.status == .unread {
            statusButton("Mark as Read", systemImage: "checkmark.circle", status: .read)
        } else {
            statusButton("Mark as Unread", systemImage: "circlebadge", status: .unread)
        }

        if bookmark.status != .archived {
            statusButton("Archive", systemImage: "archivebox", status: .archived)
        }

        Divider()

        Button(role: .destructive) {
            onDelete(bookmark)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private var url: URL? {
        bookmark.url.flatMap(URL.init(string:))
    }

    private func statusButton(
        _ title: String,
        systemImage: String,
        status: BookmarkItem.ItemStatus
    ) -> some View {
        Button {
            HapticManager.shared.selection()
            onUpdate(bookmark, BookmarkChanges(status: status))
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}

/// Red "Broken link" capsule shown on bookmarks the link checker flagged.
struct BrokenLinkBadge: View {
    var body: some View {
        Label("Broken link", systemImage: "link")
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Theme.danger, in: Capsule())
    }
}
