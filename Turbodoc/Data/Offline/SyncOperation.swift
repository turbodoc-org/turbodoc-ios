import Foundation
import SwiftData

@Model
final class SyncOperation {
    var id: UUID
    var operationType: String // "create", "update", "delete"
    var entityType: String // "note", "bookmark"
    var entityId: UUID?
    var payload: Data? // JSON encoded operation data
    var createdAt: Date
    var retryCount: Int
    var lastError: String?
    var status: String // "pending", "syncing", "failed"
    
    init(
        id: UUID = UUID(),
        operationType: String,
        entityType: String,
        entityId: UUID? = nil,
        payload: Data? = nil,
        createdAt: Date = Date(),
        retryCount: Int = 0,
        lastError: String? = nil,
        status: String = "pending"
    ) {
        self.id = id
        self.operationType = operationType
        self.entityType = entityType
        self.entityId = entityId
        self.payload = payload
        self.createdAt = createdAt
        self.retryCount = retryCount
        self.lastError = lastError
        self.status = status
    }
}

// MARK: - Codable Payloads

struct NoteOperationPayload: Codable {
    let id: UUID?
    let title: String?
    let content: String?
    let tags: [String]?
    let isFavorite: Bool?
    let version: Int?
}

struct BookmarkOperationPayload: Codable {
    let id: UUID?
    let title: String?
    let url: String?
    let tags: [String]?
    let status: String?
    let isFavorite: Bool?
    let version: Int?
}
