import Foundation

class APIService {
    static let shared = APIService()
    
    private init() {}
    
    // MARK: - Bookmark Operations (Mock Implementation)
    
    func fetchBookmarks(userId: String) async throws -> [BookmarkItem] {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Return empty array for Phase 1
        return []
    }
    
    func saveBookmark(_ bookmark: BookmarkItem) async throws -> BookmarkItem {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        
        // Mock save - just return the item
        return bookmark
    }
    
    func updateBookmark(_ bookmark: BookmarkItem) async throws -> BookmarkItem {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        
        // Mock update - just return the item
        return bookmark
    }
    
    func deleteBookmark(id: UUID) async throws {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        
        // Mock delete - no-op for now
    }
    
    // MARK: - Search Operations (Mock Implementation)
    
    func searchBookmarks(query: String, userId: String) async throws -> [BookmarkItem] {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 400_000_000) // 0.4 seconds
        
        // Return empty array for Phase 1
        return []
    }
    
    // MARK: - User Operations (Mock Implementation)
    
    func updateUserProfile(userId: String, name: String?) async throws -> User {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        
        // Mock update - create a mock user
        let user = User(id: userId, email: "mock@example.com", name: name)
        return user
    }
    
    // MARK: - Statistics Operations (Mock Implementation)
    
    func getUserStats(userId: String) async throws -> UserStats {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        
        // Return mock stats
        return UserStats(
            bookmarkCount: 0,
            tagCount: 0,
            totalSize: 0
        )
    }
}

// MARK: - Supporting Models

struct UserStats {
    let bookmarkCount: Int
    let tagCount: Int
    let totalSize: Int64 // in bytes
}

enum APIError: Error {
    case networkError
    case invalidResponse
    case authenticationRequired
    case serverError(String)
    
    var localizedDescription: String {
        switch self {
        case .networkError:
            return "Network connection error"
        case .invalidResponse:
            return "Invalid response from server"
        case .authenticationRequired:
            return "Authentication required"
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}