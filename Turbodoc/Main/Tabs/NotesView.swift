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
    
    // Grid layout - 2 columns with improved spacing
    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]
    
    var body: some View {
        NavigationStack {
            VStack {
                if isLoading {
                    loadingView
                } else if notes.isEmpty {
                    emptyStateView
                } else {
                    notesGrid
                }
            }
            .navigationTitle("Notes")
            .searchable(text: $searchText, prompt: "Search notes...")
            .onChange(of: searchText) {
                performSearch(query: searchText)
            }
            .onAppear {
                refreshNotesIfNeeded()
            }
            .onChange(of: scenePhase) {
                if scenePhase == .active && authService.isAuthenticated {
                    refreshNotesIfNeeded()
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
                        updateNote(updatedNote)
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
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(notes, id: \.id) { note in
                    NoteCardView(
                        note: note,
                        onEdit: { noteToEdit in
                            self.noteToEdit = noteToEdit
                        },
                        onDelete: { noteToDelete in
                            confirmDeleteNote(noteToDelete)
                        }
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 12)
            .padding(.bottom, 100) // Space for floating action button
        }
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
    
    private func addNote(_ note: NoteItem) {
        showingAddNote = false
        
        Task {
            do {
                let savedNote = try await APIService.shared.saveNote(note)
                
                await MainActor.run {
                    self.allNotes.insert(savedNote, at: 0)
                    self.notes.insert(savedNote, at: 0)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to add note: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func updateNote(_ note: NoteItem) {
        noteToEdit = nil
        
        Task {
            do {
                let updatedNote = try await APIService.shared.updateNote(note)
                
                await MainActor.run {
                    if let index = self.notes.firstIndex(where: { $0.id == note.id }) {
                        self.notes[index] = updatedNote
                    }
                    if let index = self.allNotes.firstIndex(where: { $0.id == note.id }) {
                        self.allNotes[index] = updatedNote
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to update note: \(error.localizedDescription)"
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
