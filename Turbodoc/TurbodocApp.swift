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
    @StateObject private var authService = AuthenticationService()
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            User.self,
            BookmarkItem.self,
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
                .onAppear {
                    // Configure API service with auth service
                    APIService.shared.configure(authService: authService)
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
