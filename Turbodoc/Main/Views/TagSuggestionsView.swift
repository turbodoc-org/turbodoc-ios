import SwiftUI

/// Reusable tag suggestions component with chip-based UI and caching
struct TagSuggestionsView: View {
    @Binding var selectedTags: [String]
    @State private var availableTags: [APITagItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    // Cache management
    @AppStorage("cachedTags") private var cachedTagsJSON: String = "[]"
    @AppStorage("tagsCacheTimestamp") private var tagsCacheTimestamp: Double = 0
    private let cacheExpirationSeconds: Double = 300 // 5 minutes
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggested Tags")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading tags...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            } else if availableTags.isEmpty && errorMessage == nil {
                Text("No suggested tags yet. Start tagging bookmarks to see suggestions!")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.vertical, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(availableTags, id: \.tag) { tagItem in
                            TagChip(
                                tag: tagItem.tag,
                                count: tagItem.count,
                                isSelected: selectedTags.contains(tagItem.tag),
                                onTap: {
                                    toggleTag(tagItem.tag)
                                }
                            )
                        }
                    }
                }
                .frame(height: 36)
            }
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.vertical, 4)
            }
        }
        .onAppear {
            loadTags()
        }
    }
    
    // MARK: - Tag Management
    
    private func toggleTag(_ tag: String) {
        if let index = selectedTags.firstIndex(of: tag) {
            selectedTags.remove(at: index)
        } else {
            selectedTags.append(tag)
        }
    }
    
    // MARK: - Cache & API
    
    private func loadTags() {
        // Check cache first
        let now = Date().timeIntervalSince1970
        let cacheAge = now - tagsCacheTimestamp
        
        if cacheAge < cacheExpirationSeconds, let cachedTags = loadCachedTags(), !cachedTags.isEmpty {
            // Use cached data
            availableTags = cachedTags
            return
        }
        
        // Fetch from API
        fetchTagsFromAPI()
    }
    
    private func loadCachedTags() -> [APITagItem]? {
        guard let data = cachedTagsJSON.data(using: .utf8),
              let tags = try? JSONDecoder().decode([APITagItem].self, from: data) else {
            return nil
        }
        return tags
    }
    
    private func saveCacheToStorage(_ tags: [APITagItem]) {
        if let data = try? JSONEncoder().encode(tags),
           let jsonString = String(data: data, encoding: .utf8) {
            cachedTagsJSON = jsonString
            tagsCacheTimestamp = Date().timeIntervalSince1970
        }
    }
    
    private func fetchTagsFromAPI() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let tags = try await APIService.shared.fetchTags()
                
                await MainActor.run {
                    self.availableTags = tags
                    self.saveCacheToStorage(tags)
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to load tag suggestions"
                    self.isLoading = false
                    
                    // Try to use cached data even if expired
                    if let cachedTags = loadCachedTags() {
                        self.availableTags = cachedTags
                        self.errorMessage = nil
                    }
                }
            }
        }
    }
}

// MARK: - Tag Chip Component

struct TagChip: View {
    let tag: String
    let count: Int
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(tag)
                    .font(.caption)
                    .fontWeight(.medium)
                
                Text("\(count)")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(chipCountBackgroundColor)
                    .foregroundColor(chipCountForegroundColor)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(chipBackgroundColor)
            .foregroundColor(chipForegroundColor)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(chipBorderColor, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var chipBackgroundColor: Color {
        isSelected ? .blue : Color(.systemGray6)
    }
    
    private var chipForegroundColor: Color {
        isSelected ? .white : .primary
    }
    
    private var chipBorderColor: Color {
        isSelected ? .blue : Color(.systemGray4)
    }
    
    private var chipCountBackgroundColor: Color {
        isSelected ? Color.white.opacity(0.2) : Color(.systemGray5)
    }
    
    private var chipCountForegroundColor: Color {
        isSelected ? .white : .secondary
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        TagSuggestionsView(selectedTags: .constant(["swift", "ios"]))
            .padding()
        
        Divider()
        
        VStack {
            Text("Selected: swift, ios")
                .font(.caption)
        }
    }
}
