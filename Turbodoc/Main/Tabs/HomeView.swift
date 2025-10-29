import SwiftUI

struct HomeView: View {
    @EnvironmentObject var authService: AuthenticationService
    @State private var bookmarks: [BookmarkItem] = []
    @State private var allBookmarks: [BookmarkItem] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var isRefreshing = false
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var showingDeleteConfirmation = false
    @State private var bookmarkToDelete: BookmarkItem?
    @State private var showingAddBookmark = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastRefreshTime = Date()
    
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
            .navigationTitle("Bookmarks")
            .searchable(text: $searchText, prompt: "Search bookmarks...")
            .onChange(of: searchText) {
                performSearch(query: searchText)
            }
            .onAppear {
                refreshBookmarksIfNeeded()
            }
            .onChange(of: scenePhase) {
                if scenePhase == .active && authService.isAuthenticated {
                    refreshBookmarksIfNeeded()
                }
            }
            .onChange(of: authService.isAuthenticated) {
                if authService.isAuthenticated {
                    loadBookmarks()
                }
            }
            .onChange(of: authService.currentUser) {
                if authService.currentUser != nil {
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
                AddBookmarkView(onSave: { url, tags in
                    addBookmark(url: url, tags: tags)
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
            }, onUpdate: { updatedBookmark in
                updateBookmark(updatedBookmark)
            })
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if bookmark.status != .read {
                    Button {
                        markAsRead(bookmark)
                    } label: {
                        Label("Read", systemImage: "checkmark.circle.fill")
                    }
                    .tint(.green)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                if bookmark.status != .archived {
                    Button {
                        archiveBookmark(bookmark)
                    } label: {
                        Label("Archive", systemImage: "archivebox.fill")
                    }
                    .tint(.gray)
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowSeparator(.hidden)
        }
        .listStyle(PlainListStyle())
        .refreshable {
            await refreshBookmarks()
        }
    }
    
    private func refreshBookmarksIfNeeded() {
        guard let user = authService.currentUser else {
            return
        }
        
        // Check if we should refresh (first load or if it's been more than 30 seconds since last refresh)
        let timeSinceLastRefresh = Date().timeIntervalSince(lastRefreshTime)
        let shouldRefresh = bookmarks.isEmpty || timeSinceLastRefresh > 30
        
        if shouldRefresh {
            lastRefreshTime = Date()
            
            // Use loadBookmarks for initial load, refreshBookmarks for subsequent refreshes
            if bookmarks.isEmpty {
                loadBookmarks()
            } else {
                Task {
                    await refreshBookmarks()
                }
            }
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
                    self.allBookmarks = fetchedBookmarks
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
                self.allBookmarks = fetchedBookmarks
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
                    self.allBookmarks.removeAll { $0.id == bookmark.id }
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
    
    private func updateBookmark(_ bookmark: BookmarkItem) {
        Task {
            do {
                let result = try await APIService.shared.updateBookmark(bookmark)
                
                await MainActor.run {
                    if let index = self.bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
                        self.bookmarks[index] = result
                    }
                    if let index = self.allBookmarks.firstIndex(where: { $0.id == bookmark.id }) {
                        self.allBookmarks[index] = result
                    }
                }
            } catch let networkError as NetworkError {                
                // Check if it's a decoding error but the request was successful
                if case .decodingError(let decodingError) = networkError {
                    // Optimistically update the UI since the API call likely succeeded
                    await MainActor.run {
                        if let index = self.bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
                            self.bookmarks[index] = bookmark
                        }
                        if let index = self.allBookmarks.firstIndex(where: { $0.id == bookmark.id }) {
                            self.allBookmarks[index] = bookmark
                        }
                        self.errorMessage = "Bookmark updated successfully"
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
    
    private func markAsRead(_ bookmark: BookmarkItem) {
        var updatedBookmark = bookmark
        updatedBookmark.status = .read
        updateBookmark(updatedBookmark)
    }
    
    private func archiveBookmark(_ bookmark: BookmarkItem) {
        var updatedBookmark = bookmark
        updatedBookmark.status = .archived
        updateBookmark(updatedBookmark)
    }
    
    private func addBookmark(url: String, tags: [String] = []) {
        guard let user = authService.currentUser else {
            errorMessage = "Please sign in to add bookmarks"
            return
        }
        
        Task {
            // Try to fetch metadata with retries
            let metadata = await fetchMetadataWithRetry(url: url, retries: 2)
            
            // Extract domain info from URL
            let urlComponents = URL(string: url)
            let domain = urlComponents?.host ?? ""
            let faviconURL = urlComponents.map { "https://www.google.com/s2/favicons?domain=\($0.host ?? "")&sz=64" }
            
            // Extract title, fallback to URL host if no title
            let pageTitle: String
            if let extractedTitle = metadata?.title, !extractedTitle.isEmpty {
                pageTitle = extractedTitle
            } else if !domain.isEmpty {
                pageTitle = domain
            } else {
                pageTitle = "Untitled"
            }
            
            // Create bookmark object with fetched metadata
            let bookmark = BookmarkItem(
                title: pageTitle,
                url: url,
                contentType: .link,
                userId: user.id
            )
            
            // Set tags if provided
            bookmark.tags = tags
            
            // Set OG image if available
            bookmark.ogImageURL = metadata?.ogImage
            
            // Store domain and favicon in metadata
            var metadataDict: [String: String] = [:]
            if !domain.isEmpty {
                metadataDict["domain"] = domain
            }
            if let favicon = faviconURL {
                metadataDict["faviconURL"] = favicon
            }
            if !metadataDict.isEmpty {
                bookmark.metadata = metadataDict
            }
            
            // Save to API
            do {
                let savedBookmark = try await APIService.shared.saveBookmark(bookmark)
                
                // Update UI
                await MainActor.run {
                    self.allBookmarks.insert(savedBookmark, at: 0)
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
    
    private func fetchMetadataWithRetry(url: String, retries: Int) async -> APIOgImageResponse? {
        var attempts = 0
        while attempts <= retries {
            do {
                let metadata = try await APIService.shared.fetchOgImage(for: url)
                return metadata
            } catch {
                attempts += 1
                if attempts > retries {
                    print("Failed to fetch metadata after \(retries) retries: \(error.localizedDescription)")
                    return nil
                }
                // Wait before retry (exponential backoff)
                try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempts)) * 1_000_000_000))
            }
        }
        return nil
    }
    
    private func performSearch(query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If search is empty, show all bookmarks
        if trimmedQuery.isEmpty {
            bookmarks = allBookmarks
            return
        }
        
        // For local search, filter the existing bookmarks
        if trimmedQuery.count < 3 {
            // Local search for short queries
            bookmarks = allBookmarks.filter { bookmark in
                bookmark.title.localizedCaseInsensitiveContains(trimmedQuery) ||
                bookmark.url?.localizedCaseInsensitiveContains(trimmedQuery) == true ||
                bookmark.tags.contains { tag in
                    tag.localizedCaseInsensitiveContains(trimmedQuery)
                }
            }
            return
        }
        
        // For longer queries, use API search
        guard let user = authService.currentUser else {
            return
        }
        
        // Debounce API calls
        isSearching = true
        
        Task {
            // Add a small delay to debounce rapid typing
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
            
            // Check if search text is still the same (user hasn't typed more)
            guard searchText.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedQuery else {
                return
            }
            
            do {
                let searchResults = try await APIService.shared.searchBookmarks(query: trimmedQuery, userId: user.id)
                
                await MainActor.run {
                    // Only update if this is still the current search
                    if self.searchText.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedQuery {
                        self.bookmarks = searchResults
                    }
                    self.isSearching = false
                }
            } catch {
                await MainActor.run {
                    // Fall back to local search on API error
                    self.bookmarks = self.allBookmarks.filter { bookmark in
                        bookmark.title.localizedCaseInsensitiveContains(trimmedQuery) ||
                        bookmark.url?.localizedCaseInsensitiveContains(trimmedQuery) == true ||
                        bookmark.tags.contains { tag in
                            tag.localizedCaseInsensitiveContains(trimmedQuery)
                        }
                    }
                    self.isSearching = false
                }
            }
        }
    }
}

struct TagEditorView: View {
    let bookmark: BookmarkItem
    let onSave: ([String]) -> Void
    
    @State private var tagText = ""
    @State private var tags: [String]
    @Environment(\.dismiss) private var dismiss
    
    init(bookmark: BookmarkItem, onSave: @escaping ([String]) -> Void) {
        self.bookmark = bookmark
        self.onSave = onSave
        self._tags = State(initialValue: bookmark.tags)
    }
    
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
    let onUpdate: (BookmarkItem) -> Void
    
    @State private var showingEditor = false
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
        .sheet(isPresented: $showingEditor) {
            BookmarkEditView(bookmark: bookmark, onSave: { updatedBookmark in
                onUpdate(updatedBookmark)
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
    
    @ViewBuilder
    private var contextMenuContent: some View {
        Button(action: openURL) {
            Label("Open Link", systemImage: "link")
        }
        
        Button(action: { showingEditor = true }) {
            Label("Edit Bookmark", systemImage: "pencil")
        }
        
        Divider()
        
        Button(role: .destructive) {
            onDelete(bookmark)
        } label: {
            Label("Delete", systemImage: "trash")
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
}
