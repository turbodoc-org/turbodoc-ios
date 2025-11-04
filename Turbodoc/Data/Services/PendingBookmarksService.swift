import Foundation

class PendingBookmarksService {
    static let shared = PendingBookmarksService()
    
    private let appGroupIdentifier = "group.ai.turbodoc.ios.Turbodoc"
    private weak var authService: AuthenticationService?
    
    private init() {}
    
    // MARK: - Configuration
    
    func configure(authService: AuthenticationService) {
        self.authService = authService
    }
    
    // MARK: - Public Methods
    
    /// Processes all pending bookmarks from the share extension
    func processPendingBookmarks() async {
        let pendingBookmarks = getPendingBookmarks()
        
        guard !pendingBookmarks.isEmpty else {
            return
        }
        
        for (_, bookmarkData) in pendingBookmarks.enumerated() {
            do {
                let bookmark = try await createBookmarkFromShareData(bookmarkData)
                let savedBookmark = try await APIService.shared.saveBookmark(bookmark)
            } catch {
                // Continue processing other bookmarks even if one fails
            }
        }
        
        // Clear processed bookmarks
        clearPendingBookmarks()
        
        // Update local bookmark cache for deduplication
        updateLocalBookmarkCache()
    }
    
    // MARK: - Private Methods
    
    private func getPendingBookmarks() -> [[String: Any]] {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return []
        }
        
        let bookmarksURL = containerURL.appendingPathComponent("pendingBookmarks.json")
        
        guard FileManager.default.fileExists(atPath: bookmarksURL.path) else {
            return []
        }
        
        do {
            let data = try Data(contentsOf: bookmarksURL)
            if let bookmarks = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                return bookmarks
            }
        } catch {
            // Silent error handling
        }
        
        return []
    }
    
    private func clearPendingBookmarks() {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return
        }
        
        let bookmarksURL = containerURL.appendingPathComponent("pendingBookmarks.json")
        
        do {
            if FileManager.default.fileExists(atPath: bookmarksURL.path) {
                try FileManager.default.removeItem(at: bookmarksURL)
            }
        } catch {
            // Silent error handling
        }
    }
    
    private func createBookmarkFromShareData(_ data: [String: Any]) async throws -> BookmarkItem {
        guard let url = data["url"] as? String,
              let type = data["type"] as? String,
              let title = data["title"] as? String else {
            throw PendingBookmarkError.invalidData
        }
        
        // Determine content type based on share extension type
        let contentType: BookmarkItem.ContentType
        switch type {
        case "url":
            contentType = .link
        case "image":
            contentType = .image
        case "video":
            contentType = .video
        case "text":
            contentType = .text
        case "file":
            contentType = .file
        default:
            contentType = .link
        }
        
        // Create the bookmark item
        let bookmark = BookmarkItem(
            title: title.isEmpty ? extractTitleFromURL(url) : title,
            url: url,
            contentType: contentType,
            userId: await getCurrentUserId()
        )
        
        // Try to fetch OG image for URLs
        if contentType == .link, let actualURL = URL(string: url) {
            do {
                let ogResponse = try await APIService.shared.fetchOgImage(for: url)
                if let ogImageURL = ogResponse.ogImage {
                    bookmark.ogImageURL = ogImageURL
                }
                if let ogTitle = ogResponse.title, title.isEmpty {
                    bookmark.title = ogTitle
                }
            } catch {
                // Continue without OG image - not a critical failure
            }
        }
        
        return bookmark
    }
    
    private func extractTitleFromURL(_ urlString: String) -> String {
        guard let url = URL(string: urlString) else {
            return "Shared Content"
        }
        
        // Try to get a meaningful title from the URL
        if let host = url.host {
            return host.replacingOccurrences(of: "www.", with: "")
        }
        
        return "Shared Content"
    }
    
    private func getCurrentUserId() async -> String {
        // Get the current user ID from the authentication service
        if let authService = authService {
            let currentUser = await MainActor.run {
                return authService.currentUser
            }
            
            if let currentUser = currentUser {
                return currentUser.id
            }
        }
        
        // Fallback - this should not happen in normal flow
        return "unknown-user"
    }
    
    private func updateLocalBookmarkCache() {
        // Fetch all bookmarks from the server and update local cache for deduplication
        Task {
            do {
                guard let currentUserId = await getCurrentUserId() as String?,
                      currentUserId != "unknown-user" else {
                    return
                }
                
                let bookmarks = try await APIService.shared.fetchBookmarks(userId: currentUserId)
                
                guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
                    return
                }
                
                let cacheURL = containerURL.appendingPathComponent("savedBookmarks.json")
                
                let bookmarkData = bookmarks.compactMap { bookmark -> [String: Any]? in
                    guard let url = bookmark.url else { return nil }
                    return [
                        "url": url,
                        "type": bookmark.contentType.rawValue,
                        "title": bookmark.title,
                        "timestamp": bookmark.timeAdded.timeIntervalSince1970
                    ]
                }
                
                let data = try JSONSerialization.data(withJSONObject: bookmarkData)
                try data.write(to: cacheURL)
                
            } catch {
                // Silent error handling
            }
        }
    }
}

// MARK: - Error Types

enum PendingBookmarkError: Error {
    case invalidData
    case noAuthenticatedUser
    case processingFailed(String)
    
    var localizedDescription: String {
        switch self {
        case .invalidData:
            return "Invalid bookmark data from share extension"
        case .noAuthenticatedUser:
            return "No authenticated user found"
        case .processingFailed(let message):
            return "Failed to process bookmark: \(message)"
        }
    }
}
