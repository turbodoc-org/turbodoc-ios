import SwiftUI

struct HomeView: View {
    @EnvironmentObject var authService: AuthenticationService
    @State private var bookmarks: [BookmarkItem] = []
    @State private var isLoading = false
    @State private var isRefreshing = false
    @State private var errorMessage: String?
    @State private var showingDeleteConfirmation = false
    @State private var bookmarkToDelete: BookmarkItem?
    @State private var showingAddBookmark = false
    
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
            .alert("Delete Bookmark", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let bookmark = bookmarkToDelete {
                        deleteBookmark(bookmark)
                    }
                }
            } message: {
                if let bookmark = bookmarkToDelete {
                    Text("Are you sure you want to delete \"\(bookmark.title)\"? This action cannot be undone.")
                }
            }
            .sheet(isPresented: $showingAddBookmark) {
                AddBookmarkView(onSave: { url in
                    addBookmark(url: url)
                })
            }
            .overlay(alignment: .bottomTrailing) {
                Button(action: { showingAddBookmark = true }) {
                    Image(systemName: "plus")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.blue)
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 20)
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
            BookmarkTileView(bookmark: bookmark, onDelete: { bookmarkToDelete in
                confirmDeleteBookmark(bookmarkToDelete)
            }, onUpdateTags: { bookmarkToUpdate, newTags in
                updateBookmarkTags(bookmarkToUpdate, newTags: newTags)
            })
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowSeparator(.hidden)
        }
        .listStyle(PlainListStyle())
        .refreshable {
            await refreshBookmarks()
        }
    }
    
    private func loadBookmarks() {
        guard let user = authService.currentUser else {
            return
        }
        
        // Prevent multiple simultaneous loads
        guard !isLoading && !isRefreshing else { return }
        
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
    
    private func refreshBookmarks() async {
        guard let user = authService.currentUser else {
            return
        }
        
        // Prevent multiple simultaneous refreshes
        guard !isRefreshing && !isLoading else { return }
        
        isRefreshing = true
        errorMessage = nil
        
        do {
            // Configure API service with auth service
            APIService.shared.configure(authService: authService)
            
            let fetchedBookmarks = try await APIService.shared.fetchBookmarks(userId: user.id)
            
            await MainActor.run {
                self.bookmarks = fetchedBookmarks
                self.isRefreshing = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to refresh bookmarks: \(error.localizedDescription)"
                self.isRefreshing = false
            }
        }
    }
    
    private func confirmDeleteBookmark(_ bookmark: BookmarkItem) {
        bookmarkToDelete = bookmark
        showingDeleteConfirmation = true
    }
    
    private func deleteBookmark(_ bookmark: BookmarkItem) {        
        Task {
            do {
                try await APIService.shared.deleteBookmark(id: bookmark.id)
                await MainActor.run {
                    self.bookmarks.removeAll { $0.id == bookmark.id }
                    self.bookmarkToDelete = nil
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to delete bookmark: \(error.localizedDescription)"
                    self.bookmarkToDelete = nil
                }
            }
        }
    }
    
    private func updateBookmarkTags(_ bookmark: BookmarkItem, newTags: [String]) {
        Task {
            do {
                var updatedBookmark = bookmark
                updatedBookmark.tags = newTags
                let result = try await APIService.shared.updateBookmark(updatedBookmark)
                
                await MainActor.run {
                    if let index = self.bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
                        self.bookmarks[index] = result
                    }
                }
            } catch let networkError as NetworkError {                
                // Check if it's a decoding error but the request was successful
                if case .decodingError(let decodingError) = networkError {
                    // Optimistically update the UI since the API call likely succeeded
                    await MainActor.run {
                        if let index = self.bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
                            self.bookmarks[index].tags = newTags
                        }
                        self.errorMessage = "Tags updated successfully (response format issue)"
                    }
                } else {
                    await MainActor.run {
                        self.errorMessage = "Failed to update bookmark: \(networkError.localizedDescription)"
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to update bookmark: \(error.localizedDescription)"
                }
            }
        }
    }
    
    
    private func addBookmark(url: String) {
        guard let user = authService.currentUser else {
            errorMessage = "Please sign in to add bookmarks"
            return
        }
        
        Task {
            do {                
                // Fetch page metadata to get the actual title
                let metadata = try await APIService.shared.fetchOgImage(for: url)
                let pageTitle = metadata.title?.isEmpty == false ? metadata.title! : "Untitled"
                
                // Create bookmark object with actual title
                let bookmark = BookmarkItem(
                    title: pageTitle,
                    url: url,
                    contentType: .link,
                    userId: user.id
                )
                
                // Set OG image if available
                bookmark.ogImageURL = metadata.ogImage
                
                // Save to API
                let savedBookmark = try await APIService.shared.saveBookmark(bookmark)
                
                // Update UI
                await MainActor.run {
                    self.bookmarks.insert(savedBookmark, at: 0)
                    self.showingAddBookmark = false
                }
                
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to add bookmark: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct TagEditorView: View {
    let bookmark: BookmarkItem
    let onSave: ([String]) -> Void
    
    @State private var tagText = ""
    @State private var tags: [String] = []
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bookmark")
                        .font(.headline)
                    Text(bookmark.title)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Add Tags")
                        .font(.headline)
                    
                    HStack {
                        TextField("Enter tag name", text: $tagText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onSubmit {
                                addTag()
                            }
                        
                        Button("Add", action: addTag)
                            .disabled(tagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    
                    if !tags.isEmpty {
                        Text("Current Tags")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 8) {
                            ForEach(tags, id: \.self) { tag in
                                HStack {
                                    Text(tag)
                                        .font(.caption)
                                        .lineLimit(1)
                                    
                                    Button(action: { removeTag(tag) }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.yellow.opacity(0.2))
                                .foregroundColor(Color.orange.opacity(0.8))
                                .cornerRadius(12)
                            }
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Edit Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(tags)
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            tags = bookmark.tags
        }
    }
    
    private func addTag() {
        let newTag = tagText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !newTag.isEmpty && !tags.contains(newTag) {
            tags.append(newTag)
            tagText = ""
        }
    }
    
    private func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }
}

struct BookmarkTileView: View {
    let bookmark: BookmarkItem
    let onDelete: (BookmarkItem) -> Void
    let onUpdateTags: (BookmarkItem, [String]) -> Void
    
    @State private var showingTagEditor = false
    @State private var ogImage: String? = nil
    @State private var imageLoading = false
    @State private var imageError = false
    
    var body: some View {
        Button(action: openURL) {
            VStack(spacing: 0) {
                // OG Image Header (160pt height like web version)
                ogImageHeader
                
                // Main content area
                HStack(spacing: 12) {
                    // Content type icon (smaller since we have OG image)
                    Image(systemName: iconForContentType(bookmark.contentType))
                        .font(.footnote)
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(colorForContentType(bookmark.contentType))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    
                    // Content
                    VStack(alignment: .leading, spacing: 4) {
                        Text(bookmark.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        
                        if let url = bookmark.url {
                            HStack(spacing: 4) {
                                Image(systemName: "globe")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(domainFromURL(url))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(formattedTimeAdded(bookmark.timeAdded))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                }
                .padding(12)
                
                // Tags section
                if !bookmark.tags.isEmpty {
                    HStack {
                        ForEach(bookmark.tags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.yellow.opacity(0.2))
                                .foregroundColor(Color.orange.opacity(0.8))
                                .cornerRadius(8)
                        }
                        
                        if bookmark.tags.count > 3 {
                            Text("+\(bookmark.tags.count - 3)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // Status badge
                        Text(bookmark.status.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(statusColor.opacity(0.2))
                            .foregroundColor(statusColor)
                            .cornerRadius(8)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                } else {
                    // Status badge when no tags
                    HStack {
                        Spacer()
                        Text(bookmark.status.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(statusColor.opacity(0.2))
                            .foregroundColor(statusColor)
                            .cornerRadius(8)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        .contextMenu {
            contextMenuContent
        }
        .sheet(isPresented: $showingTagEditor) {
            TagEditorView(bookmark: bookmark, onSave: { newTags in
                onUpdateTags(bookmark, newTags)
            })
        }
        .onAppear {
            fetchOgImageIfNeeded()
        }
    }
    
    private var ogImageHeader: some View {
        Rectangle()
            .frame(height: 120)
            .overlay {
                if let ogImageUrl = ogImage, !imageError {
                    AsyncImage(url: URL(string: ogImageUrl)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        if imageLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .yellow))
                        } else {
                            domainFallbackView
                        }
                    }
                } else {
                    domainFallbackView
                }
            }
            .clipped()
    }
    
    private var domainFallbackView: some View {
        Color(.systemGray5)
        .overlay {
            VStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.title2)
                    .foregroundColor(.secondary)
                if let url = bookmark.url {
                    Text(domainFromURL(url))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
    
    private func fetchOgImageIfNeeded() {
        // Only fetch if we don't already have an image and URL exists
        guard let url = bookmark.url,
              ogImage == nil,
              !imageLoading,
              !imageError else { return }
        
        // Use cached image if available
        if let cachedImage = bookmark.ogImageURL {
            ogImage = cachedImage
            return
        }
        
        imageLoading = true
        
        Task {
            do {
                let response = try await APIService.shared.fetchOgImage(for: url)
                await MainActor.run {
                    if let ogImageUrl = response.ogImage {
                        self.ogImage = ogImageUrl
                    } else {
                        self.imageError = true
                    }
                    self.imageLoading = false
                }
            } catch {
                await MainActor.run {
                    self.imageError = true
                    self.imageLoading = false
                }
            }
        }
    }
    
    private var statusColor: Color {
        switch bookmark.status {
        case .unread:
            return .orange
        case .read:
            return .green
        case .archived:
            return .gray
        }
    }
    
    private var contextMenuContent: some View {
        Group {
            Button(action: openURL) {
                Label("Open Link", systemImage: "link")
            }
            
            Button(action: { showingTagEditor = true }) {
                Label("Edit Tags", systemImage: "tag")
            }
            
            Divider()
            
            Button(action: { onDelete(bookmark) }) {
                Label("Delete", systemImage: "trash")
            }
            .foregroundColor(.red)
        }
    }
    
    private func openURL() {
        guard let urlString = bookmark.url,
              let url = URL(string: urlString) else {
            return
        }
        
        UIApplication.shared.open(url)
    }
    
    private func domainFromURL(_ urlString: String) -> String {
        guard let url = URL(string: urlString),
              let host = url.host else {
            return urlString
        }
        return host.replacingOccurrences(of: "www.", with: "")
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
    
    private func colorForContentType(_ contentType: BookmarkItem.ContentType) -> Color {
        switch contentType {
        case .link:
            return .blue
        case .image:
            return .green
        case .video:
            return .red
        case .text:
            return Color.yellow.opacity(0.8)
        case .file:
            return .purple
        }
    }
    
    private func formattedTimeAdded(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.month], from: date, to: now)
        
        guard let months = components.month else { return "Recently" }
        
        if months == 0 {
            return "This month"
        } else if months == 1 {
            return "1 month ago"
        } else {
            return "\(months) months ago"
        }
    }
}
