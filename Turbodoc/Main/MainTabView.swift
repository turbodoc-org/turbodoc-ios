import SwiftUI

struct MainTabView: View {
    @StateObject private var authService = AuthenticationService()
    
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Image(systemName: "bookmark.fill")
                    Text("Bookmarks")
                }
            
            NotesView()
                .tabItem {
                    Image(systemName: "text.justify")
                    Text("Notes")
                }
            
            ProfileView()
                .tabItem {
                    Image(systemName: "person.fill")
                    Text("Profile")
                }
        }
        .environmentObject(authService)
    }
}
