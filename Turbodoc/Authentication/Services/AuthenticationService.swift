import Foundation
import SwiftUI
import Supabase

enum AuthenticationStatus {
    case authenticated
    case notAuthenticated
    case loading
}

@MainActor
class AuthenticationService: ObservableObject {
    @Published var authenticationStatus: AuthenticationStatus = .loading
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let supabaseClient: SupabaseClient
    private var authToken: String? = nil
    private let appGroupIdentifier = "group.ai.turbodoc.ios.Turbodoc"
    
    init() {
        self.supabaseClient = SupabaseClient(
            supabaseURL: SupabaseConfig.supabaseURL,
            supabaseKey: SupabaseConfig.anonKey)
        
        Task {
            await checkAuthStatus()
        }
    }
    
    func signIn(email: String, password: String) async throws {
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await supabaseClient.auth.signIn(email: email, password: password)
            let user = User(id: response.user.id.uuidString, email: response.user.email ?? email)

            currentUser = user
            authenticationStatus = .authenticated
            
            authToken = response.accessToken
            saveAuthTokenToSharedStorage(response.accessToken)
            
        } catch {
            errorMessage = "Invalid email or password"
            throw AuthenticationError.invalidCredentials
        }
        
        isLoading = false
    }
    
    func signUp(email: String, password: String) async throws {
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await supabaseClient.auth.signUp(email: email, password: password)
            
            let user = User(id: response.user.id.uuidString, email: response.user.email ?? email)
            
            currentUser = user
            authenticationStatus = .authenticated
            
            authToken = response.session?.accessToken
            if let token = response.session?.accessToken {
                saveAuthTokenToSharedStorage(token)
            }
            
        } catch {
            errorMessage = "Failed to create account"
            throw AuthenticationError.networkError
        }
        
        isLoading = false
    }
    
    func signOut() async throws {
        isLoading = true
        errorMessage = nil
        
        do {
            try await supabaseClient.auth.signOut()
            
            currentUser = nil
            authenticationStatus = .notAuthenticated
            authToken = nil
            clearAuthTokenFromSharedStorage()
            
        } catch {
            errorMessage = "Failed to sign out"
            throw AuthenticationError.networkError
        }
        
        isLoading = false
    }
    
    func resetPassword(email: String) async throws {
        isLoading = true
        errorMessage = nil
        
        do {
            try await supabaseClient.auth.resetPasswordForEmail(email)
            
        } catch {
            errorMessage = "Failed to send reset email"
            throw AuthenticationError.networkError
        }
        
        isLoading = false
    }
    
    func getCurrentUser() async throws -> User? {
        do {
            let supabaseUser = try await supabaseClient.auth.user()
            return User(id: supabaseUser.id.uuidString, email: supabaseUser.email ?? "")
        } catch {
            return currentUser
        }
    }
    
    func checkAuthStatus() async {
        do {
            let session = try await supabaseClient.auth.session
            
            let user = User(id: session.user.id.uuidString, email: session.user.email ?? "")

            currentUser = user
            authenticationStatus = .authenticated
            authToken = session.accessToken
            saveAuthTokenToSharedStorage(session.accessToken)
        } catch {
            authenticationStatus = .notAuthenticated
            currentUser = nil
            authToken = nil
            clearAuthTokenFromSharedStorage()
        }
    }
    
    func getCurrentAuthToken() -> String? {
        return authToken
    }
    
    // MARK: - Shared Storage for Share Extension
    
    private func saveAuthTokenToSharedStorage(_ token: String) {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return
        }
        
        let authURL = containerURL.appendingPathComponent("auth.json")
        
        let authData = [
            "accessToken": token,
            "timestamp": Date().timeIntervalSince1970
        ] as [String: Any]
        
        do {
            let data = try JSONSerialization.data(withJSONObject: authData)
            try data.write(to: authURL)
        } catch {
            // Silent error handling
        }
    }
    
    private func clearAuthTokenFromSharedStorage() {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return
        }
        
        let authURL = containerURL.appendingPathComponent("auth.json")
        
        do {
            if FileManager.default.fileExists(atPath: authURL.path) {
                try FileManager.default.removeItem(at: authURL)
            }
        } catch {
            // Silent error handling
        }
    }
}

enum AuthenticationError: Error {
    case notImplemented
    case invalidCredentials
    case networkError
    
    var localizedDescription: String {
        switch self {
        case .notImplemented:
            return "Authentication not yet implemented"
        case .invalidCredentials:
            return "Invalid email or password"
        case .networkError:
            return "Network error occurred"
        }
    }
}
