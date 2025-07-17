import Foundation

// MARK: - API Request/Response Models

struct APIBookmarkRequest: Codable {
    let title: String
    let url: String?
    let tags: [String]
    let status: String
    
    init(from bookmarkItem: BookmarkItem) {
        self.title = bookmarkItem.title
        self.url = bookmarkItem.url
        self.tags = bookmarkItem.tags
        self.status = bookmarkItem.status.rawValue
    }
}

struct APIBookmarkResponse: Codable {
    let id: String
    let user_id: String
    let title: String
    let url: String?
    let time_added: String
    let tags: [String]
    let status: String
    let created_at: String
    let updated_at: String
    
    func toBookmarkItem() -> BookmarkItem {
        let bookmark = BookmarkItem(
            title: title,
            url: url,
            contentType: .link, // Default to link, can be enhanced later
            userId: user_id
        )
        
        // Parse the ID from string to UUID
        if let uuid = UUID(uuidString: id) {
            bookmark.id = uuid
        }
        
        // Parse time_added
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        if let date = formatter.date(from: time_added) {
            bookmark.timeAdded = date
        }
        
        bookmark.tags = tags
        bookmark.status = BookmarkItem.ItemStatus(rawValue: status) ?? .unread
        
        return bookmark
    }
}

struct APIBookmarkListResponse: Codable {
    let bookmarks: [APIBookmarkResponse]
    let total: Int
    let page: Int
    let per_page: Int
}

struct APIUserResponse: Codable {
    let id: String
    let email: String
    let name: String?
    let created_at: String
    let updated_at: String
    
    func toUser() -> User {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        let user = User(id: id, email: email, name: name)
        
        if let createdDate = formatter.date(from: created_at) {
            user.createdAt = createdDate
        }
        
        if let updatedDate = formatter.date(from: updated_at) {
            user.updatedAt = updatedDate
        }
        
        return user
    }
}

struct APIUserUpdateRequest: Codable {
    let name: String?
    let email: String?
}