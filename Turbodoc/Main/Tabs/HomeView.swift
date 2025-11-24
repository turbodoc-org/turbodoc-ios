import SwiftUI

struct HomeView: View {
    @EnvironmentObject var authService: AuthenticationService
    @EnvironmentObject var quickActionService: QuickActionService
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
    @State private var showingFilters = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastRefreshTime = Date()
    @AppStorage("viewMode") private var viewMode: ViewMode = .grid
    @AppStorage("bookmarksFilter") private var selectedFilter: String = "all"
    
    @State private var isConnected = NetworkMonitor.shared.isConnected
    @State private var pendingOperationsCount = SyncQueueManager.shared.pendingOperationsCount
    
    // Filter states
    @State private var selectedStatus: BookmarkItem.ItemStatus? = nil
    @State private var selectedTags: Set<String> = []
    @State private var sortOption: SortOption = .dateAddedDesc
    @State private var availableTags: [String] = []
    
    enum SortOption: String, CaseIterable, Identifiable {
        case dateAddedDesc = "Newest First"
        case dateAddedAsc = "Oldest First"
        case dateModifiedDesc = "Recently Updated"
        case dateModifiedAsc = "Least Recently Updated"
        case titleAsc = "Title A-Z"
        case titleDesc = "Title Z-A"
        
        var id: String { rawValue }
    }
    
    var body: some View {
        NavigationView {
            contentWithModifiers
        }
    }
    
    private var contentWithModifiers: some View {
        mainContent
            .navigationTitle("Bookmarks")
            .toolbar { toolbarContent }
            .searchable(text: $searchText, prompt: "Search bookmarks...")
            .onChange(of: searchText) {
                applyFilterPills()
            }
            .onChange(of: selectedStatus) { _, _ in
                applyFilterPills()
            }
            .onChange(of: selectedTags) { _, _ in
                applyFilterPills()
            }
            .onChange(of: sortOption) { _, _ in
                applyFilterPills()
            }
            .onAppear {
                refreshBookmarksIfNeeded()
            }
            .onChange(of: scenePhase) {
                handleScenePhaseChange()
            }
            .onChange(of: authService.authenticationStatus) {
                handleAuthStatusChange()
            }
            .onChange(of: authService.currentUser) {
                handleUserChange()
            }
            .alert("Delete Bookmark", isPresented: $showingDeleteConfirmation) {
                deleteAlertButtons
            } message: {
                deleteAlertMessage
            }
            .sheet(isPresented: $showingAddBookmark) {
                AddBookmarkView(onSave: { url, tags in
                    addBookmark(url: url, tags: tags)
                })
            }
            .sheet(isPresented: $showingFilters) {
                filterSheet
            }
            .onChange(of: quickActionService.currentAction) { _, action in
                handleQuickAction(action)
            }
            .onReceive(NetworkMonitor.shared.connectionStatusChanged) { connected in
                Task { @MainActor in
                    isConnected = connected
                }
            }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                handleTimerTick()
            }
            .overlay(alignment: .bottomTrailing) {
                addBookmarkButton
            }
    }
    
    private var filterSheet: some View {
        FilterView(
            selectedStatus: $selectedStatus,
            selectedTags: $selectedTags,
            sortOption: $sortOption,
            availableTags: availableTags,
            onClearAll: clearAllFilters
        )
    }
    
    private func handleScenePhaseChange() {
        if scenePhase == .active && authService.authenticationStatus == .authenticated {
            refreshBookmarksIfNeeded()
        }
    }
    
    private func handleAuthStatusChange() {
        if authService.authenticationStatus == .authenticated {
            loadBookmarks()
        }
    }
    
    private func handleUserChange() {
        if authService.currentUser != nil {
            loadBookmarks()
        }
    }
    
    private func handleTimerTick() {
        isConnected = NetworkMonitor.shared.isConnected
        pendingOperationsCount = SyncQueueManager.shared.pendingOperationsCount
    }
    
    // MARK: - Subviews
    
    private var mainContent: some View {
        VStack(spacing: 0) {
            offlineBanner
            
            if isLoading {
                loadingView
            } else {
                contentArea
            }
        }
    }
    
    private var offlineBanner: some View {
        OfflineBanner(
            isConnected: isConnected,
            pendingOperations: pendingOperationsCount,
            onTapSync: {
                Task {
                    await SyncQueueManager.shared.processPendingOperations()
                }
            }
        )
    }
    
    private var contentArea: some View {
        Group {
            if !allBookmarks.isEmpty {
                VStack(spacing: 0) {
                    filterPillsBar
                    contentList
                }
            } else if bookmarks.isEmpty {
                emptyStateView
            } else {
                bookmarksList
            }
        }
    }
    
    private var filterPillsBar: some View {
        FilterPillsBar(
            filters: filterItems,
            selectedFilter: selectedFilter,
            onSelect: { filterId in
                selectedFilter = filterId
                applyFilterPills()
            }
        )
    }
    
    private var contentList: some View {
        Group {
            if bookmarks.isEmpty {
                emptyStateView
            } else {
                bookmarksList
            }
        }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button(action: {
                HapticManager.shared.selection()
                showingFilters.toggle()
            }) {
                Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .imageScale(.large)
                    .foregroundColor(hasActiveFilters ? .blue : .primary)
            }
        }
        
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(action: {
                HapticManager.shared.selection()
                viewMode = viewMode == .grid ? .list : .grid
            }) {
                Image(systemName: viewMode == .grid ? "list.bullet" : "square.grid.2x2")
                    .imageScale(.large)
            }
        }
    }
    
    @ViewBuilder
    private var deleteAlertButtons: some View {
        Button("Cancel", role: .cancel) { }
        Button("Delete", role: .destructive) {
            if let bookmark = bookmarkToDelete {
                deleteBookmark(bookmark)
            }
        }
    }
    
    @ViewBuilder
    private var deleteAlertMessage: some View {
        if let bookmark = bookmarkToDelete {
            Text("Are you sure you want to delete \"\(bookmark.title)\"? This action cannot be undone.")
        }
    }
    
    private var addBookmarkButton: some View {
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
    
    private func handleQuickAction(_ action: QuickAction?) {
        if action == .newBookmark {
            showingAddBookmark = true
            HapticManager.shared.light()
        } else if action == .search {
            HapticManager.shared.light()
        }
    }
    
    // MARK: - Computed Properties
    
    private var filterItems: [FilterPillsBar.FilterItem] {
        // Get base filtered bookmarks (after applying tags, status, search)
        var baseFiltered = allBookmarks
        
        // Apply status filter from filter sheet
        if let status = selectedStatus {
            baseFiltered = baseFiltered.filter { $0.status == status }
        }
        
        // Apply tag filter from filter sheet
        if !selectedTags.isEmpty {
            baseFiltered = baseFiltered.filter { bookmark in
                let bookmarkTags = Set(bookmark.tags)
                return !bookmarkTags.isDisjoint(with: selectedTags)
            }
        }
        
        // Apply search filter
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            baseFiltered = baseFiltered.filter { bookmark in
                let titleMatch = bookmark.title.localizedCaseInsensitiveContains(trimmedQuery)
                let urlMatch = bookmark.url?.localizedCaseInsensitiveContains(trimmedQuery) == true
                let tagMatch = bookmark.tags.contains { tag in
                    tag.localizedCaseInsensitiveContains(trimmedQuery)
                }
                return titleMatch || urlMatch || tagMatch
            }
        }
        
        let totalCount = baseFiltered.count
        let favoriteCount = baseFiltered.filter { $0.isFavorite }.count
        
        let allItem = FilterPillsBar.FilterItem(id: "all", title: "All", count: totalCount)
        let favoritesItem = FilterPillsBar.FilterItem(id: "favorites", title: "Favorites", count: favoriteCount)
        
        return [allItem, favoritesItem]
    }
    
    private var hasActiveFilters: Bool {
        selectedFilter != "all" || selectedStatus != nil || !selectedTags.isEmpty || sortOption != .dateAddedDesc
    }
    
    // MARK: - Views
    
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
            
            Image(systemName: hasActiveFilters || !searchText.isEmpty ? "magnifyingglass" : "bookmark")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            VStack(spacing: 16) {
                Text(emptyStateTitle)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text(emptyStateMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                // Only show error if there's an actual error, not when filters return no results
                if let errorMessage = errorMessage, !hasActiveFilters && searchText.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Show clear filters button when filters are active
                if hasActiveFilters || !searchText.isEmpty {
                    Button(action: clearAllFilters) {
                        Text("Clear Filters")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .padding(.top, 8)
                }
            }
            
            Spacer()
        }
    }
    
    private var emptyStateTitle: String {
        if hasActiveFilters || !searchText.isEmpty {
            return "No Results Found"
        }
        return "No Bookmarks Yet"
    }
    
    private var emptyStateMessage: String {
        if !searchText.isEmpty {
            return "No bookmarks match '\(searchText)'"
        } else if hasActiveFilters {
            return "No bookmarks match your filters"
        }
        return "Your saved content will appear here"
    }
    
    private var bookmarksList: some View {
        Group {
            if viewMode == .grid {
                gridView
            } else {
                listView
            }
        }
    }
    
    private var gridView: some View {
        List(bookmarks, id: \.id) { bookmark in
            BookmarkTileView(bookmark: bookmark, onDelete: { bookmarkToDelete in
                confirmDeleteBookmark(bookmarkToDelete)
            }, onUpdate: { updatedBookmark in
                updateBookmark(updatedBookmark)
            }, onToggleFavorite: { bookmarkToToggle in
                toggleFavorite(bookmarkToToggle)
            })
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    toggleFavorite(bookmark)
                } label: {
                    Label(bookmark.isFavorite ? "Unfavorite" : "Favorite", systemImage: bookmark.isFavorite ? "star.slash.fill" : "star.fill")
                }
                .tint(.yellow)
                
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
    
    private var listView: some View {
        List(bookmarks, id: \.id) { bookmark in
            BookmarkCompactView(bookmark: bookmark, onDelete: { bookmarkToDelete in
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
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
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
                    self.extractAvailableTags()
                    self.applyFilterPills()
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    // Only show error if we don't have any bookmarks (no cache)
                    if self.allBookmarks.isEmpty {
                        self.errorMessage = "Failed to load bookmarks: \(error.localizedDescription)"
                    }
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
                self.extractAvailableTags()
                self.applyFilterPills()
                self.isRefreshing = false
            }
        } catch {
            await MainActor.run {
                // Only show error if we have no cached bookmarks
                if self.allBookmarks.isEmpty {
                    self.errorMessage = "Failed to refresh bookmarks: \(error.localizedDescription)"
                }
                self.isRefreshing = false
            }
        }
    }
    
    private func confirmDeleteBookmark(_ bookmark: BookmarkItem) {
        bookmarkToDelete = bookmark
        showingDeleteConfirmation = true
    }
    
    private func deleteBookmark(_ bookmark: BookmarkItem) {
        HapticManager.shared.warning()
        
        Task {
            do {
                try await APIService.shared.deleteBookmark(id: bookmark.id)
                await MainActor.run {
                    self.bookmarks.removeAll { $0.id == bookmark.id }
                    self.allBookmarks.removeAll { $0.id == bookmark.id }
                    self.bookmarkToDelete = nil
                    HapticManager.shared.success()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to delete bookmark: \(error.localizedDescription)"
                    self.bookmarkToDelete = nil
                    HapticManager.shared.error()
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
                    HapticManager.shared.success()
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
                        HapticManager.shared.success()
                    }
                } else {
                    await MainActor.run {
                        self.errorMessage = "Failed to update bookmark: \(networkError.localizedDescription)"
                        HapticManager.shared.error()
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to update bookmark: \(error.localizedDescription)"
                    HapticManager.shared.error()
                }
            }
        }
    }
    
    private func markAsRead(_ bookmark: BookmarkItem) {
        HapticManager.shared.light()
        var updatedBookmark = bookmark
        updatedBookmark.status = .read
        updateBookmark(updatedBookmark)
    }
    
    private func archiveBookmark(_ bookmark: BookmarkItem) {
        HapticManager.shared.light()
        var updatedBookmark = bookmark
        updatedBookmark.status = .archived
        updateBookmark(updatedBookmark)
    }
    
    private func toggleFavorite(_ bookmark: BookmarkItem) {
        // Optimistic UI update
        bookmark.isFavorite.toggle()
        
        // Update in local arrays
        if let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
            bookmarks[index] = bookmark
        }
        if let index = allBookmarks.firstIndex(where: { $0.id == bookmark.id }) {
            allBookmarks[index] = bookmark
        }
        
        // Save to server in background
        Task {
            do {
                let result = try await APIService.shared.updateBookmark(bookmark)
                
                await MainActor.run {
                    // Update with server response
                    if let index = self.bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
                        self.bookmarks[index] = result
                    }
                    if let index = self.allBookmarks.firstIndex(where: { $0.id == bookmark.id }) {
                        self.allBookmarks[index] = result
                    }
                }
            } catch {
                await MainActor.run {
                    // Revert optimistic update on error
                    bookmark.isFavorite.toggle()
                    if let index = self.bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
                        self.bookmarks[index] = bookmark
                    }
                    if let index = self.allBookmarks.firstIndex(where: { $0.id == bookmark.id }) {
                        self.allBookmarks[index] = bookmark
                    }
                    self.errorMessage = "Failed to update favorite status"
                }
            }
        }
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
    
    // MARK: - Filter Methods
    
    private func applyFilterPills() {
        var filtered = allBookmarks
        
        // Apply status filter from filter sheet first
        if let status = selectedStatus {
            filtered = filtered.filter { $0.status == status }
        }
        
        // Apply tag filter from filter sheet
        if !selectedTags.isEmpty {
            filtered = filtered.filter { bookmark in
                !Set(bookmark.tags).isDisjoint(with: selectedTags)
            }
        }
        
        // Apply search filter
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            filtered = filtered.filter { bookmark in
                bookmark.title.localizedCaseInsensitiveContains(trimmedQuery) ||
                bookmark.url?.localizedCaseInsensitiveContains(trimmedQuery) == true ||
                bookmark.tags.contains { tag in
                    tag.localizedCaseInsensitiveContains(trimmedQuery)
                }
            }
        }
        
        // Apply filter pill (favorites filter on top of everything else)
        if selectedFilter == "favorites" {
            filtered = filtered.filter { $0.isFavorite }
        }
        // "all" means no additional favorite filtering
        
        // Apply sorting
        filtered = sortBookmarks(filtered, by: sortOption)
        
        bookmarks = filtered
        
        HapticManager.shared.selection()
    }
    
    private func applyFiltersAndSearch() {
        var filtered = allBookmarks
        
        // Clear error message when actively filtering (not an error, just no results)
        if hasActiveFilters || !searchText.isEmpty {
            errorMessage = nil
        }
        
        // Apply status filter
        if let status = selectedStatus {
            filtered = filtered.filter { $0.status == status }
        }
        
        // Apply tag filter
        if !selectedTags.isEmpty {
            filtered = filtered.filter { bookmark in
                !Set(bookmark.tags).isDisjoint(with: selectedTags)
            }
        }
        
        // Apply search filter
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            filtered = filtered.filter { bookmark in
                bookmark.title.localizedCaseInsensitiveContains(trimmedQuery) ||
                bookmark.url?.localizedCaseInsensitiveContains(trimmedQuery) == true ||
                bookmark.tags.contains { tag in
                    tag.localizedCaseInsensitiveContains(trimmedQuery)
                }
            }
        }
        
        // Apply sorting
        filtered = sortBookmarks(filtered, by: sortOption)
        
        bookmarks = filtered
    }
    
    private func sortBookmarks(_ bookmarks: [BookmarkItem], by option: SortOption) -> [BookmarkItem] {
        switch option {
        case .dateAddedDesc:
            return bookmarks.sorted { (a: BookmarkItem, b: BookmarkItem) in
                a.timeAdded > b.timeAdded
            }
        case .dateAddedAsc:
            return bookmarks.sorted { (a: BookmarkItem, b: BookmarkItem) in
                a.timeAdded < b.timeAdded
            }
        case .dateModifiedDesc:
            // No updatedAt property, use timeAdded as fallback
            return bookmarks.sorted { (a: BookmarkItem, b: BookmarkItem) in
                a.timeAdded > b.timeAdded
            }
        case .dateModifiedAsc:
            // No updatedAt property, use timeAdded as fallback
            return bookmarks.sorted { (a: BookmarkItem, b: BookmarkItem) in
                a.timeAdded < b.timeAdded
            }
        case .titleAsc:
            return bookmarks.sorted { (a: BookmarkItem, b: BookmarkItem) in
                a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        case .titleDesc:
            return bookmarks.sorted { (a: BookmarkItem, b: BookmarkItem) in
                a.title.localizedCaseInsensitiveCompare(b.title) == .orderedDescending
            }
        }
    }
    
    private func clearAllFilters() {
        selectedFilter = "all"
        selectedStatus = nil
        selectedTags.removeAll()
        sortOption = .dateAddedDesc
        searchText = ""
        applyFilterPills()
        HapticManager.shared.light()
    }
    
    private func extractAvailableTags() {
        var tags = Set<String>()
        for bookmark in allBookmarks {
            tags.formUnion(bookmark.tags)
        }
        availableTags = Array(tags).sorted()
    }
}

// MARK: - Filter View

struct FilterView: View {
    @Binding var selectedStatus: BookmarkItem.ItemStatus?
    @Binding var selectedTags: Set<String>
    @Binding var sortOption: HomeView.SortOption
    let availableTags: [String]
    let onClearAll: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                // Status Filter Section
                Section(header: Text("Status")) {
                    ForEach([BookmarkItem.ItemStatus.unread, BookmarkItem.ItemStatus.read, BookmarkItem.ItemStatus.archived], id: \.self) { status in
                        Button(action: {
                            if selectedStatus == status {
                                selectedStatus = nil
                            } else {
                                selectedStatus = status
                            }
                            HapticManager.shared.selection()
                        }) {
                            HStack {
                                Circle()
                                    .fill(colorForStatus(status))
                                    .frame(width: 12, height: 12)
                                
                                Text(status.rawValue.capitalized)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                if selectedStatus == status {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                    
                    if selectedStatus != nil {
                        Button(action: {
                            selectedStatus = nil
                            HapticManager.shared.light()
                        }) {
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                Text("Clear Status Filter")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                // Tag Filter Section
                if !availableTags.isEmpty {
                    Section(header: Text("Tags")) {
                        ForEach(availableTags, id: \.self) { tag in
                            Button(action: {
                                if selectedTags.contains(tag) {
                                    selectedTags.remove(tag)
                                } else {
                                    selectedTags.insert(tag)
                                }
                                HapticManager.shared.selection()
                            }) {
                                HStack {
                                    Image(systemName: "tag.fill")
                                        .font(.caption)
                                        .foregroundColor(selectedTags.contains(tag) ? .blue : .secondary)
                                    
                                    Text(tag)
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                    
                                    if selectedTags.contains(tag) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                        
                        if !selectedTags.isEmpty {
                            Button(action: {
                                selectedTags.removeAll()
                                HapticManager.shared.light()
                            }) {
                                HStack {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                    Text("Clear Tag Filters (\(selectedTags.count))")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                
                // Sort Section
                Section(header: Text("Sort By")) {
                    ForEach(HomeView.SortOption.allCases) { option in
                        Button(action: {
                            sortOption = option
                            HapticManager.shared.selection()
                        }) {
                            HStack {
                                Text(option.rawValue)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                if sortOption == option {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Clear All") {
                        onClearAll()
                    }
                    .disabled(selectedStatus == nil && selectedTags.isEmpty && sortOption == .dateAddedDesc)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func colorForStatus(_ status: BookmarkItem.ItemStatus) -> Color {
        switch status {
        case .unread:
            return .orange
        case .read:
            return .green
        case .archived:
            return .gray
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
    let onToggleFavorite: (BookmarkItem) -> Void
    
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
                                .background(Color(.systemGray5))
                                .foregroundColor(Color(.label))
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
        .overlay(alignment: .topTrailing) {
            favoriteButton
        }
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
    
    private var favoriteButton: some View {
        Button(action: {
            HapticManager.shared.light()
            onToggleFavorite(bookmark)
        }) {
            Image(systemName: bookmark.isFavorite ? "star.fill" : "star")
                .font(.system(size: 12))
                .foregroundColor(bookmark.isFavorite ? .yellow : .white)
                .padding(8)
                .background(Color.black.opacity(0.3))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(8)
    }
    
    @ViewBuilder
    private var contextMenuContent: some View {
        Button(action: openURL) {
            Label("Open Link", systemImage: "link")
        }
        
        Button(action: { showingEditor = true }) {
            Label("Edit Bookmark", systemImage: "pencil")
        }
        
        Button(action: copyLink) {
            Label("Copy Link", systemImage: "doc.on.doc")
        }
        
        Button(action: shareBookmark) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        
        Divider()
        
        if bookmark.status != .read {
            Button(action: {
                HapticManager.shared.selection()
                var updatedBookmark = bookmark
                updatedBookmark.status = .read
                onUpdate(updatedBookmark)
            }) {
                Label("Mark as Read", systemImage: "checkmark.circle")
            }
        }
        
        if bookmark.status != .unread {
            Button(action: {
                HapticManager.shared.selection()
                var updatedBookmark = bookmark
                updatedBookmark.status = .unread
                onUpdate(updatedBookmark)
            }) {
                Label("Mark as Unread", systemImage: "circle")
            }
        }
        
        if bookmark.status != .archived {
            Button(action: {
                HapticManager.shared.selection()
                var updatedBookmark = bookmark
                updatedBookmark.status = .archived
                onUpdate(updatedBookmark)
            }) {
                Label("Archive", systemImage: "archivebox")
            }
        }
        
        Divider()
        
        Button(role: .destructive) {
            HapticManager.shared.warning()
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
    
    private func copyLink() {
        guard let urlString = bookmark.url else { return }
        UIPasteboard.general.string = urlString
        HapticManager.shared.success()
    }
    
    private func shareBookmark() {
        guard let urlString = bookmark.url,
              let url = URL(string: urlString) else {
            return
        }
        
        HapticManager.shared.light()
        
        let activityVC = UIActivityViewController(
            activityItems: [url, bookmark.title],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            // Find the topmost presented view controller
            var topController = rootViewController
            while let presented = topController.presentedViewController {
                topController = presented
            }
            
            // For iPad, set popover presentation
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = topController.view
                popover.sourceRect = CGRect(x: topController.view.bounds.midX, y: topController.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            
            topController.present(activityVC, animated: true)
        }
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

// MARK: - Compact List View

struct BookmarkCompactView: View {
    let bookmark: BookmarkItem
    let onDelete: (BookmarkItem) -> Void
    let onUpdate: (BookmarkItem) -> Void
    
    @State private var showingEditor = false
    
    var body: some View {
        Button(action: openURL) {
            HStack(spacing: 12) {
                // Favicon or icon
                Image(systemName: iconForContentType(bookmark.contentType))
                    .font(.footnote)
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(colorForContentType(bookmark.contentType))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(bookmark.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        if let url = bookmark.url {
                            Text(domainFromURL(url))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        
                        if !bookmark.tags.isEmpty {
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(bookmark.tags.prefix(2).joined(separator: ", "))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                
                Spacer()
                
                // Status indicator
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            contextMenuContent
        }
        .sheet(isPresented: $showingEditor) {
            BookmarkEditView(bookmark: bookmark, onSave: { updatedBookmark in
                onUpdate(updatedBookmark)
            })
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
        
        Button(action: copyLink) {
            Label("Copy Link", systemImage: "doc.on.doc")
        }
        
        Button(action: shareBookmark) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        
        Divider()
        
        if bookmark.status != .read {
            Button(action: {
                HapticManager.shared.selection()
                var updatedBookmark = bookmark
                updatedBookmark.status = .read
                onUpdate(updatedBookmark)
            }) {
                Label("Mark as Read", systemImage: "checkmark.circle")
            }
        }
        
        if bookmark.status != .unread {
            Button(action: {
                HapticManager.shared.selection()
                var updatedBookmark = bookmark
                updatedBookmark.status = .unread
                onUpdate(updatedBookmark)
            }) {
                Label("Mark as Unread", systemImage: "circle")
            }
        }
        
        if bookmark.status != .archived {
            Button(action: {
                HapticManager.shared.selection()
                var updatedBookmark = bookmark
                updatedBookmark.status = .archived
                onUpdate(updatedBookmark)
            }) {
                Label("Archive", systemImage: "archivebox")
            }
        }
        
        Divider()
        
        Button(role: .destructive) {
            HapticManager.shared.warning()
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
    
    private func copyLink() {
        guard let urlString = bookmark.url else { return }
        UIPasteboard.general.string = urlString
        HapticManager.shared.success()
    }
    
    private func shareBookmark() {
        guard let urlString = bookmark.url,
              let url = URL(string: urlString) else {
            return
        }
        
        HapticManager.shared.light()
        
        let activityVC = UIActivityViewController(
            activityItems: [url, bookmark.title],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            var topController = rootViewController
            while let presented = topController.presentedViewController {
                topController = presented
            }
            
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = topController.view
                popover.sourceRect = CGRect(x: topController.view.bounds.midX, y: topController.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            
            topController.present(activityVC, animated: true)
        }
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
