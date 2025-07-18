import Foundation
import SwiftUI
import Supabase

@MainActor
class AuthenticationService: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let supabaseClient: SupabaseClient
    private var authToken: String? = nil
    
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
            isAuthenticated = true
            
            authToken = response.accessToken
            
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
            isAuthenticated = true
            
            authToken = response.session?.accessToken
            
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
            isAuthenticated = false
            authToken = nil
            
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
            isAuthenticated = true
            authToken = session.accessToken
        } catch {
            isAuthenticated = false
            currentUser = nil
            authToken = nil
        }
    }
    
    func getCurrentAuthToken() -> String? {
        return authToken
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
