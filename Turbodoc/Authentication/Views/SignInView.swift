import SwiftUI

struct SignInView: View {
    @StateObject private var authService = AuthenticationService()
    @State private var email = ""
    @State private var password = ""
    @State private var showingForgotPassword = false
    @State private var showingSignUp = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Spacer()
                
                // Logo/Title
                VStack(spacing: 10) {
                    Image("Logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 120)
                    
                    Text("Turbodoc")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Save and organize your content")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 40)
                
                // Sign In Form
                VStack(spacing: 16) {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    SecureField("Password", text: $password)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Button(action: signIn) {
                        HStack {
                            if authService.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            Text("Sign In")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(authService.isLoading || email.isEmpty || password.isEmpty)
                }
                .padding(.horizontal)
                
                // Error Message
                if let errorMessage = authService.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Action Buttons
                HStack {
                    Button("Forgot Password?") {
                        showingForgotPassword = true
                    }
                    .foregroundColor(.blue)
                    .font(.footnote)
                    
                    Spacer()
                    
                    Button("Sign Up") {
                        showingSignUp = true
                    }
                    .foregroundColor(.blue)
                    .font(.footnote)
                }
                .padding(.horizontal)
                .padding(.top, 10)
                
                Spacer()
            }
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