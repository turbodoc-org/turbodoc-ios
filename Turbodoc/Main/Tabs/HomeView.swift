import SwiftUI

struct HomeView: View {
    @EnvironmentObject var authService: AuthenticationService
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Spacer()
                
                Image(systemName: "house.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                
                VStack(spacing: 16) {
                    Text("Welcome to Turbodoc")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Your saved content will appear here")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Text("Coming Soon")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                        .padding(.top, 20)
                }
                
                Spacer()
            }
            .navigationTitle("Home")
        }
    }
}