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

/// Queued note change. Operations queued by older builds may still be stored,
/// so every field is optional and new fields must stay optional.
struct NoteOperationPayload: Codable {
    var id: UUID?
    var title: String?
    var content: String?
    var tags: [String]?
    var isFavorite: Bool?
    var version: Int?
    /// The revision these edits started from (`base_revision_id`). Stored
    /// under its original key so payloads from older builds still decode.
    /// With a nil base the server overwrites instead of merging; history
    /// keeps the previous version.
    var headRevisionId: String?
    /// ID of the "(recovered)" copy, fixed once chosen so recreating a note
    /// that was deleted on the server is safe to retry.
    var recoveryId: UUID?

    var baseRevisionId: String? {
        get { headRevisionId }
        set { headRevisionId = newValue }
    }
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
