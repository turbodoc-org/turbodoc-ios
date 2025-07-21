import SwiftUI

struct SignInView: View {
    @StateObject private var authService = AuthenticationService()
    @State private var email = ""
    @State private var password = ""
    @State private var showingForgotPassword = false
    @State private var showingSignUp = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Constants.Spacing.xl) {
                    Spacer(minLength: Constants.Spacing.xxl)
                    
                    // Logo/Title
                    VStack(spacing: Constants.Spacing.md) {
                        Image("Logo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 120, height: 120)
                            .background(Color(.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color(.systemGray5), lineWidth: 1)
                            )
                        
                        Text(Constants.App.name)
                            .font(.system(size: Constants.Typography.FontSizes.xxl + 8, weight: .bold))
                            .foregroundColor(Constants.Colors.cardForeground)
                        
                        Text("Save and organize your content")
                            .font(.system(size: Constants.Typography.FontSizes.base))
                            .foregroundColor(Constants.Colors.mutedForeground)
                    }
                    .padding(.bottom, Constants.Spacing.lg)
                    
                    // Sign In Card
                    CardView {
                        CardHeader {
                            CardTitle(text: "Login")
                            CardDescription(text: "Enter your email below to login to your account")
                        }
                        
                        CardContent {
                            VStack(spacing: Constants.Spacing.lg) {
                                FormField(label: "Email") {
                                    TextField("mail@example.com", text: $email)
                                        .keyboardType(.emailAddress)
                                        .autocapitalization(.none)
                                        .primaryTextFieldStyle()
                                        .foregroundColor(Constants.Colors.cardForeground)
                                        .tint(Constants.Colors.primary)
                                }
                                
                                FormField(label: "Password") {
                                    SecureField("Password", text: $password)
                                        .primaryTextFieldStyle()
                                        .foregroundColor(Constants.Colors.cardForeground)
                                        .tint(Constants.Colors.primary)
                                }
                                
                                Button("Forgot your password?") {
                                    showingForgotPassword = true
                                }
                                .font(.system(size: Constants.Typography.FontSizes.sm))
                                .foregroundColor(Color(.systemBlue))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                
                                // Error Message
                                if let errorMessage = authService.errorMessage {
                                    Text(errorMessage)
                                        .font(.system(size: Constants.Typography.FontSizes.sm))
                                        .foregroundColor(Constants.Colors.destructive)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                
                                Button(action: signIn) {
                                    HStack(spacing: Constants.Spacing.sm) {
                                        if authService.isLoading {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: Constants.Colors.primaryForeground))
                                                .scaleEffect(0.8)
                                        }
                                        Text(authService.isLoading ? "Logging in..." : "Login")
                                    }
                                }
                                .primaryButtonStyle(isLoading: authService.isLoading)
                                .disabled(authService.isLoading || email.isEmpty || password.isEmpty)
                            }
                            
                            HStack {
                                Text("Don't have an account?")
                                    .font(.system(size: Constants.Typography.FontSizes.sm))
                                    .foregroundColor(Color(.systemGray2))
                                
                                Button("Sign up") {
                                    showingSignUp = true
                                }
                                .font(.system(size: Constants.Typography.FontSizes.sm))
                                .foregroundColor(Color(.systemBlue))
                            }
                            .padding(.top, Constants.Spacing.md)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, Constants.Spacing.md)
                    
                    Spacer(minLength: Constants.Spacing.xl)
                }
            }
            .background(Constants.Colors.background)
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showingForgotPassword) {
            ForgotPasswordView()
        }
        .sheet(isPresented: $showingSignUp) {
            SignUpView()
        }
    }
    
    private func signIn() {
        Task {
            do {
                try await authService.signIn(email: email, password: password)
            } catch {
                // Error is handled in AuthenticationService
            }
        }
    }
}
