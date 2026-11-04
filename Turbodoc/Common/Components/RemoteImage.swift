import SwiftUI
import UIKit

/// A remote image backed by an in-memory cache.
///
/// `AsyncImage` refetches and redecodes whenever a list cell is reused, which
/// makes scrolling stutter and flashes the placeholder. This keeps decoded
/// images around for the session and decodes them off the main thread.
struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: UIImage?

    init(url: URL?, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.placeholder = placeholder
        // Start with the cached image so reused cells never flash the placeholder.
        _image = State(initialValue: url.flatMap { RemoteImageCache.image(for: $0) })
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        guard let url else { return }
        if let cached = RemoteImageCache.image(for: url) {
            image = cached
            return
        }

        guard
            let (data, _) = try? await URLSession.shared.data(from: url),
            let decoded = UIImage(data: data)
        else { return }

        let prepared = await decoded.byPreparingForDisplay() ?? decoded
        RemoteImageCache.store(prepared, for: url)
        guard !Task.isCancelled else { return }
        image = prepared
    }
}

enum RemoteImageCache {
    private static let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 300
        return cache
    }()

    static func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    static func store(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}

/// Remembers OG image lookups for the session, including pages that have none,
/// so bookmark tiles don't hit the API again every time they scroll into view.
@MainActor
enum OGImageLookupCache {
    private static var results: [String: String?] = [:]

    /// `nil` when the URL hasn't been looked up; `.some(nil)` when it has no image.
    static func result(for url: String) -> String?? {
        results[url]
    }

    static func store(_ imageURL: String?, for url: String) {
        results[url] = .some(imageURL)
    }
}
