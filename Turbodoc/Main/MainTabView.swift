import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var authService: AuthenticationService
    @EnvironmentObject var quickActionService: QuickActionService
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Bookmarks", systemImage: "bookmark.fill", value: 0) {
                HomeView()
            }
            
            Tab("Notes", systemImage: "text.justify", value: 1) {
                NotesView()
            }
            
            Tab("Profile", systemImage: "person.fill", value: 2) {
                ProfileView()
            }
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
