import Foundation
import SwiftUI

@MainActor
class AuthenticationService: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Mock implementation for Phase 1 - will be replaced with real Supabase in Phase 2
    private let isMockMode = true
    
    init() {
        // Check if Supabase is configured
        if !SupabaseConfig.isConfigured {
            print("⚠️ Supabase not configured. Using mock authentication.")
            print("📖 See SETUP.md for configuration instructions.")
        }
        
        Task {
            await checkAuthStatus()
        }
    }
    
    func signIn(email: String, password: String) async throws {
        isLoading = true
        errorMessage = nil
        
        // Mock authentication - simulate network delay
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        if isMockMode {
            // Mock successful login
            let user = User(id: UUID().uuidString, email: email)
            currentUser = user
            isAuthenticated = true
            
            // Save user to local storage
            // try DataManager.shared.saveUser(user)
        } else {
            // TODO: Implement real Supabase authentication
            errorMessage = "Real Supabase authentication not yet implemented"
            throw AuthenticationError.notImplemented
        }
        
        isLoading = false
    }
    
    func signUp(email: String, password: String) async throws {
        isLoading = true
        errorMessage = nil
        
        // Mock authentication - simulate network delay
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        if isMockMode {
            // Mock successful signup
            let user = User(id: UUID().uuidString, email: email)
            currentUser = user
            isAuthenticated = true
            
            // Save user to local storage
            // try DataManager.shared.saveUser(user)
        } else {
            // TODO: Implement real Supabase authentication
            errorMessage = "Real Supabase authentication not yet implemented"
            throw AuthenticationError.notImplemented
        }
        
        isLoading = false
    }
    
    func signOut() async throws {
        isLoading = true
        errorMessage = nil
        
        // Mock signout - simulate network delay
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        if isMockMode {
            // Clear local data
            if let user = currentUser {
                // try DataManager.shared.deleteUser(user)
            }
            
            currentUser = nil
            isAuthenticated = false
        } else {
            // TODO: Implement real Supabase signout
            errorMessage = "Real Supabase authentication not yet implemented"
            throw AuthenticationError.notImplemented
        }
        
        isLoading = false
    }
    
    func resetPassword(email: String) async throws {
        isLoading = true
        errorMessage = nil
        
        // Mock password reset - simulate network delay
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        if isMockMode {
            // Mock successful password reset
            // In real implementation, this would send an email
        } else {
            // TODO: Implement real Supabase password reset
            errorMessage = "Real Supabase authentication not yet implemented"
            throw AuthenticationError.notImplemented
        }
        
        isLoading = false
    }
    
    func getCurrentUser() async throws -> User? {
        if isMockMode {
            return currentUser
        } else {
            // TODO: Implement real Supabase user fetching
            return nil
        }
    }
    
    func checkAuthStatus() async {
        if isMockMode {
            // Check if we have a saved user in local storage
            // For now, just start with logged out state
            isAuthenticated = false
            currentUser = nil
        } else {
            // TODO: Implement real Supabase auth status check
            isAuthenticated = false
            currentUser = nil
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