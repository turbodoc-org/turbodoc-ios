import Foundation

struct APIConfig {
    static let baseURL = "https://api.turbodoc.ai"
    
    static var baseURLComponents: URLComponents {
        guard let components = URLComponents(string: baseURL) else {
            fatalError("Invalid base URL: \(baseURL)")
        }
        return components
    }
    
    static func url(for endpoint: String) -> URL {
        guard let url = URL(string: baseURL + endpoint) else {
            fatalError("Invalid endpoint: \(endpoint)")
        }
        return url
    }
    
    // API Endpoints
    struct Endpoints {
        static let bookmarks = "/v1/bookmarks"
        static let bookmarkById = "/v1/bookmarks/" // append bookmark ID
        static let searchBookmarks = "/v1/bookmarks/search"
        static let notes = "/v2/documents"
        static let noteById = "/v2/documents/" // append document ID
        static let notesTranscribe = "/v1/notes/transcribe" // voice -> text (Workers AI Whisper)
        static let users = "/v1/users"
        static let userById = "/v1/users/" // append user ID
        static let userStats = "/v1/users/stats" // current-user stats summary
        static let ogImage = "/v1/bookmarks/og-image" // OG image endpoint
        static let tags = "/v1/tags" // Get user's top tags
    }
}
