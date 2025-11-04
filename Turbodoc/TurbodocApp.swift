//
//  TurbodocApp.swift
//  Turbodoc
//
//  Created by Nico Botha on 16/07/2025.
//

import SwiftUI
import SwiftData

@main
struct TurbodocApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authService = AuthenticationService()
    @StateObject private var quickActionService = QuickActionService()
    @Environment(\.scenePhase) private var scenePhase
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            User.self,
            BookmarkItem.self,
            NoteItem.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authService)
                .environmentObject(quickActionService)
                .onAppear {
                    // Configure services with auth service
                    APIService.shared.configure(authService: authService)
                    PendingBookmarksService.shared.configure(authService: authService)
                    
                    // If user is already authenticated, process pending bookmarks
                    if authService.isAuthenticated {
                        Task {
                            await PendingBookmarksService.shared.processPendingBookmarks()
                        }
                    }
                }
                .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
                    if isAuthenticated {
                        // Process pending bookmarks when user becomes authenticated
                        Task {
                            await PendingBookmarksService.shared.processPendingBookmarks()
                        }
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        handlePendingQuickAction()
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }
    
    private func handlePendingQuickAction() {
        guard let shortcutItem = QuickActionHandler.shared.shortcutItemToProcess else {
            return
        }
        
        QuickActionHandler.shared.shortcutItemToProcess = nil
        
        switch shortcutItem.type {
        case "com.turbodoc.newBookmark":
            quickActionService.triggerAction(.newBookmark)
        case "com.turbodoc.newNote":
            quickActionService.triggerAction(.newNote)
        case "com.turbodoc.search":
            quickActionService.triggerAction(.search)
        default:
            break
        }
    }
}
