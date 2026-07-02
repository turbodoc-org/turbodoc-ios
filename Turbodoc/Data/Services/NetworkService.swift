import Foundation

class NetworkService {
    static let shared = NetworkService()
    
    private let session = URLSession.shared
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    
    // Reference to auth service for token access
    private var authService: AuthenticationService?
    
    private init() {
        // Configure date formatting
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        decoder.dateDecodingStrategy = .formatted(formatter)
        encoder.dateEncodingStrategy = .formatted(formatter)
    }
    
    // MARK: - Configuration
    
    func setAuthService(_ authService: AuthenticationService) {
        self.authService = authService
    }
    
    // MARK: - Generic Request Methods
    
    func performRequest<T: Codable>(
        endpoint: String,
        method: HTTPMethod = .GET,
        body: Data? = nil,
        responseType: T.Type
    ) async throws -> T {
        let url = APIConfig.url(for: endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add authentication token if available
        if let authService = authService,
           let token = await authService.getCurrentAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        if let body = body {
            request.httpBody = body
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            let message = try? decoder.decode(APIErrorResponse.self, from: data).message
            throw NetworkError.serverError(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }
        
        do {
            return try decoder.decode(responseType, from: data)
        } catch {
            throw NetworkError.decodingError(error)
        }
    }
    
    func performRequest(
        endpoint: String,
        method: HTTPMethod = .GET,
        body: Data? = nil
    ) async throws {
        let url = APIConfig.url(for: endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add authentication token if available
        if let authService = authService,
           let token = await authService.getCurrentAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        if let body = body {
            request.httpBody = body
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            let message = try? decoder.decode(APIErrorResponse.self, from: data).message
            throw NetworkError.serverError(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }
    }
    
    // MARK: - Helper Methods
    
    func encodeBody<T: Codable>(_ object: T) throws -> Data {
        return try encoder.encode(object)
    }
    
    // MARK: - Multipart Upload
    
    /// Performs a multipart/form-data POST with a single binary file part
    /// and the given `Content-Type` filename, then decodes the JSON response.
    func performMultipartUpload<T: Codable>(
        endpoint: String,
        fieldName: String,
        filename: String,
        mimeType: String,
        fileURL: URL,
        responseType: T.Type
    ) async throws -> T {
        let url = APIConfig.url(for: endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // Authentication
        if let authService = authService,
           let token = await authService.getCurrentAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // Build multipart body
        let boundary = "----TurbodocBoundary\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        let multipartFileURL = try makeMultipartBodyFile(
            boundary: boundary,
            fieldName: fieldName,
            filename: filename,
            mimeType: mimeType,
            sourceFileURL: fileURL
        )
        defer { try? FileManager.default.removeItem(at: multipartFileURL) }
        
        let (data, response) = try await session.upload(for: request, fromFile: multipartFileURL)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            let message = try? decoder.decode(APIErrorResponse.self, from: data).message
            throw NetworkError.serverError(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }
        
        do {
            return try decoder.decode(responseType, from: data)
        } catch {
            throw NetworkError.decodingError(error)
        }
    }
    
    /// Builds the multipart envelope on disk so large recordings are never
    /// duplicated in memory before upload.
    private func makeMultipartBodyFile(
        boundary: String,
        fieldName: String,
        filename: String,
        mimeType: String,
        sourceFileURL: URL
    ) throws -> URL {
        let multipartFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("multipart_\(UUID().uuidString).body")
        
        guard FileManager.default.createFile(atPath: multipartFileURL.path, contents: nil) else {
            throw NetworkError.encodingError(
                CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: multipartFileURL.path])
            )
        }
        
        do {
            let output = try FileHandle(forWritingTo: multipartFileURL)
            defer { try? output.close() }
            
            let input = try FileHandle(forReadingFrom: sourceFileURL)
            defer { try? input.close() }
            
            // Keep CRLF explicit. A Swift multiline string suppresses its final
            // line feed, which previously left the header terminator as a lone
            // carriage return and made Hono reject the multipart body.
            let header =
            "--\(boundary)\r\n"
            + "Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\r\n"
            + "Content-Type: \(mimeType)\r\n"
            + "\r\n"
            try output.write(contentsOf: Data(header.utf8))
            
            while let chunk = try input.read(upToCount: 64 * 1024), !chunk.isEmpty {
                try output.write(contentsOf: chunk)
            }
            
            try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
            try output.synchronize()
            return multipartFileURL
        } catch {
            try? FileManager.default.removeItem(at: multipartFileURL)
            throw error
        }
    }
}

// MARK: - HTTP Method Enum

enum HTTPMethod: String {
    case GET = "GET"
    case POST = "POST"
    case PUT = "PUT"
    case DELETE = "DELETE"
}

// MARK: - Network Error Types

enum NetworkError: Error, LocalizedError {
    case invalidResponse
    case httpError(Int)
    case serverError(statusCode: Int, message: String?)
    case decodingError(Error)
    case encodingError(Error)
    case noData
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response received"
        case .httpError(let statusCode):
            return "HTTP error with status code: \(statusCode)"
        case .serverError(let statusCode, let message):
            return message ?? "The server returned HTTP \(statusCode)."
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .encodingError(let error):
            return "Failed to encode request: \(error.localizedDescription)"
        case .noData:
            return "No data received"
        }
    }
}

private struct APIErrorResponse: Decodable {
    let message: String
}
