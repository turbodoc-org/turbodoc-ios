import SwiftUI

struct NotesView: View {
    @EnvironmentObject var authService: AuthenticationService
    @EnvironmentObject var quickActionService: QuickActionService
    @State private var notes: [NoteItem] = []
    @State private var allNotes: [NoteItem] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var showingDeleteConfirmation = false
    @State private var noteToDelete: NoteItem?
    @State private var showingAddNote = false
    @State private var showingVoiceRecording = false
    @State private var showingPhotoOCR = false
    @State private var noteToEdit: NoteItem?
    @State private var isFABExpanded = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastRefreshTime = Date.distantPast
    @State private var refreshCoordinator = RefreshCoordinator()
    @AppStorage("notesViewMode") private var viewMode: ViewMode = .grid
    @AppStorage("notesFilterSelection") private var selectedFilter: String = "all"
    @AppStorage("notesSortOrder") private var sortOrder: String = "date_newest"
    
    private var filterItems: [FilterPillsBar.FilterItem] {
        let favoriteCount = allNotes.filter { $0.isFavorite }.count
        
        return [
            .init(id: "all", title: "All", count: allNotes.count),
            .init(id: "favorites", title: "Favorites", count: favoriteCount),
        ]
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading && allNotes.isEmpty {
                    loadingView
                } else if viewMode == .grid {
                    gridView
                } else {
                    listView
                }
            }
            // Pinned under the navigation bar, outside the scroll view, so it
            // never competes with it for scroll tracking.
            .safeAreaInset(edge: .top, spacing: 0) {
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
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Sort", selection: $sortOrder) {
                            Text("Newest First").tag("date_newest")
                            Text("Oldest First").tag("date_oldest")
                            Text("Recently Modified").tag("modified")
                            Text("A-Z").tag("alpha_asc")
                            Text("Z-A").tag("alpha_desc")
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                            .imageScale(.large)
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        HapticManager.shared.selection()
                        viewMode = viewMode == .grid ? .list : .grid
                    }) {
                        Image(systemName: viewMode == .grid ? "list.bullet" : "square.grid.2x2")
                            .imageScale(.large)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search notes...")
            .onChange(of: searchText) {
                performSearch(query: searchText)
            }
            .onChange(of: sortOrder) {
                applyFilter()
            }
            .onAppear {
                // Migrate any previously-persisted "recent" selection (now removed)
                // back to "all" so the user doesn't end up on a non-existent filter.
                if selectedFilter == "recent" { selectedFilter = "all" }
                refreshNotesIfNeeded()
            }
            .onChange(of: scenePhase) {
                if scenePhase == .active && authService.authenticationStatus == .authenticated {
                    refreshNotesIfNeeded()
                }
            }
            .onChange(of: authService.authenticationStatus) {
                if authService.authenticationStatus == .authenticated {
                    loadNotes()
                }
            }
            .onChange(of: authService.currentUser) {
                if authService.currentUser != nil {
                    loadNotes()
                }
            }
            .alert("Delete Note", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let note = noteToDelete {
                        deleteNote(note)
                    }
                }
            } message: {
                if let note = noteToDelete {
                    Text(
                        "Are you sure you want to delete \"\(note.displayTitle)\"? This action cannot be undone."
                    )
                }
            }
            .sheet(isPresented: $showingAddNote) {
                AddNoteView(
                    onSave: { note in
                        saveNoteUpdate(note)
                        showingAddNote = false
                    }
                )
            }
            .sheet(isPresented: $showingVoiceRecording) {
                VoiceRecordingView(onSave: { transcribedText in
                    guard let userId = authService.currentUser?.id else { return }
                    let note = NoteItem(
                        title: "🎤 Voice Note",
                        content: transcribedText,
                        tags: [],
                        userId: userId
                    )
                    saveNoteUpdate(note)
                })
            }
            .sheet(isPresented: $showingPhotoOCR) {
                PhotoOCRView(onSave: { extractedText, _ in
                    guard let userId = authService.currentUser?.id else { return }
                    let note = NoteItem(
                        title: "📷 Photo Note",
                        content: extractedText,
                        tags: [],
                        userId: userId
                    )
                    saveNoteUpdate(note)
                })
            }
            .onChange(of: quickActionService.currentAction) { _, action in
                if action == .newNote {
                    showingAddNote = true
                }
            }
            .navigationDestination(item: $noteToEdit) { noteToEdit in
                EditNoteView(
                    note: noteToEdit,
                    onSave: { updatedNote in
                        await saveExistingNoteUpdate(updatedNote)
                    },
                    onRestore: { restoredNote in
                        if let index = notes.firstIndex(where: { $0.id == restoredNote.id }) {
                            notes[index] = restoredNote
                        }
                        if let index = allNotes.firstIndex(where: { $0.id == restoredNote.id }) {
                            allNotes[index] = restoredNote
                        }
                    },
                    onFinish: {
                        self.noteToEdit = nil
                    },
                    onDelete: { noteToDelete in
                        deleteNote(noteToDelete)
                        self.noteToEdit = nil
                    }
                )
            }
            .overlay(alignment: .bottomTrailing) {
                VStack(alignment: .trailing, spacing: 16) {
                    // Expandable menu items
                    if isFABExpanded {
                        VStack(alignment: .trailing, spacing: 12) {
                            // Voice recording button
                            FABMenuItem(
                                icon: "mic.fill",
                                label: "Voice Note",
                                color: .orange
                            ) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    isFABExpanded = false
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    showingVoiceRecording = true
                                }
                            }
                            
                            // Photo OCR button
                            FABMenuItem(
                                icon: "camera.fill",
                                label: "Photo Note",
                                color: .purple
                            ) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    isFABExpanded = false
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    showingPhotoOCR = true
                                }
                            }
                            
                            // Text note button
                            FABMenuItem(
                                icon: "text.alignleft",
                                label: "Text Note",
                                color: .blue
                            ) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    isFABExpanded = false
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    showingAddNote = true
                                }
                            }
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                    
                    // Main FAB button
                    Button(action: {
                        HapticManager.shared.light()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isFABExpanded.toggle()
                        }
                    }) {
                        // Rotating the plus 45° turns it into a close button.
                        Image(systemName: "plus")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .floatingActionButtonBackground(.blue)
                            .rotationEffect(.degrees(isFABExpanded ? 45 : 0))
                    }
                }
                .padding(.trailing, 24)
                .padding(.bottom, 32)
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                .scaleEffect(1.5)
            
            Text("Loading your notes...")
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
        } else if selectedFilter == "favorites" && !allNotes.isEmpty {
            ContentUnavailableView(
                "No Favorite Notes",
                systemImage: "star",
                description: Text("Notes you favorite will appear here.")
            )
        } else {
            ContentUnavailableView {
                Label("No Notes Yet", systemImage: "note.text")
            } description: {
                Text(errorMessage ?? "Your notes will appear here.")
            } actions: {
                Button("New Note") { showingAddNote = true }
            }
        }
    }
    
    @ViewBuilder
    private var filterPills: some View {
        if !allNotes.isEmpty {
            FilterPillsBar(
                filters: filterItems,
                selectedFilter: selectedFilter,
                onSelect: { filterId in
                    selectedFilter = filterId
                    applyFilter()
                }
            )
        }
    }
    
    /// Both layouts stay mounted when empty so pull to refresh, the large title
    /// and search keep tracking the same scroll view.
    private var gridView: some View {
        ScrollView {
            filterPills
            
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: 16)],
                spacing: 16
            ) {
                ForEach(notes, id: \.id) { note in
                    noteCard(note)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        // Keep the last cards clear of the floating add button.
        .contentMargins(.bottom, 100, for: .scrollContent)
        .overlay {
            if notes.isEmpty && !isLoading {
                emptyStateView
            }
        }
        .refreshable {
            await refreshNotes()
        }
    }

    private func noteCard(_ note: NoteItem) -> some View {
        NoteCardView(
            note: note,
            onEdit: { noteToEdit = $0 },
            onDelete: confirmDeleteNote,
            onToggleFavorite: toggleFavorite
        )
    }
    
    private var listView: some View {
        List {
            filterPills
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            
            ForEach(notes, id: \.id) { note in
                NoteListRowView(
                    note: note,
                    onEdit: { noteToEdit in
                        self.noteToEdit = noteToEdit
                    },
                    onDelete: { noteToDelete in
                        confirmDeleteNote(noteToDelete)
                    }
                )
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        toggleFavorite(note)
                    } label: {
                        Label(
                            note.isFavorite ? "Unfavorite" : "Favorite",
                            systemImage: note.isFavorite ? "star.slash.fill" : "star.fill"
                        )
                    }
                    .tint(.yellow)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        confirmDeleteNote(note)
                    } label: {
                        Label("Delete", systemImage: "trash.fill")
                    }
                    .tint(.red)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
        }
        .listStyle(.plain)
        .contentMargins(.bottom, 100, for: .scrollContent)
        .overlay {
            if notes.isEmpty && !isLoading {
                emptyStateView
            }
        }
        .refreshable {
            await refreshNotes()
        }
    }
    
    private func refreshNotesIfNeeded() {
        guard authService.currentUser != nil else { return }
        
        // Check if we should refresh (first load or if it's been more than 30 seconds since last refresh)
        let timeSinceLastRefresh = Date().timeIntervalSince(lastRefreshTime)
        let shouldRefresh = allNotes.isEmpty || timeSinceLastRefresh > 30
        
        if shouldRefresh {
            // Use loadNotes for initial load, refreshNotes for subsequent refreshes
            if allNotes.isEmpty {
                loadNotes()
            } else {
                Task {
                    await refreshNotes()
                }
            }
        }
    }
    
    private func applyFilter() {
        var filtered = allNotes
        
        // Apply selected filter
        switch selectedFilter {
        case "favorites":
            filtered = filtered.filter { $0.isFavorite }
        default:  // "all"
            break
        }
        
        // Apply sorting
        switch sortOrder {
        case "date_oldest":
            filtered.sort { $0.createdAt < $1.createdAt }
        case "alpha_asc":
            filtered.sort {
                ($0.title ?? $0.displayTitle).localizedCaseInsensitiveCompare(
                    $1.title ?? $1.displayTitle) == .orderedAscending
            }
        case "alpha_desc":
            filtered.sort {
                ($0.title ?? $0.displayTitle).localizedCaseInsensitiveCompare(
                    $1.title ?? $1.displayTitle) == .orderedDescending
            }
        case "modified":
            filtered.sort { $0.updatedAt > $1.updatedAt }
        default:  // "date_newest"
            filtered.sort { $0.createdAt > $1.createdAt }
        }
        
        notes = filtered
    }
    
    private func loadNotes() {
        Task {
            await reloadNotes(showInitialLoader: true)
        }
    }
    
    private func refreshNotes() async {
        await reloadNotes(showInitialLoader: false)
    }

    @MainActor
    private func reloadNotes(showInitialLoader: Bool) async {
        await refreshCoordinator.run {
            guard let user = authService.currentUser else { return }

            let isInitialLoad = showInitialLoader && allNotes.isEmpty
            if isInitialLoad { isLoading = true }
            errorMessage = nil
            defer { isLoading = false }

            do {
                APIService.shared.configure(authService: authService)
                let fetchedNotes = try await APIService.shared.fetchNotes(userId: user.id)

                // Merge fetched notes with local pending changes
                allNotes = mergeFetchedNotesWithLocalEdits(fetchedNotes)
                applyFilter()
                lastRefreshTime = Date()
            } catch {
                // Only show error if we have no cached notes
                if allNotes.isEmpty {
                    errorMessage = "Failed to refresh notes: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func confirmDeleteNote(_ note: NoteItem) {
        noteToDelete = note
        showingDeleteConfirmation = true
    }
    
    private func deleteNote(_ note: NoteItem) {
        Task {
            do {
                try await APIService.shared.deleteNote(id: note.id)
                await MainActor.run {
                    self.notes.removeAll { $0.id == note.id }
                    self.allNotes.removeAll { $0.id == note.id }
                    self.noteToDelete = nil
                    HapticManager.shared.success()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to delete note: \(error.localizedDescription)"
                    self.noteToDelete = nil
                    HapticManager.shared.error()
                }
            }
        }
    }
    
    private func toggleFavorite(_ note: NoteItem) {
        HapticManager.shared.selection()
        
        // Optimistic UI update
        note.isFavorite.toggle()
        
        // Update in local arrays
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
        }
        if let index = allNotes.firstIndex(where: { $0.id == note.id }) {
            allNotes[index] = note
        }
        
        // Save to server in background
        Task {
            do {
                let updatedNote = try await APIService.shared.updateNote(note)
                
                await MainActor.run {
                    // Update with server response
                    if let index = self.notes.firstIndex(where: { $0.id == note.id }) {
                        self.notes[index] = updatedNote
                    }
                    if let index = self.allNotes.firstIndex(where: { $0.id == note.id }) {
                        self.allNotes[index] = updatedNote
                    }
                }
            } catch {
                await MainActor.run {
                    // Revert optimistic update on error
                    note.isFavorite.toggle()
                    if let index = self.notes.firstIndex(where: { $0.id == note.id }) {
                        self.notes[index] = note
                    }
                    if let index = self.allNotes.firstIndex(where: { $0.id == note.id }) {
                        self.allNotes[index] = note
                    }
                    self.errorMessage = "Failed to update favorite status"
                    HapticManager.shared.error()
                }
            }
        }
    }
    
    private func mergeFetchedNotesWithLocalEdits(_ fetchedNotes: [NoteItem]) -> [NoteItem] {
        let pendingPayloads = SyncQueueManager.shared.getPendingNotePayloads()
        let pendingNoteIds = Set(pendingPayloads.keys)
        
        // If no pending changes, return fetched notes as-is
        guard !pendingNoteIds.isEmpty else {
            return fetchedNotes
        }
        
        var mergedNotes: [NoteItem] = []
        
        // For each fetched note, check if it has pending changes
        for fetchedNote in fetchedNotes {
            if pendingNoteIds.contains(fetchedNote.id) {
                // This note has pending changes - use the local version from allNotes if available
                if let localNote = allNotes.first(where: { $0.id == fetchedNote.id }) {
                    mergedNotes.append(localNote)
                } else if let payload = pendingPayloads[fetchedNote.id] {
                    // Reconstruct from payload if not in allNotes
                    let note = NoteItem(
                        title: payload.title ?? "",
                        content: payload.content ?? "",
                        tags: payload.tags ?? [],
                        userId: authService.currentUser?.id ?? ""
                    )
                    note.id = fetchedNote.id
                    note.isFavorite = payload.isFavorite ?? false
                    note.version = payload.version ?? 1
                    note.headRevisionId = payload.headRevisionId
                    mergedNotes.append(note)
                } else {
                    mergedNotes.append(fetchedNote)
                }
            } else {
                // No pending changes - use fetched version
                mergedNotes.append(fetchedNote)
            }
        }
        
        // Add any new notes that are pending creation (not in fetched notes)
        for noteId in pendingNoteIds {
            if !mergedNotes.contains(where: { $0.id == noteId }) {
                // This is a new note being created
                if let localNote = allNotes.first(where: { $0.id == noteId }) {
                    mergedNotes.insert(localNote, at: 0)
                }
            }
        }
        
        return mergedNotes
    }
    
    private func saveNoteUpdate(_ note: NoteItem) {
        let isExistingNote = allNotes.contains(where: { $0.id == note.id })
        let operationType = isExistingNote ? "update" : "create"
        
        // Update UI immediately (optimistic update)
        if !isExistingNote {
            self.allNotes.insert(note, at: 0)
            self.applyFilter()
        } else {
            if let index = self.notes.firstIndex(where: { $0.id == note.id }) {
                self.notes[index] = note
            }
            if let index = self.allNotes.firstIndex(where: { $0.id == note.id }) {
                self.allNotes[index] = note
            }
        }
        
        // Update cache will happen on next successful API fetch
        // For now, the UI is already updated optimistically above
        
        // Save to server in background
        Task {
            if NetworkMonitor.shared.isConnected {
                // Online - try to save immediately
                do {
                    let savedNote: NoteItem
                    
                    if !isExistingNote {
                        savedNote = try await APIService.shared.saveNote(note)
                    } else {
                        savedNote = try await APIService.shared.updateNote(note)
                    }
                    
                    await MainActor.run {
                        // Update with server response
                        if let index = self.notes.firstIndex(where: { $0.id == note.id }) {
                            self.notes[index] = savedNote
                        }
                        if let index = self.allNotes.firstIndex(where: { $0.id == note.id }) {
                            self.allNotes[index] = savedNote
                        }
                    }
                } catch {
                    // Failed while online - queue for retry
                    SyncQueueManager.shared.queueNoteOperation(type: operationType, note: note)
                }
            } else {
                // Offline - queue operation
                SyncQueueManager.shared.queueNoteOperation(type: operationType, note: note)
            }
        }
    }

    @MainActor
    private func saveExistingNoteUpdate(_ note: NoteItem) async -> NoteSaveOutcome {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
        }
        if let index = allNotes.firstIndex(where: { $0.id == note.id }) {
            allNotes[index] = note
        }

        guard NetworkMonitor.shared.isConnected else {
            SyncQueueManager.shared.queueNoteOperation(type: "update", note: note)
            AppLogger.notes.notice(
                "Queued offline note update for \(note.id.uuidString, privacy: .public)"
            )
            return .queued
        }

        do {
            let savedNote = try await APIService.shared.updateNote(note)
            if let index = notes.firstIndex(where: { $0.id == note.id }) {
                notes[index] = savedNote
            }
            if let index = allNotes.firstIndex(where: { $0.id == note.id }) {
                allNotes[index] = savedNote
            }
            AppLogger.notes.info(
                "Saved note \(note.id.uuidString, privacy: .public)"
            )
            return .saved(savedNote)
        } catch {
            SyncQueueManager.shared.queueNoteOperation(type: "update", note: note)
            AppLogger.notes.error(
                "Note update failed and was queued: \(error.localizedDescription, privacy: .public)"
            )
            return .queued
        }
    }
    
    private func performSearch(query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If search is empty, show all notes
        if trimmedQuery.isEmpty {
            notes = allNotes
            return
        }
        
        // For local search, filter the existing notes
        if trimmedQuery.count < 3 {
            // Local search for short queries
            notes = allNotes.filter { note in
                note.displayTitle.localizedCaseInsensitiveContains(trimmedQuery)
                || note.content.localizedCaseInsensitiveContains(trimmedQuery)
                || note.tags.contains { tag in
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
            try? await Task.sleep(nanoseconds: 300_000_000)  // 300ms
            
            // Check if search text is still the same (user hasn't typed more)
            guard searchText.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedQuery else {
                return
            }
            
            do {
                let searchResults = try await APIService.shared.searchNotes(
                    query: trimmedQuery, userId: user.id)
                
                await MainActor.run {
                    // Only update if this is still the current search
                    if self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                        == trimmedQuery
                    {
                        self.notes = searchResults
                    }
                    self.isSearching = false
                }
            } catch {
                await MainActor.run {
                    // Fall back to local search on API error
                    self.notes = self.allNotes.filter { note in
                        note.displayTitle.localizedCaseInsensitiveContains(trimmedQuery)
                        || note.content.localizedCaseInsensitiveContains(trimmedQuery)
                        || note.tags.contains { tag in
                            tag.localizedCaseInsensitiveContains(trimmedQuery)
                        }
                    }
                    self.isSearching = false
                }
            }
        }
    }
}

// MARK: - FAB Menu Item Component

struct FABMenuItem: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(.secondarySystemBackground))
                        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                )
            
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .floatingActionButtonBackground(color)
            }
        }
    }
}
