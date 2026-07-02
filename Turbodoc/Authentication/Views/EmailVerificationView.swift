import SwiftUI

/// Shown after sign-up when Supabase is waiting on email verification.
/// Makes it explicit the user MUST verify their email before signing in,
/// and offers a "Resend verification email" affordance with a 60-second
/// countdown so Supabase's email-send rate limit (60s) is respected.
struct EmailVerificationView: View {
    static let resendCooldownSeconds: Int = 60
    
    let email: String
    
    @EnvironmentObject var authService: AuthenticationService
    @Environment(\.dismiss) private var dismiss
    
    @State private var isResending = false
    @State private var resendResult: String?
    
    /// Seconds remaining on the cooldown timer. Starts at 60 because Supabase
    /// already sent the verification email during the preceding sign-up, so
    /// its email-send rate limit is already ticking from that moment.
    @State private var secondsUntilCanResend: Int = Self.resendCooldownSeconds
    @State private var cooldownTimer: Timer?
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.1))
                                .frame(width: 100, height: 100)
                            
                            Image(systemName: "envelope.badge.fill")
                                .font(.system(size: 44))
                                .foregroundColor(.blue)
                        }
                        
                        Text("Verify your email")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("We sent a verification link to")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Text(email)
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        Text("Before you can sign in, tap the verification link to confirm your email address. Don't forget to check your spam or junk folder.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                    .padding(.top, 24)
                    
                    VStack(spacing: 12) {
                        Button(action: resendEmail) {
                            HStack {
                                if isResending {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: Constants.Colors.primaryForeground))
                                        .scaleEffect(0.8)
                                }
                                Text(resendButtonTitle)
                            }
                        }
                        .primaryButtonStyle(isLoading: isResending)
                        .disabled(isResending || isOnCooldown)
                        .padding(.horizontal)
                        
                        if isOnCooldown {
                            Text("You can resend in \(secondsUntilCanResend)s")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        
                        if let result = resendResult {
                            Text(result)
                                .font(.callout)
                                .foregroundColor(
                                    result.lowercased().hasPrefix("failed")
                                        ? Constants.Colors.destructive
                                        : Constants.Colors.secondaryForeground
                                )
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }
                    
                    VStack(spacing: 8) {
                        Button("I've verified — back to sign in") {
                            // Reset pending state so the sign-in screen shows again
                            // without the verification sheet.
                            authService.pendingVerificationEmail = nil
                            dismiss()
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(Color(.systemBlue))
                        .padding(.top, 8)
                    }
                    .padding(.top, 16)
                    
                    Spacer(minLength: 40)
                }
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Verify Email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        cancelCooldown()
                        authService.pendingVerificationEmail = nil
                        dismiss()
                    }
                }
            }
            .onAppear { startCooldownIfNeeded() }
            .onDisappear { cancelCooldown() }
        }
    }
    
    private func startCooldownIfNeeded(fromSeconds duration: Int? = nil) {
        if let duration {
            cancelCooldown()
            secondsUntilCanResend = duration
        }
        guard cooldownTimer == nil, secondsUntilCanResend > 0 else { return }
        cooldownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            secondsUntilCanResend -= 1
            if secondsUntilCanResend <= 0 {
                timer.invalidate()
                cooldownTimer = nil
                secondsUntilCanResend = 0
            }
        }
    }
    
    // MARK: - Cooldown
    
    private var isOnCooldown: Bool {
        secondsUntilCanResend > 0
    }
    
    private var resendButtonTitle: String {
        if isResending { return "Sending…" }
        return "Resend verification email"
    }
    
    private func cancelCooldown() {
        cooldownTimer?.invalidate()
        cooldownTimer = nil
        secondsUntilCanResend = 0
    }
    
    // MARK: - Resend
    
    private func resendEmail() {
        guard !isResending, !isOnCooldown else { return }
        isResending = true
        resendResult = nil
        Task {
            do {
                try await authService.resendVerificationEmail(to: email)
                await MainActor.run {
                    isResending = false
                    resendResult = "Verification email resent to \(email)."
                    startCooldownIfNeeded(fromSeconds: Self.resendCooldownSeconds)
                }
            } catch {
                let message = error.localizedDescription
                AppLogger.authentication.error(
                    "Resend verification email failed: \(error.localizedDescription, privacy: .public)"
                )
                await MainActor.run {
                    isResending = false
                    resendResult = "Failed: \(message)"
                }
            }
        }
    }
}
