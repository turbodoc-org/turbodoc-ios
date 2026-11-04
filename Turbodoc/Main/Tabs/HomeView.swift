import SwiftUI

struct HomeView: View {
    @EnvironmentObject var authService: AuthenticationService
    @EnvironmentObject var quickActionService: QuickActionService
    @State private var bookmarks: [BookmarkItem] = []
    @State private var allBookmarks: [BookmarkItem] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var actionErrorMessage: String?
    @State private var showingDeleteConfirmation = false
    @State private var bookmarkToDelete: BookmarkItem?
    @State private var showingAddBookmark = false
    @State private var showingFilters = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastRefreshTime = Date.distantPast
    @State private var refreshCoordinator = RefreshCoordinator()
    @AppStorage("viewMode") private var viewMode: ViewMode = .grid
    @AppStorage("bookmarksFilter") private var selectedFilter: String = "all"
    
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
        NavigationStack {
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
            .alert(
                "Something Went Wrong",
                isPresented: Binding(
                    get: { actionErrorMessage != nil },
                    set: { if !$0 { actionErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(actionErrorMessage ?? "")
            }
            .sheet(isPresented: $showingAddBookmark) {
                AddBookmarkView(onSave: { url, customTitle, tags in
                    addBookmark(url: url, customTitle: customTitle, tags: tags)
                })
            }
            .sheet(isPresented: $showingFilters) {
                filterSheet
            }
            .onChange(of: quickActionService.currentAction) { _, action in
                handleQuickAction(action)
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
    
    // MARK: - Subviews
    
    private var mainContent: some View {
        Group {
            if isLoading && allBookmarks.isEmpty {
                loadingView
            } else {
                bookmarksList
            }
        }
        // Pinned under the navigation bar, outside the list, so it never
        // competes with the list for scroll tracking.
        .safeAreaInset(edge: .top, spacing: 0) {
            offlineBanner
        }
    }
    
    private var offlineBanner: some View {
        // Both are @Observable, so reading them here keeps the banner current.
        OfflineBanner(
            isConnected: NetworkMonitor.shared.isConnected,
            pendingOperations: SyncQueueManager.shared.pendingOperationsCount,
            onTapSync: {
                Task {
                    await SyncQueueManager.shared.processPendingOperations()
                }
            }
        )
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
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: {
                HapticManager.shared.selection()
                showingFilters.toggle()
            }) {
                Image(systemName: "line.3.horizontal.decrease")
                    .foregroundStyle(hasActiveFilters ? Color.accentColor : .primary)
            }
        }
        
        ViewModeToolbarItem(selection: $viewMode)
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
    
    private func handleQuickAction(_ action: QuickAction?) {
        if action == .newBookmark {
            showingAddBookmark = true
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
        let unreadCount = baseFiltered.filter { $0.status == .unread }.count
        let brokenCount = baseFiltered.filter { $0.isLinkBroken }.count
        
        var items: [FilterPillsBar.FilterItem] = [
            .init(id: "all", title: "All", count: totalCount),
            .init(id: "favorites", title: "Favorites", count: favoriteCount),
            .init(id: "unread", title: "Unread", count: unreadCount),
        ]
        
        // Only offer the Broken filter when there's something to show.
        if brokenCount > 0 || selectedFilter == "broken" {
            items.append(
                FilterPillsBar.FilterItem(id: "broken", title: "Broken", count: brokenCount, tint: Theme.danger)
            )
        }
        
        return items
    }
    
    @ViewBuilder
    private var listHeader: some View {
        if !allBookmarks.isEmpty {
            let broken = allBookmarks.filter(\.isLinkBroken).count
            VStack(spacing: 8) {
                ListSummary(
                    text: "\(allBookmarks.count) saved",
                    highlight: broken > 0 ? "\(broken) broken link\(broken == 1 ? "" : "s")" : nil
                )
                filterPillsBar
            }
        }
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
    
    @ViewBuilder
    private var emptyStateView: some View {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            ContentUnavailableView.search(text: trimmedQuery)
        } else if hasActiveFilters {
            ContentUnavailableView {
                Label("No Matching Bookmarks", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("No bookmarks match your filters.")
            } actions: {
                Button("Clear Filters", action: clearAllFilters)
            }
        } else {
            ContentUnavailableView {
                Label("No Bookmarks Yet", systemImage: "bookmark")
            } description: {
                Text(errorMessage ?? "Your saved content will appear here.")
            } actions: {
                Button("Add Bookmark") { showingAddBookmark = true }
            }
        }
    }
    
    /// One list for both layouts, always mounted (even when empty) so pull to
    /// refresh, the large title and search keep tracking the same scroll view.
    /// Both layouts stay mounted when empty so pull to refresh, the large
    /// title and search keep tracking the same scroll view.
    @ViewBuilder
    private var bookmarksList: some View {
        if viewMode == .grid {
            galleryView
        } else {
            listView
        }
    }
    
    private var galleryView: some View {
        ScrollView {
            listHeader
            
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160), spacing: 12)],
                spacing: 12
            ) {
                ForEach(bookmarks, id: \.id) { bookmark in
                    BookmarkGalleryCard(
                        bookmark: bookmark,
                        onDelete: confirmDeleteBookmark,
                        onUpdate: updateBookmark,
                        onToggleFavorite: toggleFavorite
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
        }
        // The navigation container background keeps the search field drawn correctly.
        .containerBackground(Theme.background, for: .navigation)
        .contentMargins(.bottom, 12, for: .scrollContent)
        .overlay {
            if bookmarks.isEmpty && !isLoading {
                emptyStateView
            }
        }
        .refreshable {
            await refreshBookmarks()
        }
    }
    
    private var listView: some View {
        List {
            listHeader
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            
            if isSortedByDateAdded {
                ForEach(groupedByDateSection(bookmarks, date: \.timeAdded), id: \.section) { group in
                    Section {
                        ForEach(group.items, id: \.id, content: listRow)
                    } header: {
                        Text(group.section.rawValue)
                            .font(.headline)
                            // A concrete color: `.primary` resolves to secondary in headers.
                            .foregroundStyle(Color.primary)
                            .textCase(nil)
                    }
                }
            } else {
                ForEach(bookmarks, id: \.id, content: listRow)
            }
        }
        .listStyle(.plain)
        .overlay {
            if bookmarks.isEmpty && !isLoading {
                emptyStateView
            }
        }
        .refreshable {
            await refreshBookmarks()
        }
    }
    
    private var isSortedByDateAdded: Bool {
        sortOption == .dateAddedDesc || sortOption == .dateAddedAsc
    }
    
    private func listRow(_ bookmark: BookmarkItem) -> some View {
        BookmarkListRow(
            bookmark: bookmark,
            onDelete: confirmDeleteBookmark,
            onUpdate: updateBookmark,
            onToggleFavorite: toggleFavorite
        )
        .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 16))
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
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                confirmDeleteBookmark(bookmark)
            } label: {
                Label("Delete", systemImage: "trash.fill")
            }
            .tint(.red)
            
            if bookmark.status != .archived {
                Button {
                    archiveBookmark(bookmark)
                } label: {
                    Label("Archive", systemImage: "archivebox.fill")
                }
                .tint(.gray)
            }
        }
    }
    
    private func refreshBookmarksIfNeeded() {
        guard authService.currentUser != nil else { return }
        
        // Check if we should refresh (first load or if it's been more than 30 seconds since last refresh)
        let timeSinceLastRefresh = Date().timeIntervalSince(lastRefreshTime)
        let shouldRefresh = allBookmarks.isEmpty || timeSinceLastRefresh > 30
        
        if shouldRefresh {
            // Use loadBookmarks for initial load, refreshBookmarks for subsequent refreshes
            if allBookmarks.isEmpty {
                loadBookmarks()
            } else {
                Task {
                    await refreshBookmarks()
                }
            }
        }
    }
    
    private func loadBookmarks() {
        Task {
            await reloadBookmarks(showInitialLoader: true)
        }
    }
    
    private func refreshBookmarks() async {
        await reloadBookmarks(showInitialLoader: false)
    }

    @MainActor
    private func reloadBookmarks(showInitialLoader: Bool) async {
        await refreshCoordinator.run {
            guard let user = authService.currentUser else { return }

            let isInitialLoad = showInitialLoader && allBookmarks.isEmpty
            if isInitialLoad { isLoading = true }
            errorMessage = nil
            defer { isLoading = false }

            do {
                APIService.shared.configure(authService: authService)
                allBookmarks = try await APIService.shared.fetchBookmarks(userId: user.id)
                extractAvailableTags()
                applyFilterPills()
                lastRefreshTime = Date()
            } catch {
                // Only show error if we have no cached bookmarks
                if allBookmarks.isEmpty {
                    errorMessage = "Failed to refresh bookmarks: \(error.localizedDescription)"
                }
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
                bookmarks.removeAll { $0.id == bookmark.id }
                allBookmarks.removeAll { $0.id == bookmark.id }
                bookmarkToDelete = nil
                HapticManager.shared.success()
            } catch {
                bookmarkToDelete = nil
                actionErrorMessage = "Couldn't delete \"\(bookmark.title)\". \(error.localizedDescription)"
                HapticManager.shared.error()
            }
        }
    }
    
    /// Applies `changes` optimistically and rolls them back if the server
    /// rejects the update.
    private func updateBookmark(_ bookmark: BookmarkItem, with changes: BookmarkChanges) {
        guard !changes.isEmpty else { return }
        
        let previous = bookmark.apply(changes)
        applyFilterPills()
        
        Task {
            do {
                let saved = try await APIService.shared.updateBookmark(id: bookmark.id, changes: changes)
                saved.ogImageURL = saved.ogImageURL ?? bookmark.ogImageURL
                saved.metadata = saved.metadata ?? bookmark.metadata
                if let index = allBookmarks.firstIndex(where: { $0.id == bookmark.id }) {
                    allBookmarks[index] = saved
                }
                applyFilterPills()
            } catch {
                bookmark.apply(previous)
                applyFilterPills()
                actionErrorMessage = "Couldn't update \"\(bookmark.title)\". \(error.localizedDescription)"
                HapticManager.shared.error()
            }
        }
    }
    
    private func setStatus(_ status: BookmarkItem.ItemStatus, for bookmark: BookmarkItem) {
        HapticManager.shared.selection()
        updateBookmark(bookmark, with: BookmarkChanges(status: status))
    }
    
    private func markAsRead(_ bookmark: BookmarkItem) {
        setStatus(.read, for: bookmark)
    }
    
    private func archiveBookmark(_ bookmark: BookmarkItem) {
        setStatus(.archived, for: bookmark)
    }
    
    private func toggleFavorite(_ bookmark: BookmarkItem) {
        HapticManager.shared.selection()
        updateBookmark(bookmark, with: BookmarkChanges(isFavorite: !bookmark.isFavorite))
    }
    
    private func addBookmark(url: String, customTitle: String? = nil, tags: [String] = []) {
        guard let user = authService.currentUser else {
            actionErrorMessage = "Please sign in to add bookmarks"
            return
        }
        
        Task {
            // Try to fetch metadata with retries
            let metadata = await fetchMetadataWithRetry(url: url, retries: 2)
            
            // Extract domain info from URL
            let urlComponents = URL(string: url)
            let domain = urlComponents?.host ?? ""
            let faviconURL = urlComponents.map { "https://www.google.com/s2/favicons?domain=\($0.host ?? "")&sz=64" }
            
            let trimmedCustomTitle = customTitle?.trimmingCharacters(in: .whitespacesAndNewlines)

            // Use custom title if provided, otherwise fallback to metadata and domain
            let pageTitle: String
            if let customTitle = trimmedCustomTitle, !customTitle.isEmpty {
                pageTitle = customTitle
            } else if let extractedTitle = metadata?.title, !extractedTitle.isEmpty {
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
                    HapticManager.shared.success()
                }
            } catch {
                await MainActor.run {
                    self.actionErrorMessage = "Couldn't add the bookmark. \(error.localizedDescription)"
                    HapticManager.shared.error()
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
        
        // Drop the Broken filter once the last broken bookmark is gone.
        if selectedFilter == "broken" && !allBookmarks.contains(where: \.isLinkBroken) {
            selectedFilter = "all"
        }
        
        // Apply filter pill on top of everything else
        switch selectedFilter {
        case "favorites":
            filtered = filtered.filter { $0.isFavorite }
        case "unread":
            filtered = filtered.filter { $0.status == .unread }
        case "broken":
            filtered = filtered.filter { $0.isLinkBroken }
        default:
            break
        }
        
        // Apply sorting
        filtered = sortBookmarks(filtered, by: sortOption)
        
        bookmarks = filtered
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
        HapticManager.shared.selection()
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
        NavigationStack {
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
                            HapticManager.shared.selection()
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
                                HapticManager.shared.selection()
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
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear All") {
                        onClearAll()
                    }
                    .disabled(selectedStatus == nil && selectedTags.isEmpty && sortOption == .dateAddedDesc)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
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
    
    @State private var tagsText = ""
    @State private var tags: [String]
    @Environment(\.dismiss) private var dismiss
    
    init(bookmark: BookmarkItem, onSave: @escaping ([String]) -> Void) {
        self.bookmark = bookmark
        self.onSave = onSave
        self._tags = State(initialValue: bookmark.tags)
    }
    
    var body: some View {
        NavigationStack {
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
                        TextField("Enter tags (comma separated)", text: $tagsText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onSubmit {
                                addTags()
                            }
                        
                        Button("Add", action: addTags)
                            .disabled(tagsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
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
    
    private func addTags() {
        let newTags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && !tags.contains($0) }
        
        tags.append(contentsOf: newTags)
        tagsText = ""
    }
    
    private func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }
}
