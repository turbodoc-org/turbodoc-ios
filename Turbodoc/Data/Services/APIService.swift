import Foundation

class APIService {
    static let shared = APIService()
    
    private let networkService = NetworkService.shared
    private let cacheManager = CacheManager.shared
    private let networkMonitor = NetworkMonitor.shared
    
    private init() {}
    
    // Configure with auth service reference
    func configure(authService: AuthenticationService) {
        networkService.setAuthService(authService)
    }
    
    // MARK: - Cache Invalidation
    
    /// Invalidates the cached bookmarks, forcing a fresh fetch from the API on next request.
    /// Call this when bookmarks may have been added externally (e.g., via share extension).
    func invalidateBookmarksCache() {
        cacheManager.removeAll(withPrefix: "bookmarks_")
    }
    
    // MARK: - Bookmark Operations
    
    func fetchBookmarks(userId: String) async throws -> [BookmarkItem] {
        let endpoint = APIConfig.Endpoints.bookmarks
        let cacheKey = "bookmarks_\(userId)"
        
        // Try network first if connected
        if networkMonitor.isConnected {
            do {
                let response = try await networkService.performRequest(
                    endpoint: endpoint,
                    method: .GET,
                    responseType: APIBookmarkListResponse.self
                )
                
                let bookmarks = response.data.map { $0.toBookmarkItem() }
                
                // Cache the successful response
                cacheManager.cache(item: response, forKey: cacheKey)
                
                return bookmarks
            } catch {
                // Network failed, try cache
                if let cachedResponse: APIBookmarkListResponse = cacheManager.retrieve(forKey: cacheKey, as: APIBookmarkListResponse.self) {
                    return cachedResponse.data.map { $0.toBookmarkItem() }
                }
                AppLogger.network.error(
                    "Bookmark fetch failed with no cache: \(error.localizedDescription, privacy: .public)"
                )
                throw error
            }
        } else {
            // Offline - use cache
            if let cachedResponse: APIBookmarkListResponse = cacheManager.retrieve(forKey: cacheKey, as: APIBookmarkListResponse.self) {
                return cachedResponse.data.map { $0.toBookmarkItem() }
            }
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
    
    func updateBookmark(id: UUID, changes: BookmarkChanges) async throws -> BookmarkItem {
        let endpoint = APIConfig.Endpoints.bookmarkById + id.uuidString.lowercased()
        let bodyData = try networkService.encodeBody(APIBookmarkUpdateRequest(from: changes))
        
        do {
            let response = try await networkService.performRequest(
                endpoint: endpoint,
                method: .PUT,
                body: bodyData,
                responseType: APIBookmarkUpdateResponse.self
            )
            return response.data.toBookmarkItem()
        } catch {
            AppLogger.network.error(
                "Bookmark update failed: \(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }
    
    func deleteBookmark(id: UUID) async throws {
        let endpoint = APIConfig.Endpoints.bookmarkById + id.uuidString.lowercased()
        
        do {
            try await networkService.performRequest(
                endpoint: endpoint,
                method: .DELETE
            )
        } catch {
            AppLogger.network.error(
                "Bookmark delete failed: \(error.localizedDescription, privacy: .public)"
            )
            throw error
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
    
    // MARK: - Tags Operations
    
    func fetchTags() async throws -> [APITagItem] {
        let endpoint = APIConfig.Endpoints.tags
        
        do {
            let response = try await networkService.performRequest(
                endpoint: endpoint,
                method: .GET,
                responseType: APITagsResponse.self
            )
            
            return response.data
        } catch {
            throw APIError.networkError
        }
    }
    
    // MARK: - Note Operations
    
    func fetchNotes(userId: String) async throws -> [NoteItem] {
        let endpoint = APIConfig.Endpoints.notes
        let cacheKey = "notes_\(userId)"
        
        // Try network first if connected
        if networkMonitor.isConnected {
            do {
                let response = try await networkService.performRequest(
                    endpoint: endpoint,
                    method: .GET,
                    responseType: APINoteListResponse.self
                )
                
                let notes = response.data.map { $0.toNoteItem() }
                
                // Cache the successful response
                cacheManager.cache(item: response, forKey: cacheKey)
                
                return notes
            } catch {
                // Network failed, try cache
                if let cachedResponse: APINoteListResponse = cacheManager.retrieve(forKey: cacheKey, as: APINoteListResponse.self) {
                    return cachedResponse.data.map { $0.toNoteItem() }
                }
                AppLogger.network.error(
                    "Note fetch failed with no cache: \(error.localizedDescription, privacy: .public)"
                )
                throw error
            }
        } else {
            // Offline - use cache
            if let cachedResponse: APINoteListResponse = cacheManager.retrieve(forKey: cacheKey, as: APINoteListResponse.self) {
                return cachedResponse.data.map { $0.toNoteItem() }
            }
            throw APIError.networkError
        }
    }
    
    /// Creates a note under its local ID, so an offline create can be
    /// replayed safely: the server answers 201 when it creates the document
    /// and 200 with the existing document for a replay.
    func createDocument(_ note: NoteItem) async throws -> NoteItem {
        do {
            let bodyData = try networkService.encodeBody(APIDocumentCreateRequest(from: note))
            let response = try await networkService.performRequest(
                endpoint: APIConfig.Endpoints.notes,
                method: .POST,
                body: bodyData,
                responseType: APINoteCreateResponse.self
            )
            return response.data.toNoteItem()
        } catch {
            throw Self.noteError(error)
        }
    }

    /// Creates the note under its local ID. If it already exists (a replay
    /// of a create that reached the server), the note's text is saved on top
    /// of the stored version.
    func createOrReplayDocument(_ note: NoteItem) async throws -> DocumentSaveResult {
        let created = try await createDocument(note)
        guard NoteDraft(created) != NoteDraft(note) else {
            return DocumentSaveResult(
                note: created,
                merged: false,
                conflicts: 0,
                submittedRevisionId: created.headRevisionId
            )
        }
        return try await saveDocument(
            id: note.id,
            title: note.title ?? "",
            content: note.content,
            isFavorite: nil,
            baseRevisionId: created.headRevisionId
        )
    }

    /// Saves edits made on top of `baseRevisionId`. The server merges them
    /// with anything saved since that revision. Pass nil for a field that
    /// did not change: omitted fields are left as they are on the server.
    func saveDocument(
        id: UUID,
        title: String?,
        content: String?,
        isFavorite: Bool?,
        baseRevisionId: String?
    ) async throws -> DocumentSaveResult {
        let requestBody = APIDocumentSaveRequest(
            title: title,
            markdown: content,
            is_favorite: isFavorite,
            base_revision_id: baseRevisionId,
            device_id: DocumentDevice.identifier
        )

        do {
            let bodyData = try networkService.encodeBody(requestBody)
            let response = try await networkService.performRequest(
                endpoint: APIConfig.Endpoints.noteById + id.uuidString,
                method: .PUT,
                body: bodyData,
                responseType: APIDocumentSaveResponse.self
            )
            return DocumentSaveResult(
                note: response.data.toNoteItem(),
                merged: response.merged ?? false,
                conflicts: response.conflicts ?? 0,
                submittedRevisionId: response.submitted_revision_id
            )
        } catch {
            throw Self.noteError(error)
        }
    }

    func fetchDocument(id: UUID) async throws -> NoteItem {
        do {
            let response = try await networkService.performRequest(
                endpoint: APIConfig.Endpoints.noteById + id.uuidString,
                method: .GET,
                responseType: APINoteCreateResponse.self
            )
            return response.data.toNoteItem()
        } catch {
            throw Self.noteError(error)
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
            throw Self.noteError(error)
        }
    }

    /// Note calls tell "offline" apart from "the server said no": only a
    /// transport failure is a `networkError` (and may be queued for later).
    private static func noteError(_ error: Error) -> Error {
        if let apiError = error as? APIError { return apiError }
        if error is URLError { return APIError.networkError }
        if let networkError = error as? NetworkError {
            switch networkError {
            case .serverError(let status, let message):
                return APIError.http(status: status, message: message)
            case .httpError(let status):
                return APIError.http(status: status, message: nil)
            default:
                return APIError.invalidResponse
            }
        }
        return APIError.invalidResponse
    }

    func fetchDocumentRevisions(id: UUID) async throws -> [APIDocumentRevision] {
        let response = try await networkService.performRequest(
            endpoint: APIConfig.Endpoints.noteById + id.uuidString + "/revisions",
            method: .GET,
            responseType: APIDocumentRevisionListResponse.self
        )
        return response.data
    }

    func restoreDocumentRevision(documentId: UUID, revisionId: String) async throws -> NoteItem {
        let response = try await networkService.performRequest(
            endpoint: APIConfig.Endpoints.noteById + documentId.uuidString + "/revisions/\(revisionId)/restore",
            method: .POST,
            responseType: APINoteUpdateResponse.self
        )
        return response.data.toNoteItem()
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
    
    func getUserStats(userId: String) async throws -> APIUserStats {
        let endpoint = APIConfig.Endpoints.userStats
        
        do {
            let response = try await networkService.performRequest(
                endpoint: endpoint,
                method: .GET,
                responseType: APIUserStatsResponse.self
            )
            return response.data
        } catch {
            throw APIError.networkError
        }
    }
    
    // MARK: - Voice Transcription
    
    /// Uploads an audio recording to the backend for multilingual transcription
    /// via Cloudflare Workers AI Whisper. Returns the transcribed text in the
    /// spoken language (no translation).
    func transcribeAudio(
        at fileURL: URL,
        filename: String = "recording.wav",
        mimeType: String = "audio/wav"
    ) async throws -> String {
        let response = try await networkService.performMultipartUpload(
            endpoint: APIConfig.Endpoints.notesTranscribe,
            fieldName: "audio",
            filename: filename,
            mimeType: mimeType,
            fileURL: fileURL,
            responseType: APITranscriptionResponse.self
        )
        return response.text
    }
}

// MARK: - Supporting Models

struct DocumentSaveResult {
    let note: NoteItem
    /// The server combined this save with newer edits.
    let merged: Bool
    /// Passages both sides rewrote. Both versions were kept.
    let conflicts: Int
    /// A revision holding exactly what this save sent.
    let submittedRevisionId: String?

    var syncResponse: NoteSaveResponse {
        NoteSaveResponse(
            document: ServerDocument(note),
            submittedRevisionId: submittedRevisionId
        )
    }
}

enum APIError: LocalizedError {
    case networkError
    case invalidResponse
    case authenticationRequired
    case serverError(String)
    /// The server answered with a non-2xx status.
    case http(status: Int, message: String?)
    
    var statusCode: Int? {
        if case .http(let status, _) = self { return status }
        return nil
    }
    
    var errorDescription: String? {
        switch self {
        case .networkError:
            return "Network connection error"
        case .invalidResponse:
            return "Invalid response from server"
        case .authenticationRequired:
            return "Authentication required"
        case .serverError(let message):
            return "Server error: \(message)"
        case .http(let status, let message):
            return message ?? "The server returned HTTP \(status)."
        }
    }
}
