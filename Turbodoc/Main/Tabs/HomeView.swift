import SwiftUI

struct HomeView: View {
    @EnvironmentObject var authService: AuthenticationService
    @State private var bookmarks: [BookmarkItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    loadingView
                } else if bookmarks.isEmpty {
                    emptyStateView
                } else {
                    bookmarksList
                }
            }
            .navigationTitle("Home")
            .onAppear {
                loadBookmarks()
            }
            .onChange(of: authService.isAuthenticated) { isAuthenticated in
                if isAuthenticated {
                    loadBookmarks()
                }
            }
            .onChange(of: authService.currentUser) { user in
                if user != nil {
                    loadBookmarks()
                }
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                .scaleEffect(1.5)
            
            Text("Loading your bookmarks...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Image(systemName: "bookmark")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            VStack(spacing: 16) {
                Text("No Bookmarks Yet")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Your saved content will appear here")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            
            Spacer()
        }
    }
    
    private var bookmarksList: some View {
        List(bookmarks, id: \.id) { bookmark in
            BookmarkRowView(bookmark: bookmark)
        }
        .listStyle(PlainListStyle())
        .refreshable {
            loadBookmarks()
        }
    }
    
    private func loadBookmarks() {
        guard let user = authService.currentUser else {
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                // Configure API service with auth service
                APIService.shared.configure(authService: authService)
                
                let fetchedBookmarks = try await APIService.shared.fetchBookmarks(userId: user.id)
                
                await MainActor.run {
                    self.bookmarks = fetchedBookmarks
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to load bookmarks: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
}

struct BookmarkRowView: View {
    let bookmark: BookmarkItem
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(bookmark.title)
                    .font(.headline)
                    .lineLimit(2)
                
                if let url = bookmark.url {
                    Text(url)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                HStack {
                    if !bookmark.tags.isEmpty {
                        ForEach(bookmark.tags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                        }
                    }
                    
                    Spacer()
                    
                    Text(bookmark.timeAdded, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Image(systemName: iconForContentType(bookmark.contentType))
                .font(.title2)
                .foregroundColor(.blue)
        }
        .padding(.vertical, 4)
    }
    
    private func iconForContentType(_ contentType: BookmarkItem.ContentType) -> String {
        switch contentType {
        case .link:
            return "link"
        case .image:
            return "photo"
        case .video:
            return "video"
        case .text:
            return "doc.text"
        case .file:
            return "doc"
        }
    }
}
