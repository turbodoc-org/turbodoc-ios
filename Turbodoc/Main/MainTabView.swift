import SwiftUI
import UIKit

struct MainTabView: View {
    @EnvironmentObject var authService: AuthenticationService
    @EnvironmentObject var quickActionService: QuickActionService
    @State private var selectedTab = AppTab.bookmarks
    @State private var tabBarVisibility = TabBarVisibility()
    @State private var isKeyboardVisible = false

    var body: some View {
        GeometryReader { proxy in
            TabView(selection: $selectedTab) {
                Tab(AppTab.bookmarks.title, systemImage: AppTab.bookmarks.systemImage, value: AppTab.bookmarks) {
                    HomeView()
                        .toolbar(.hidden, for: .tabBar)
                }

                Tab(AppTab.notes.title, systemImage: AppTab.notes.systemImage, value: AppTab.notes) {
                    NotesView()
                        .toolbar(.hidden, for: .tabBar)
                }

                Tab(AppTab.profile.title, systemImage: AppTab.profile.systemImage, value: AppTab.profile) {
                    ProfileView()
                        .toolbar(.hidden, for: .tabBar)
                }
            }
            // An inset, not an overlay, so lists end above the bar and scroll
            // under it.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showsTabBar {
                    TurbodocTabBar(selection: $selectedTab, addTitle: addTitle, onAdd: add)
                        // Sit low, over the home indicator area, like the
                        // system bar; keep clear of the edge on home-button phones.
                        .padding(.bottom, proxy.safeAreaInsets.bottom > 0 ? -12 : 10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .environment(tabBarVisibility)
        // Like Safari, the bar steps aside for the keyboard.
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeOut(duration: 0.2)) { isKeyboardVisible = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.2)) { isKeyboardVisible = false }
        }
        .onChange(of: quickActionService.currentAction) { _, action in
            switch action {
            case .newBookmark:
                selectedTab = .bookmarks
            case .newNote, .newVoiceNote, .newPhotoNote:
                selectedTab = .notes
            case .search, .none:
                break
            }
        }
    }

    private var showsTabBar: Bool {
        !isKeyboardVisible && !tabBarVisibility.isHidden
    }

    private var addTitle: String {
        selectedTab == .notes ? "New Note" : "New Bookmark"
    }

    private func add() {
        HapticManager.shared.light()
        quickActionService.triggerAction(selectedTab == .notes ? .newNote : .newBookmark)
    }
}
