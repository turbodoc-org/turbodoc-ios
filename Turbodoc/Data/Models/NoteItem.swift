import Foundation
import SwiftData

@Model
class NoteItem {
    var id: UUID = UUID()
    var title: String?
    var content: String = ""
    var tags: [String] = []
    var userId: String = ""
    var isFavorite: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var syncedAt: Date?
    var version: Int = 1
    
    init(title: String? = nil, content: String = "", tags: [String] = [], userId: String = "", isFavorite: Bool = false, version: Int = 1) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.tags = tags
        self.userId = userId
        self.isFavorite = isFavorite
        self.version = version
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    // Helper computed properties
    var displayTitle: String {
        if let title = title, !title.isEmpty {
            return title
        }
        // Generate title from content first line or words
        let firstLine = content.components(separatedBy: .newlines).first ?? ""
        let words = firstLine.components(separatedBy: .whitespaces)
        let titleWords = Array(words.prefix(5)).joined(separator: " ")
        return titleWords.isEmpty ? "Untitled Note" : titleWords
    }
    
    var previewContent: String {
        // Return first 150 characters for preview
        let maxLength = 150
        if content.count <= maxLength {
            return content
        }
        return String(content.prefix(maxLength)) + "..."
    }
    
    var tagsString: String {
        return tags.joined(separator: ", ")
    }
    
    // Helper method to update the updatedAt timestamp
    func updateTimestamp() {
        self.updatedAt = Date()
    }
}

// MARK: - Identifiable conformance for SwiftUI
extension NoteItem: Identifiable {}
