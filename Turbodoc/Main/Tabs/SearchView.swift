import SwiftUI

struct SearchView: View {
    @EnvironmentObject var authService: AuthenticationService
    @State private var searchText = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Spacer()
                
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                
                VStack(spacing: 16) {
                    Text("Search Your Content")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Find your saved bookmarks, images, and files")
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
            .navigationTitle("Search")
            .searchable(text: $searchText, prompt: "Search bookmarks...")
        }
    }
}