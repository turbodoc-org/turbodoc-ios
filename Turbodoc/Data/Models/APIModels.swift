import Foundation

// MARK: - API Request/Response Models

struct APIBookmarkRequest: Codable {
    let title: String
    let url: String?
    let tags: String
    let status: String
    let is_favorite: Bool
    
    init(from bookmarkItem: BookmarkItem) {
        self.title = bookmarkItem.title
        self.url = bookmarkItem.url
        self.tags = bookmarkItem.tags.joined(separator: "|")
        self.status = bookmarkItem.status.rawValue
        self.is_favorite = bookmarkItem.isFavorite
    }
}

struct APIBookmarkResponse: Codable {
    let id: String
    let user_id: String
    let title: String
    let url: String?
    let time_added: Int
    private let tags: TagsContainer?
    let status: String
    let created_at: String
    let updated_at: String
    let ogImage: String?
    let is_favorite: Bool?
    
    enum CodingKeys: String, CodingKey {
        case id, user_id, title, url, time_added, tags, status, created_at, updated_at, ogImage,
             is_favorite
    }
    
    var tagsList: [String] {
        return tags?.array ?? []
    }
    
    func toBookmarkItem() -> BookmarkItem {
        let bookmark = BookmarkItem(
            title: title,
            url: url,
            contentType: .link,  // Default to link, can be enhanced later
            userId: user_id
        )
        
        // Parse the ID from string to UUID
        if let uuid = UUID(uuidString: id) {
            bookmark.id = uuid
        }
        
        // Parse time_added as Unix timestamp
        bookmark.timeAdded = Date(timeIntervalSince1970: TimeInterval(time_added))
        
        bookmark.tags = tagsList
        bookmark.status = BookmarkItem.ItemStatus(rawValue: status) ?? .unread
        bookmark.ogImageURL = ogImage
        bookmark.isFavorite = is_favorite ?? false
        
        return bookmark
    }
}

struct APIBookmarkListResponse: Codable {
    let data: [APIBookmarkResponse]
    let total: Int?
    let page: Int?
    let per_page: Int?
}

struct APIBookmarkCreateResponse: Codable {
    let data: APIBookmarkResponse
}

struct APIBookmarkUpdateResponse: Codable {
    let data: APIBookmarkResponse
}

struct APIBookmarkSearchResponse: Codable {
    let data: [APIBookmarkResponse]
    let query: String
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

struct APIOgImageResponse: Codable {
    let ogImage: String?
    let title: String?
}

// MARK: - Tags API Models

struct APITagItem: Codable {
    let tag: String
    let count: Int
}

struct APITagsResponse: Codable {
    let data: [APITagItem]
}

// MARK: - Note API Models

struct APITranscriptionResponse: Codable {
    let text: String
}

struct APINoteRequest: Codable {
    let title: String?
    let content: String
    let tags: String
    let is_favorite: Bool
    let markdown: String
    let base_revision_id: String?
    let device_id: String
    
    init(from noteItem: NoteItem) {
        self.title = noteItem.title
        self.content = noteItem.content
        self.tags = noteItem.tags.joined(separator: "|")
        self.is_favorite = noteItem.isFavorite
        self.markdown = noteItem.content
        self.base_revision_id = noteItem.headRevisionId
        self.device_id = DocumentDevice.identifier
    }
}

struct APINoteResponse: Codable {
    let id: String
    let user_id: String
    let title: String?
    let markdown: String
    private let tags: TagsContainer?
    let created_at: String
    let updated_at: String
    let is_favorite: Bool?
    let version: Int?
    let head_revision_id: String?
    
    enum CodingKeys: String, CodingKey {
        case id, user_id, title, markdown, tags, created_at, updated_at, is_favorite, version, head_revision_id
    }
    
    var tagsList: [String] {
        return tags?.array ?? []
    }
    
    func toNoteItem() -> NoteItem {
        let note = NoteItem(
            title: title,
            content: markdown,
            tags: tagsList,
            userId: user_id
        )
        
        // Parse the ID from string to UUID
        if let uuid = UUID(uuidString: id) {
            note.id = uuid
        }
        
        // Parse timestamps
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        if let createdDate = formatter.date(from: created_at) {
            note.createdAt = createdDate
        }
        
        if let updatedDate = formatter.date(from: updated_at) {
            note.updatedAt = updatedDate
        }
        
        note.isFavorite = is_favorite ?? false
        note.version = version ?? 1
        note.headRevisionId = head_revision_id
        
        return note
    }
}

enum DocumentDevice {
    static var identifier: String {
        let key = "turbodoc.document.device-id"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let value = "ios-\(UUID().uuidString)"
        UserDefaults.standard.set(value, forKey: key)
        return value
    }
}

struct APIDocumentRevision: Codable, Identifiable {
    let id: String
    let document_id: String
    let revision_number: Int
    let title: String
    let markdown: String
    let name: String?
    let change_summary: String?
    let device_id: String?
    let created_at: String
}

struct APIDocumentRevisionListResponse: Codable { let data: [APIDocumentRevision] }

struct APINoteListResponse: Codable {
    let data: [APINoteResponse]
    let total: Int?
    let page: Int?
    let per_page: Int?
}

struct APINoteCreateResponse: Codable {
    let data: APINoteResponse
}

struct APINoteUpdateResponse: Codable {
    let data: APINoteResponse
}

// Helper struct to handle tags field that can be either a string or array
struct TagsContainer: Codable {
    let array: [String]
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let stringValue = try? container.decode(String.self) {
            // Handle string format like "marketing|seo"
            self.array = stringValue.split(separator: "|").map { String($0) }
        } else if let arrayValue = try? container.decode([String].self) {
            // Handle array format
            self.array = arrayValue
        } else {
            // Handle null or other cases
            self.array = []
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(array)
    }
}

// MARK: - User Stats Models

struct APIUserStatsResponse: Codable {
    let data: APIUserStats
}

struct APIUserStats: Codable {
    let bookmark_count: Int
    let note_count: Int
    let tag_count: Int
    let favorite_count: Int
    let member_since: String?
}
