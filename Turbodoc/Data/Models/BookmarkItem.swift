import Foundation
import SwiftData

@Model
class BookmarkItem {
    var id: UUID
    var title: String
    var url: String?
    var contentType: ContentType
    var timeAdded: Date
    var tags: [String]
    var status: ItemStatus
    var isFavorite: Bool
    var userId: String
    var version: Int = 1
    var localFilePath: String?
    var textContent: String?
    var thumbnailPath: String?
    var ogImageURL: String?
    var fileName: String?
    var fileSize: Int64
    var metadata: [String: String]?
    var syncedAt: Date?
    var linkStatus: LinkStatus?
    var linkStatusCode: Int?
    var linkError: String?
    
    enum ContentType: String, CaseIterable, Codable {
        case link = "link"
        case image = "image"
        case video = "video"
        case text = "text"
        case file = "file"
    }
    
    enum ItemStatus: String, CaseIterable, Codable {
        case unread = "unread"
        case read = "read"
        case archived = "archived"
    }
    
    /// Link health from the API's link checker. A link is only `broken` after
    /// two consecutive failed checks at least a day apart.
    enum LinkStatus: String, CaseIterable, Codable {
        case unknown = "unknown"
        case ok = "ok"
        case broken = "broken"
    }
    
    var isLinkBroken: Bool {
        linkStatus == .broken
    }
    
    /// Why the link is broken: "404 Not found", "Timed out", "Unreachable".
    var linkFailureDescription: String {
        if let code = linkStatusCode {
            let reasons = [
                404: "Not found",
                410: "Gone",
                500: "Server error",
                502: "Bad gateway",
                503: "Unavailable",
                504: "Gateway timeout",
            ]
            if let reason = reasons[code] ?? (code >= 500 ? "Server error" : nil) {
                return "\(code) \(reason)"
            }
            return "HTTP \(code)"
        }
        let error = linkError?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return error.isEmpty ? "Unreachable" : error
    }
    
    /// Applies the fields set in `changes` and returns their previous values,
    /// so an optimistic update can be rolled back.
    @discardableResult
    func apply(_ changes: BookmarkChanges) -> BookmarkChanges {
        let previous = BookmarkChanges(
            title: changes.title.map { _ in title },
            url: changes.url.map { _ in url ?? "" },
            tags: changes.tags.map { _ in tags },
            status: changes.status.map { _ in status },
            isFavorite: changes.isFavorite.map { _ in isFavorite }
        )
        if let title = changes.title { self.title = title }
        if let url = changes.url { self.url = url }
        if let tags = changes.tags { self.tags = tags }
        if let status = changes.status { self.status = status }
        if let isFavorite = changes.isFavorite { self.isFavorite = isFavorite }
        return previous
    }
    
    init(title: String, url: String?, contentType: ContentType, userId: String) {
        self.id = UUID()
        self.title = title
        self.url = url
        self.contentType = contentType
        self.userId = userId
        self.timeAdded = Date()
        self.tags = []
        self.status = .unread
        self.isFavorite = false
        self.ogImageURL = nil
        self.fileName = nil
        self.fileSize = 0
        self.metadata = nil
    }
}

/// The bookmark fields a user edit touches; `nil` means unchanged.
struct BookmarkChanges {
    var title: String?
    var url: String?
    var tags: [String]?
    var status: BookmarkItem.ItemStatus?
    var isFavorite: Bool?
    
    var isEmpty: Bool {
        title == nil && url == nil && tags == nil && status == nil && isFavorite == nil
    }
}