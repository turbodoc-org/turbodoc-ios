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
    var userId: String
    var localFilePath: String?
    var textContent: String?
    var thumbnailPath: String?
    var ogImageURL: String?
    var fileName: String?
    var fileSize: Int64
    var metadata: [String: String]?
    
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
    
    init(title: String, url: String?, contentType: ContentType, userId: String) {
        self.id = UUID()
        self.title = title
        self.url = url
        self.contentType = contentType
        self.userId = userId
        self.timeAdded = Date()
        self.tags = []
        self.status = .unread
        self.ogImageURL = nil
        self.fileName = nil
        self.fileSize = 0
        self.metadata = nil
    }
}