import Foundation
import Supabase
import SwiftUI

enum AuthenticationStatus {
    case authenticated
    case notAuthenticated
    case loading
}

/// Outcome of a `signUp` call. With Supabase's default email-confirmation
/// enabled, sign-up returns no session until the user clicks the verification
/// link in the email — in that case we inform the UI that the user must
/// verify their email before signing in.
enum SignUpOutcome {
    case emailVerificationRequired
    case sessionConfirmed
}

@MainActor
class AuthenticationService: ObservableObject {
    @Published var authenticationStatus: AuthenticationStatus = .loading
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var errorMessage: String?

    /// When non-nil, the user has signed up successfully but Supabase is still
    /// waiting for email verification before allowing sign-in. The UI should
    /// show the ``EmailVerificationView`` while this is set.
    @Published var pendingVerificationEmail: String?

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
        pendingVerificationEmail = nil
        defer { isLoading = false }

        do {
            let response = try await supabaseClient.auth.signIn(email: email, password: password)
            let user = User(id: response.user.id.uuidString, email: response.user.email ?? email)
            user.createdAt = response.user.createdAt
            user.updatedAt = response.user.updatedAt

            currentUser = user
            authenticationStatus = .authenticated

            authToken = response.accessToken
            saveAuthTokenToSharedStorage(response.accessToken)

        } catch {
            AppLogger.authentication.error(
                "Sign in failed: \(error.localizedDescription, privacy: .public)"
            )
            // Email verification is handled by the verification sheet, so only
            // genuine credential failures should appear as inline errors.
            let message = error.localizedDescription
            if message.lowercased().contains("email not confirmed") {
                pendingVerificationEmail = email
            } else {
                errorMessage = "Invalid email or password"
            }
            throw AuthenticationError.invalidCredentials
        }
    }

    func signUp(email: String, password: String) async throws -> SignUpOutcome {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        var outcome: SignUpOutcome = .emailVerificationRequired

        do {
            let response = try await supabaseClient.auth.signUp(email: email, password: password)

            // If Supabase returned a session immediately, email verification is
            // not required for this project — authenticate right away.
            if let token = response.session?.accessToken {
                let user = User(
                    id: response.user.id.uuidString, email: response.user.email ?? email)
                user.createdAt = response.user.createdAt
                user.updatedAt = response.user.updatedAt
                currentUser = user
                authenticationStatus = .authenticated
                authToken = token
                saveAuthTokenToSharedStorage(token)
                pendingVerificationEmail = nil
                outcome = .sessionConfirmed
            } else {
                // Default Supabase config requires the user to confirm their
                // email by clicking the verification link before they can sign
                // in. Keep them unauthenticated and route to the verification
                // screen — do NOT silently flip to .authenticated, which
                // previously left users confused thinking sign-up "worked".
                pendingVerificationEmail = email
                authenticationStatus = .notAuthenticated
                outcome = .emailVerificationRequired
            }
        } catch {
            AppLogger.authentication.error(
                "Sign up failed: \(error.localizedDescription, privacy: .public)"
            )
            // Surface the real underlying message so the user (and debugging
            // via the Xcode console) can see what actually went wrong instead
            // of a generic "Failed to create account" string.
            let detail =
                error.localizedDescription.isEmpty ? "Unknown error" : error.localizedDescription
            errorMessage = "Failed to create account: \(detail)"
            throw AuthenticationError.networkError
        }

        return outcome
    }

    /// Resends the sign-up verification email for the given address.
    /// Used by the EmailVerificationView "Resend verification email" button.
    func resendVerificationEmail(to email: String) async throws {
        try await supabaseClient.auth.resend(email: email, type: .signup)
    }

    func signOut() async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await supabaseClient.auth.signOut()

            currentUser = nil
            authenticationStatus = .notAuthenticated
            authToken = nil
            clearAuthTokenFromSharedStorage()

        } catch {
            AppLogger.authentication.error(
                "Sign out failed: \(error.localizedDescription, privacy: .public)"
            )
            errorMessage = "Failed to sign out"
            throw AuthenticationError.networkError
        }
    }

    func resetPassword(email: String) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await supabaseClient.auth.resetPasswordForEmail(email)

        } catch {
            AppLogger.authentication.error(
                "Password reset failed: \(error.localizedDescription, privacy: .public)"
            )
            errorMessage = "Failed to send reset email"
            throw AuthenticationError.networkError
        }
    }

    func getCurrentUser() async throws -> User? {
        do {
            let supabaseUser = try await supabaseClient.auth.user()
            let user = User(id: supabaseUser.id.uuidString, email: supabaseUser.email ?? "")
            user.createdAt = supabaseUser.createdAt
            user.updatedAt = supabaseUser.updatedAt
            return user
        } catch {
            AppLogger.authentication.warning(
                "Could not refresh current user: \(error.localizedDescription, privacy: .public)"
            )
            return currentUser
        }
    }

    func checkAuthStatus() async {
        do {
            let session = try await supabaseClient.auth.session

            let user = User(id: session.user.id.uuidString, email: session.user.email ?? "")
            user.createdAt = session.user.createdAt
            user.updatedAt = session.user.updatedAt

            currentUser = user
            authenticationStatus = .authenticated
            authToken = session.accessToken
            saveAuthTokenToSharedStorage(session.accessToken)
        } catch {
            AppLogger.authentication.info("No authenticated session was restored")
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
        guard
            let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        else {
            return
        }

        let authURL = containerURL.appendingPathComponent("auth.json")

        let authData =
            [
                "accessToken": token,
                "timestamp": Date().timeIntervalSince1970,
            ] as [String: Any]

        do {
            let data = try JSONSerialization.data(withJSONObject: authData)
            try data.write(to: authURL)
        } catch {
            AppLogger.authentication.error(
                "Failed to save shared auth state: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func clearAuthTokenFromSharedStorage() {
        guard
            let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        else {
            return
        }

        let authURL = containerURL.appendingPathComponent("auth.json")

        do {
            if FileManager.default.fileExists(atPath: authURL.path) {
                try FileManager.default.removeItem(at: authURL)
            }
        } catch {
            AppLogger.authentication.error(
                "Failed to clear shared auth state: \(error.localizedDescription, privacy: .public)"
            )
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
