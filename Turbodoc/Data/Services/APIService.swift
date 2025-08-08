import Foundation

class APIService {
    static let shared = APIService()
    
    private let networkService = NetworkService.shared
    
    private init() {}
    
    // Configure with auth service reference
    func configure(authService: AuthenticationService) {
        networkService.setAuthService(authService)
    }
    
    // MARK: - Bookmark Operations
    
    func fetchBookmarks(userId: String) async throws -> [BookmarkItem] {
        let endpoint = APIConfig.Endpoints.bookmarks
        
        do {
            let response = try await networkService.performRequest(
                endpoint: endpoint,
                method: .GET,
                responseType: APIBookmarkListResponse.self
            )
            
            return response.data.map { $0.toBookmarkItem() }
        } catch {
            throw APIError.networkError
        }
    }
    
    func saveBookmark(_ bookmark: BookmarkItem) async throws -> BookmarkItem {
        let endpoint = APIConfig.Endpoints.bookmarks
        let requestBody = APIBookmarkRequest(from: bookmark)
        
        do {
            let bodyData = try networkService.encodeBody(requestBody)
            let response = try await networkService.performRequest(
                endpoint: endpoint,
                method: .POST,
                body: bodyData,
                responseType: APIBookmarkCreateResponse.self
            )
            
            let bookmarkItem = response.data.toBookmarkItem()
            return bookmarkItem
        } catch {
            throw APIError.networkError
        }
    }
    
    func updateBookmark(_ bookmark: BookmarkItem) async throws -> BookmarkItem {
        let endpoint = APIConfig.Endpoints.bookmarkById + bookmark.id.uuidString
        let requestBody = APIBookmarkRequest(from: bookmark)
        
        do {
            let bodyData = try networkService.encodeBody(requestBody)
            let response = try await networkService.performRequest(
                endpoint: endpoint,
                method: .PUT,
                body: bodyData,
                responseType: APIBookmarkUpdateResponse.self
            )
            
            return response.data.toBookmarkItem()
        } catch {
            throw APIError.networkError
        }
    }
    
    func deleteBookmark(id: UUID) async throws {
        let endpoint = APIConfig.Endpoints.bookmarkById + id.uuidString
        
        do {
            try await networkService.performRequest(
                endpoint: endpoint,
                method: .DELETE
            )
        } catch {
            throw APIError.networkError
        }
    }
    
    // MARK: - Search Operations
    
    func searchBookmarks(query: String, userId: String) async throws -> [BookmarkItem] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let endpoint = APIConfig.Endpoints.searchBookmarks + "?q=\(encodedQuery)"
        
        do {
            let response = try await networkService.performRequest(
                endpoint: endpoint,
                method: .GET,
                responseType: APIBookmarkSearchResponse.self
            )
            
            return response.data.map { $0.toBookmarkItem() }
        } catch {
            throw APIError.networkError
        }
    }
    
    // MARK: - User Operations
    
    func updateUserProfile(userId: String, name: String?) async throws -> User {
        let endpoint = APIConfig.Endpoints.userById + userId
        let requestBody = APIUserUpdateRequest(name: name, email: nil)
        
        do {
            let bodyData = try networkService.encodeBody(requestBody)
            let response = try await networkService.performRequest(
                endpoint: endpoint,
                method: .PUT,
                body: bodyData,
                responseType: APIUserResponse.self
            )
            
            return response.toUser()
        } catch {
            throw APIError.networkError
        }
    }
    
    // MARK: - OG Image Operations
    
    func fetchOgImage(for url: String) async throws -> APIOgImageResponse {
        var urlComponents = APIConfig.baseURLComponents
        urlComponents.path = APIConfig.Endpoints.ogImage
        urlComponents.queryItems = [URLQueryItem(name: "url", value: url)]
        
        guard let requestURL = urlComponents.url else {
            throw APIError.invalidResponse
        }
        
        do {
            let response = try await networkService.performRequest(
                endpoint: urlComponents.path + "?" + (urlComponents.query ?? ""),
                method: .GET,
                responseType: APIOgImageResponse.self
            )
            
            return response
        } catch {
            throw APIError.networkError
        }
    }
    
    // MARK: - Note Operations
    
    func fetchNotes(userId: String) async throws -> [NoteItem] {
        let endpoint = APIConfig.Endpoints.notes
        
        do {
            let response = try await networkService.performRequest(
                endpoint: endpoint,
                method: .GET,
                responseType: APINoteListResponse.self
            )
            
            return response.data.map { $0.toNoteItem() }
        } catch {
            throw APIError.networkError
        }
    }
    
    func saveNote(_ note: NoteItem) async throws -> NoteItem {
        let endpoint = APIConfig.Endpoints.notes
        let requestBody = APINoteRequest(from: note)
        
        do {
            let bodyData = try networkService.encodeBody(requestBody)
            let response = try await networkService.performRequest(
                endpoint: endpoint,
                method: .POST,
                body: bodyData,
                responseType: APINoteCreateResponse.self
            )
            
            return response.data.toNoteItem()
        } catch {
            throw APIError.networkError
        }
    }
    
    func updateNote(_ note: NoteItem) async throws -> NoteItem {
        let endpoint = APIConfig.Endpoints.noteById + note.id.uuidString
        let requestBody = APINoteRequest(from: note)
        
        do {
            let bodyData = try networkService.encodeBody(requestBody)
            let response = try await networkService.performRequest(
                endpoint: endpoint,
                method: .PUT,
                body: bodyData,
                responseType: APINoteUpdateResponse.self
            )
            
            return response.data.toNoteItem()
        } catch {
            throw APIError.networkError
        }
    }
    
    func deleteNote(id: UUID) async throws {
        let endpoint = APIConfig.Endpoints.noteById + id.uuidString
        
        do {
            try await networkService.performRequest(
                endpoint: endpoint,
                method: .DELETE
            )
        } catch {
            throw APIError.networkError
        }
    }
    
    func searchNotes(query: String, userId: String) async throws -> [NoteItem] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let endpoint = APIConfig.Endpoints.notes + "?search=\(encodedQuery)"
        
        do {
            let response = try await networkService.performRequest(
                endpoint: endpoint,
                method: .GET,
                responseType: APINoteListResponse.self
            )
            
            return response.data.map { $0.toNoteItem() }
        } catch {
            throw APIError.networkError
        }
    }
    
    // MARK: - Statistics Operations
    
    func getUserStats(userId: String) async throws -> UserStats {
        let endpoint = APIConfig.Endpoints.userById + userId
        
        do {
            let _ = try await networkService.performRequest(
                endpoint: endpoint,
                method: .GET,
                responseType: APIUserResponse.self
            )
            
            // For now, return mock stats since the API doesn't have a stats endpoint
            // This can be enhanced when a dedicated stats endpoint is added
            return UserStats(
                bookmarkCount: 0,
                tagCount: 0,
                totalSize: 0
            )
        } catch {
            throw APIError.networkError
        }
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
