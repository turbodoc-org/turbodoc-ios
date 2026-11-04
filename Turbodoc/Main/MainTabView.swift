import SwiftUI
import UIKit

struct MainTabView: View {
    @EnvironmentObject var authService: AuthenticationService
    @EnvironmentObject var quickActionService: QuickActionService
    @State private var selectedTab = AppTab.bookmarks
    @State private var tabBarVisibility = TabBarVisibility()
    @State private var isKeyboardVisible = false
    /// Height of the bar above the device's own bottom safe area, measured
    /// from the laid-out bar so the inset always matches what is drawn.
    @State private var tabBarHeight: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            TabView(selection: $selectedTab) {
                Tab(AppTab.bookmarks.title, systemImage: AppTab.bookmarks.systemImage, value: AppTab.bookmarks) {
                    HomeView()
                        .modifier(TabContent(bottomInset: contentBottomInset))
                }

                Tab(AppTab.notes.title, systemImage: AppTab.notes.systemImage, value: AppTab.notes) {
                    NotesView()
                        .modifier(TabContent(bottomInset: contentBottomInset))
                }

                Tab(AppTab.profile.title, systemImage: AppTab.profile.systemImage, value: AppTab.profile) {
                    ProfileView()
                        .modifier(TabContent(bottomInset: contentBottomInset))
                }
            }
            // The bar floats over the tabs. Safe-area changes made out here
            // never reach the lists inside the (UIKit-hosted) tab and
            // navigation containers, so each scroll view adds the bar's
            // height as a content margin itself (see `tabBarContentMargin`).
            .overlay(alignment: .bottom) {
                if showsTabBar {
                    TurbodocTabBar(selection: $selectedTab, addTitle: addTitle, onAdd: add)
                        // Sit low, over the home indicator area, like the
                        // system bar; keep clear of the edge on home-button phones.
                        .padding(.bottom, proxy.safeAreaInsets.bottom > 0 ? -12 : 10)
                        .onGeometryChange(for: CGFloat.self) { geometry in
                            geometry.size.height
                        } action: { height in
                            tabBarHeight = height
                        }
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

    /// Extra bottom safe area for the tab content: the bar plus a little
    /// breathing room, or nothing while the bar is away.
    private var contentBottomInset: CGFloat {
        showsTabBar ? tabBarHeight + 12 : 0
    }

    private var addTitle: String {
        selectedTab == .notes ? "New Note" : "New Bookmark"
    }

    private func add() {
        HapticManager.shared.light()
        quickActionService.triggerAction(selectedTab == .notes ? .newNote : .newBookmark)
    }
}

/// Hides the system tab bar and tells the tab's scroll views how much room
/// the app's own bar needs.
private struct TabContent: ViewModifier {
    let bottomInset: CGFloat

    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .tabBar)
            .environment(\.tabBarContentInset, bottomInset)
    }
}

extension EnvironmentValues {
    /// Room the floating tab bar needs at the bottom of a tab's scroll view.
    @Entry var tabBarContentInset: CGFloat = 0
}

private struct TabBarContentMargin: ViewModifier {
    @Environment(\.tabBarContentInset) private var inset

    func body(content: Content) -> some View {
        // Applies to both the content and the scroll indicators, so the
        // last row and the indicator both stop above the bar.
        content.contentMargins(.bottom, inset)
    }
}

extension View {
    /// Lets a tab's root list or scroll view scroll its last row clear of
    /// the floating tab bar.
    func tabBarContentMargin() -> some View {
        modifier(TabBarContentMargin())
    }
}
