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
                            ForEach(Self.sortOptions, id: \.value) { option in
                                Text(option.title).tag(option.value)
                            }
                        }
                    } label: {
                        Label(sortTitle, systemImage: "arrow.up.arrow.down")
                            .labelStyle(.titleAndIcon)
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    // Text notes start from the + beside the tab bar.
                    Menu {
                        Button {
                            showingVoiceRecording = true
                        } label: {
                            Label("Voice Note", systemImage: "mic")
                        }
                        Button {
                            showingPhotoOCR = true
                        } label: {
                            Label("Photo Note", systemImage: "camera")
                        }
                    } label: {
                        Label("Capture", systemImage: "waveform.and.mic")
                    }
                }

                
                ViewModeToolbarItem(selection: $viewMode)
            }
            .searchable(text: $searchText, prompt: "Search notes...")
            .onChange(of: searchText) {
                performSearch(query: searchText)
            }
            .onChange(of: sortOrder) {
                applyFilter()
            }
            .onChange(of: viewMode) {
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
                        createNote(note)
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
                    createNote(note)
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
                    createNote(note)
                })
            }
            .onReceive(NotificationCenter.default.publisher(for: .noteQueueDidSync)) { notification in
                guard let event = notification.object as? NoteQueueEvent else { return }
                applyQueueEvent(event)
            }
            .onChange(of: quickActionService.currentAction) { _, action in
                switch action {
                case .newNote: showingAddNote = true
                case .newVoiceNote: showingVoiceRecording = true
                case .newPhotoNote: showingPhotoOCR = true
                default: break
                }
            }
            .navigationDestination(item: $noteToEdit) { noteToEdit in
                EditNoteView(
                    note: noteToEdit,
                    onSave: { updatedNote, baseRevisionId in
                        await saveExistingNoteUpdate(updatedNote, baseRevisionId: baseRevisionId)
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
                    },
                    onKeepCopy: { copy in
                        createNote(copy)
                    }
                )
                .hidesTabBar()
            }
        }
    }
    
    private static let sortOptions: [(value: String, title: String)] = [
        ("date_newest", "Newest First"),
        ("date_oldest", "Oldest First"),
        ("modified", "Recently Edited"),
        ("alpha_asc", "Title A–Z"),
        ("alpha_desc", "Title Z–A"),
    ]
    
    private var sortTitle: String {
        switch sortOrder {
        case "date_oldest": return "Oldest"
        case "modified": return "Edited"
        case "alpha_asc", "alpha_desc": return "Title"
        default: return "Newest"
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
            ListSummary(text: "\(allNotes.count) note\(allNotes.count == 1 ? "" : "s")")
            
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
                columns: [GridItem(.adaptive(minimum: 160), spacing: 12)],
                spacing: 12
            ) {
                ForEach(notes, id: \.id) { note in
                    noteCard(note)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
        }
        // The navigation container background keeps the search field drawn correctly.
        .containerBackground(Theme.background, for: .navigation)
        .contentMargins(.bottom, 12, for: .scrollContent)
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
    
    /// Apple Notes style: favorites first, then everything else, each in an
    /// inset grouped section.
    private var listView: some View {
        let favorites = notes.filter(\.isFavorite)
        let others = notes.filter { !$0.isFavorite }
        
        return List {
            if !favorites.isEmpty {
                Section {
                    ForEach(favorites, id: \.id, content: listRow)
                } header: {
                    VStack(alignment: .leading, spacing: 18) {
                        noteCountHeader
                        Label("Favorites", systemImage: "star.fill")
                            .labelStyle(SectionHeaderLabelStyle())
                    }
                }
            }
            
            if !others.isEmpty {
                Section {
                    ForEach(others, id: \.id, content: listRow)
                } header: {
                    VStack(alignment: .leading, spacing: 18) {
                        if favorites.isEmpty {
                            noteCountHeader
                        }
                        Text(favorites.isEmpty ? "Notes" : "Recent")
                            .font(.title3.bold())
                            .foregroundStyle(Color.primary)
                            .textCase(nil)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if notes.isEmpty && !isLoading {
                emptyStateView
            }
        }
        .refreshable {
            await refreshNotes()
        }
    }
    
    private var noteCountHeader: some View {
        Text("\(allNotes.count) note\(allNotes.count == 1 ? "" : "s")")
            .font(.subheadline)
            .foregroundStyle(Color.secondary)
            .textCase(nil)
    }
    
    private func listRow(_ note: NoteItem) -> some View {
        NoteListRowView(
            note: note,
            onEdit: { noteToEdit = $0 },
            onDelete: confirmDeleteNote,
            onToggleFavorite: toggleFavorite
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
        
        // The list view shows favorites as their own section instead.
        switch viewMode == .grid ? selectedFilter : "all" {
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
                    SyncQueueManager.shared.discardPendingNoteOperations(for: note.id)
                    removeNoteLocally(note.id)
                    self.noteToDelete = nil
                    HapticManager.shared.success()
                }
            } catch APIError.networkError {
                // Offline: delete it when the connection is back.
                await MainActor.run {
                    SyncQueueManager.shared.queueNoteOperation(
                        type: "delete",
                        note: note,
                        baseRevisionId: nil
                    )
                    removeNoteLocally(note.id)
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
    
    private func removeNoteLocally(_ id: UUID) {
        notes.removeAll { $0.id == id }
        allNotes.removeAll { $0.id == id }
    }
    
    private func replaceNoteLocally(_ note: NoteItem) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
        }
        if let index = allNotes.firstIndex(where: { $0.id == note.id }) {
            allNotes[index] = note
        }
    }
    
    /// The offline queue changed a note on the server: show the result,
    /// unless newer local edits are still waiting.
    private func applyQueueEvent(_ event: NoteQueueEvent) {
        switch event {
        case .saved(let saved):
            guard !SyncQueueManager.shared.hasPendingNoteOperation(for: saved.id) else { return }
            if allNotes.contains(where: { $0.id == saved.id }) {
                replaceNoteLocally(saved)
            } else {
                allNotes.insert(saved, at: 0)
            }
            applyFilter()
        case .removed(let id):
            removeNoteLocally(id)
        case .recovered(let originalId, let copy):
            removeNoteLocally(originalId)
            if !allNotes.contains(where: { $0.id == copy.id }) {
                allNotes.insert(copy, at: 0)
            }
            applyFilter()
        }
    }
    
    private func toggleFavorite(_ note: NoteItem) {
        HapticManager.shared.selection()
        
        // Optimistic UI update
        note.isFavorite.toggle()
        let isFavorite = note.isFavorite
        replaceNoteLocally(note)
        
        // Send only the flag. This list copy may be stale, so it must never
        // resend the note's title or content.
        Task {
            do {
                let result = try await APIService.shared.saveDocument(
                    id: note.id,
                    title: nil,
                    content: nil,
                    isFavorite: isFavorite,
                    baseRevisionId: note.headRevisionId
                )
                
                await MainActor.run {
                    if SyncQueueManager.shared.hasPendingNoteOperation(for: note.id) {
                        // Keep the local, not yet synced text on screen.
                        note.isFavorite = result.note.isFavorite
                        replaceNoteLocally(note)
                    } else {
                        replaceNoteLocally(result.note)
                    }
                    applyFilter()
                }
            } catch {
                await MainActor.run {
                    // Revert optimistic update on error
                    note.isFavorite = !isFavorite
                    replaceNoteLocally(note)
                    self.errorMessage = "Failed to update favorite status"
                    HapticManager.shared.error()
                }
            }
        }
    }
    
    private func mergeFetchedNotesWithLocalEdits(_ fetchedNotes: [NoteItem]) -> [NoteItem] {
        let pendingPayloads = SyncQueueManager.shared.getPendingNotePayloads()
        let pendingNoteIds = Set(pendingPayloads.keys)
        let pendingDeletions = SyncQueueManager.shared.pendingNoteDeletions()
        let fetchedNotes = fetchedNotes.filter { !pendingDeletions.contains($0.id) }
        
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
    
    /// Creates a note under its local ID, so the server keeps it and a
    /// replay of a queued create cannot duplicate it.
    private func createNote(_ note: NoteItem) {
        // Update UI immediately (optimistic update)
        allNotes.insert(note, at: 0)
        applyFilter()
        
        Task {
            guard NetworkMonitor.shared.isConnected else {
                SyncQueueManager.shared.queueNoteOperation(type: "create", note: note, baseRevisionId: nil)
                return
            }
            do {
                let created = try await APIService.shared.createDocument(note)
                await MainActor.run {
                    replaceNoteLocally(created)
                }
            } catch {
                // Never lose a new note: the queue retries the create (it is
                // idempotent) and keeps it if the server refuses.
                AppLogger.notes.error(
                    "Note create failed and was queued: \(error.localizedDescription, privacy: .public)"
                )
                SyncQueueManager.shared.queueNoteOperation(type: "create", note: note, baseRevisionId: nil)
            }
        }
    }

    /// Saves an edit from the editor on top of `baseRevisionId`, the
    /// revision its edits started from.
    @MainActor
    private func saveExistingNoteUpdate(_ note: NoteItem, baseRevisionId: String?) async -> NoteSaveOutcome {
        replaceNoteLocally(note)

        // Created offline and not on the server yet: send the create, with
        // these edits folded in.
        if SyncQueueManager.shared.hasPendingCreate(for: note.id) {
            SyncQueueManager.shared.queueNoteOperation(type: "update", note: note, baseRevisionId: baseRevisionId)
            guard NetworkMonitor.shared.isConnected else { return .queued }
            do {
                guard let result = try await SyncQueueManager.shared.pushPendingCreate(for: note.id) else {
                    return .queued
                }
                replaceNoteLocally(result.note)
                return .saved(result)
            } catch APIError.networkError {
                return .queued
            } catch {
                AppLogger.notes.error(
                    "Queued note create failed: \(error.localizedDescription, privacy: .public)"
                )
                return .failed
            }
        }

        guard NetworkMonitor.shared.isConnected else {
            SyncQueueManager.shared.queueNoteOperation(type: "update", note: note, baseRevisionId: baseRevisionId)
            AppLogger.notes.notice(
                "Queued offline note update for \(note.id.uuidString, privacy: .public)"
            )
            return .queued
        }

        do {
            let result = try await APIService.shared.saveDocument(
                id: note.id,
                title: note.title ?? "",
                content: note.content,
                isFavorite: nil,
                baseRevisionId: baseRevisionId
            )
            replaceNoteLocally(result.note)
            AppLogger.notes.info(
                "Saved note \(note.id.uuidString, privacy: .public) (merged: \(result.merged, privacy: .public), conflicts: \(result.conflicts, privacy: .public))"
            )
            return .saved(result)
        } catch APIError.networkError {
            SyncQueueManager.shared.queueNoteOperation(type: "update", note: note, baseRevisionId: baseRevisionId)
            AppLogger.notes.notice(
                "Note update could not reach the server and was queued"
            )
            return .queued
        } catch let error as APIError where error.statusCode == 404 {
            AppLogger.notes.notice(
                "Note \(note.id.uuidString, privacy: .public) was deleted on another device"
            )
            SyncQueueManager.shared.discardPendingNoteOperations(for: note.id)
            removeNoteLocally(note.id)
            return .deleted
        } catch {
            AppLogger.notes.error(
                "Note update failed: \(error.localizedDescription, privacy: .public)"
            )
            return .failed
        }
    }
    
    private func performSearch(query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If search is empty, go back to the filtered, sorted notes
        if trimmedQuery.isEmpty {
            applyFilter()
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

/// Large, bold section title with a tinted icon (e.g. the Favorites star).
private struct SectionHeaderLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 7) {
            configuration.icon
                .font(.headline)
                .foregroundStyle(Theme.favorite)
            configuration.title
                .font(.title3.bold())
                .foregroundStyle(Color.primary)
        }
        .textCase(nil)
    }
}
