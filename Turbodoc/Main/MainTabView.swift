import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var authService: AuthenticationService
    @EnvironmentObject var quickActionService: QuickActionService
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Image(systemName: "bookmark.fill")
                    Text("Bookmarks")
                }
                .tag(0)
            
            NotesView()
                .tabItem {
                    Image(systemName: "text.justify")
                    Text("Notes")
                }
                .tag(1)
            
            ProfileView()
                .tabItem {
                    Image(systemName: "person.fill")
                    Text("Profile")
                }
                .tag(2)
        }
        .onChange(of: quickActionService.currentAction) { _, action in
            switch action {
            case .newBookmark:
                selectedTab = 0
            case .newNote:
                selectedTab = 1
            case .search:
                // Stay on current tab
                break
            case .none:
                break
            }
        }
    }
}
