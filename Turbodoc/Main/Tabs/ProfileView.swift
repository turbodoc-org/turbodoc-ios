import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authService: AuthenticationService
    @State private var showingSignOutAlert = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Profile Header
                VStack(spacing: 12) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                    
                    if let user = authService.currentUser {
                        Text(user.name ?? "User")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text(user.email)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 20)
                
                // Profile Info
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "bookmark.fill")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        Text("Bookmarks")
                        Spacer()
                        Text("0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Image(systemName: "tag.fill")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        Text("Tags")
                        Spacer()
                        Text("0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        Text("Member Since")
                        Spacer()
                        if let user = authService.currentUser {
                            Text(user.createdAt, style: .date)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
                
                Spacer()
                
                // Sign Out Button
                Button("Sign Out") {
                    showingSignOutAlert = true
                }
                .foregroundColor(.red)
                .padding(.bottom, 20)
            }
            .navigationTitle("Profile")
        }
        .alert("Sign Out", isPresented: $showingSignOutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                signOut()
            }
        } message: {
            Text("Are you sure you want to sign out?")
        }
    }
    
    private func signOut() {
        Task {
            do {
                try await authService.signOut()
            } catch {
                // Error is handled in AuthenticationService
            }
        }
    }
}