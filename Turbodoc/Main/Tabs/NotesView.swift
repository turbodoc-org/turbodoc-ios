import SwiftUI

struct NotesView: View {
    @EnvironmentObject var authService: AuthenticationService
    @EnvironmentObject var quickActionService: QuickActionService
    @State private var notes: [NoteItem] = []
    @State private var allNotes: [NoteItem] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var isRefreshing = false
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var showingDeleteConfirmation = false
    @State private var noteToDelete: NoteItem?
    @State private var showingAddNote = false
    @State private var noteToEdit: NoteItem?
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastRefreshTime = Date()
    @AppStorage("notesViewMode") private var viewMode: ViewMode = .grid
    @AppStorage("notesFilterSelection") private var selectedFilter: String = "all"
    @AppStorage("notesSortOrder") private var sortOrder: String = "date_newest"
    
    // Grid layout - 2 columns with improved spacing
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    private var filterItems: [FilterPillsBar.FilterItem] {
        let favoriteCount = allNotes.filter { $0.isFavorite }.count
        let recentCount = allNotes.filter {
            Calendar.current.isDate($0.createdAt, equalTo: Date(), toGranularity: .weekOfYear)
        }.count
        
        return [
            .init(id: "all", title: "All", count: allNotes.count),
            .init(id: "favorites", title: "Favorites", count: favoriteCount),
            .init(id: "recent", title: "Recent", count: recentCount)
        ]
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoading {
                    loadingView
                } else {
                    // Always show filter pills when we have notes (even if filtered result is empty)
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
                    
                    if notes.isEmpty {
                        emptyStateView
                    } else {
                        notesGrid
                    }
                }
            }
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
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
            .searchable(text: $searchText, prompt: "Search notes...")
            .onChange(of: searchText) {
                performSearch(query: searchText)
            }
            .onChange(of: sortOrder) {
                applyFilter()
            }
            .onAppear {
                refreshNotesIfNeeded()
            }
            .onChange(of: scenePhase) {
                if scenePhase == .active && authService.isAuthenticated {
                    // Always refresh when app becomes active to get latest data
                    Task {
                        await refreshNotes()
                    }
                }
            }
            .onChange(of: authService.isAuthenticated) {
                if authService.isAuthenticated {
                    loadNotes()
                }
            }
            .onChange(of: authService.currentUser) {
                if authService.currentUser != nil {
                    loadNotes()
                }
            }
            .alert("Delete Note", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let note = noteToDelete {
                        deleteNote(note)
                    }
                }
            } message: {
                if let note = noteToDelete {
                    Text("Are you sure you want to delete \"\(note.displayTitle)\"? This action cannot be undone.")
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
            .onChange(of: quickActionService.currentAction) { _, action in
                if action == .newNote {
                    showingAddNote = true
                    HapticManager.shared.light()
                } else if action == .search {
                    // Focus search field - handled by searchable modifier
                    HapticManager.shared.light()
                }
            }
            .navigationDestination(item: $noteToEdit) { noteToEdit in
                EditNoteView(
                    note: noteToEdit,
                    onSave: { updatedNote in
                        saveNoteUpdate(updatedNote)
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
                Button(action: { showingAddNote = true }) {
                    Image(systemName: "plus")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(width: 60, height: 60)
                        .background(
                            Circle()
                                .fill(Color.blue)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                        )
                        .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                        .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
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
    
    private var emptyStateView: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Image(systemName: "note.text")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            VStack(spacing: 16) {
                Text("No Notes Yet")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Your notes will appear here")
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
    
    private var notesGrid: some View {
        Group {
            if viewMode == .grid {
                gridView
            } else {
                listView
            }
        }
    }
    
    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(notes, id: \.id) { note in
                    NoteCardView(
                        note: note,
                        onEdit: { noteToEdit in
                            self.noteToEdit = noteToEdit
                        },
                        onDelete: { noteToDelete in
                            confirmDeleteNote(noteToDelete)
                        },
                        onToggleFavorite: { noteToToggle in
                            toggleFavorite(noteToToggle)
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 100) // Space for floating action button
        }
        .refreshable {
            await refreshNotes()
        }
    }
    
    private var listView: some View {
        List(notes, id: \.id) { note in
            NoteListRowView(
                note: note,
                onEdit: { noteToEdit in
                    self.noteToEdit = noteToEdit
                },
                onDelete: { noteToDelete in
                    confirmDeleteNote(noteToDelete)
                }
            )
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowSeparator(.hidden)
        }
        .listStyle(PlainListStyle())
        .refreshable {
            await refreshNotes()
        }
    }
    
    private func refreshNotesIfNeeded() {
        guard let user = authService.currentUser else {
            return
        }
        
        // Check if we should refresh (first load or if it's been more than 30 seconds since last refresh)
        let timeSinceLastRefresh = Date().timeIntervalSince(lastRefreshTime)
        let shouldRefresh = notes.isEmpty || timeSinceLastRefresh > 30
        
        if shouldRefresh {
            lastRefreshTime = Date()
            
            // Use loadNotes for initial load, refreshNotes for subsequent refreshes
            if notes.isEmpty {
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
        case "recent":
            let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            filtered = filtered.filter { $0.createdAt >= weekAgo }
        default: // "all"
            break
        }
        
        // Apply sorting
        switch sortOrder {
        case "date_oldest":
            filtered.sort { $0.createdAt < $1.createdAt }
        case "alpha_asc":
            filtered.sort { ($0.title ?? $0.displayTitle).localizedCaseInsensitiveCompare($1.title ?? $1.displayTitle) == .orderedAscending }
        case "alpha_desc":
            filtered.sort { ($0.title ?? $0.displayTitle).localizedCaseInsensitiveCompare($1.title ?? $1.displayTitle) == .orderedDescending }
        case "modified":
            filtered.sort { $0.updatedAt > $1.updatedAt }
        default: // "date_newest"
            filtered.sort { $0.createdAt > $1.createdAt }
        }
        
        notes = filtered
    }
    
    private func loadNotes() {
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
                
                let fetchedNotes = try await APIService.shared.fetchNotes(userId: user.id)
                
                await MainActor.run {
                    self.allNotes = fetchedNotes
                    self.notes = fetchedNotes
                    self.applyFilter()
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to load notes: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func refreshNotes() async {
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
            
            let fetchedNotes = try await APIService.shared.fetchNotes(userId: user.id)
            
            await MainActor.run {
                self.allNotes = fetchedNotes
                self.notes = fetchedNotes
                self.applyFilter()
                self.isRefreshing = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to refresh notes: \(error.localizedDescription)"
                self.isRefreshing = false
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
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to delete note: \(error.localizedDescription)"
                    self.noteToDelete = nil
                }
            }
        }
    }
    
    private func toggleFavorite(_ note: NoteItem) {
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
                }
            }
        }
    }
    
    private func saveNoteUpdate(_ note: NoteItem) {
        let isExistingNote = allNotes.contains(where: { $0.id == note.id })
        // Update UI immediately (optimistic update)
        if !isExistingNote {
            self.allNotes.insert(note, at: 0)
            self.notes.insert(note, at: 0)
        } else {
            if let index = self.notes.firstIndex(where: { $0.id == note.id }) {
                self.notes[index] = note
            }
            if let index = self.allNotes.firstIndex(where: { $0.id == note.id }) {
                self.allNotes[index] = note
            }
        }
        
        // Save to server in background
        Task {
            do {
                let savedNote: NoteItem
                
                // Use UI state to determine if this is a new or existing note
                if !isExistingNote {
                    // New note - create on server
                    savedNote = try await APIService.shared.saveNote(note)
                } else {
                    // Existing note - update on server
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
                await MainActor.run {
                    self.errorMessage = "Failed to save note: \(error.localizedDescription)"
                }
            }
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
                note.displayTitle.localizedCaseInsensitiveContains(trimmedQuery) ||
                note.content.localizedCaseInsensitiveContains(trimmedQuery) ||
                note.tags.contains { tag in
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
                let searchResults = try await APIService.shared.searchNotes(query: trimmedQuery, userId: user.id)
                
                await MainActor.run {
                    // Only update if this is still the current search
                    if self.searchText.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedQuery {
                        self.notes = searchResults
                    }
                    self.isSearching = false
                }
            } catch {
                await MainActor.run {
                    // Fall back to local search on API error
                    self.notes = self.allNotes.filter { note in
                        note.displayTitle.localizedCaseInsensitiveContains(trimmedQuery) ||
                        note.content.localizedCaseInsensitiveContains(trimmedQuery) ||
                        note.tags.contains { tag in
                            tag.localizedCaseInsensitiveContains(trimmedQuery)
                        }
                    }
                    self.isSearching = false
                }
            }
        }
    }
}
