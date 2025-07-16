import Foundation
import SwiftData

class DataManager {
    static let shared = DataManager()
    
    private var modelContainer: ModelContainer?
    
    private init() {
        setupModelContainer()
    }
    
    private func setupModelContainer() {
        let schema = Schema([
            User.self,
            BookmarkItem.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            print("Failed to create ModelContainer: \(error)")
        }
    }
    
    @MainActor
    private var context: ModelContext? {
        modelContainer?.mainContext
    }
    
    // MARK: - User Operations
    
    @MainActor
    func saveUser(_ user: User) throws {
        guard let context = context else {
            throw DataManagerError.contextNotAvailable
        }
        
        // Check if user already exists
        if let existingUser = try fetchUser(by: user.id) {
            existingUser.email = user.email
            existingUser.name = user.name
            existingUser.updatedAt = Date()
        } else {
            context.insert(user)
        }
        
        try context.save()
    }
    
    @MainActor
    func fetchUser(by id: String) throws -> User? {
        guard let context = context else {
            throw DataManagerError.contextNotAvailable
        }
        
        let descriptor = FetchDescriptor<User>()
        let users = try context.fetch(descriptor)
        
        return users.first { $0.id == id }
    }
    
    @MainActor
    func deleteUser(_ user: User) throws {
        guard let context = context else {
            throw DataManagerError.contextNotAvailable
        }
        
        context.delete(user)
        try context.save()
    }
    
    // MARK: - Bookmark Operations
    
    @MainActor
    func saveBookmark(_ bookmark: BookmarkItem) throws {
        guard let context = context else {
            throw DataManagerError.contextNotAvailable
        }
        
        context.insert(bookmark)
        try context.save()
    }
    
    @MainActor
    func fetchBookmarks(for userId: String) throws -> [BookmarkItem] {
        guard let context = context else {
            throw DataManagerError.contextNotAvailable
        }
        
        let descriptor = FetchDescriptor<BookmarkItem>(
            sortBy: [SortDescriptor(\.timeAdded, order: .reverse)]
        )
        
        let bookmarks = try context.fetch(descriptor)
        return bookmarks.filter { $0.userId == userId }
    }
    
    @MainActor
    func deleteBookmark(_ bookmark: BookmarkItem) throws {
        guard let context = context else {
            throw DataManagerError.contextNotAvailable
        }
        
        context.delete(bookmark)
        try context.save()
    }
}

enum DataManagerError: Error {
    case contextNotAvailable
    
    var localizedDescription: String {
        switch self {
        case .contextNotAvailable:
            return "Database context is not available"
        }
    }
}