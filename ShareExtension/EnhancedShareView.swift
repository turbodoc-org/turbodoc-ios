import SwiftUI

struct EnhancedShareView: View {
    let sharedURL: String
    let onSave: (ShareBookmarkData) -> Void
    let onCancel: () -> Void
    
    @State private var title: String = ""
    @State private var selectedTags: [String] = []
    @State private var suggestedTags: [String] = []
    @State private var status: String = "unread"
    @State private var ogImageURL: String?
    @State private var isLoadingMetadata = true
    @State private var isDuplicate = false
    @State private var showTagSuggestions = false
    @State private var hasUserEditedTitle = false
    
    private let appGroupIdentifier = "group.ai.turbodoc.ios.Turbodoc"
    
    var body: some View {
        NavigationView {
            Form {
                // URL Preview Section
                Section {
                    if let ogImageURL = ogImageURL {
                        AsyncImage(url: URL(string: ogImageURL)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 160)
                                .clipped()
                                .cornerRadius(8)
                        } placeholder: {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 160)
                                .overlay {
                                    if isLoadingMetadata {
                                        ProgressView()
                                    }
                                }
                                .cornerRadius(8)
                        }
                    }
                    
                    Text(sharedURL)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                // Duplicate Warning
                if isDuplicate {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("This URL already exists in your bookmarks")
                                .font(.callout)
                        }
                    }
                }
                
                // Title Section
                Section(header: Text("Title")) {
                    TextField("Enter bookmark title", text: $title)
                        .disabled(isLoadingMetadata)
                        .onChange(of: title) { _ in
                            hasUserEditedTitle = true
                        }
                }
                
                // Status Section
                Section(header: Text("Status")) {
                    Picker("Status", selection: $status) {
                        HStack {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 8, height: 8)
                            Text("Unread")
                        }
                        .tag("unread")
                        
                        HStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("Read")
                        }
                        .tag("read")
                    }
                    .pickerStyle(.segmented)
                }
                
                // Tags Section
                Section(header: Text("Tags")) {
                    if !selectedTags.isEmpty {
                        FlowLayout(spacing: 8) {
                            ForEach(selectedTags, id: \.self) { tag in
                                TagChip(tag: tag, isSelected: true) {
                                    selectedTags.removeAll { $0 == tag }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    Button(action: { showTagSuggestions.toggle() }) {
                        HStack {
                            Image(systemName: "tag")
                            Text("Add Tags")
                            Spacer()
                            Image(systemName: showTagSuggestions ? "chevron.up" : "chevron.down")
                                .font(.caption)
                        }
                    }
                    
                    if showTagSuggestions && !suggestedTags.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Suggested")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            FlowLayout(spacing: 8) {
                                ForEach(suggestedTags, id: \.self) { tag in
                                    TagChip(tag: tag, isSelected: selectedTags.contains(tag)) {
                                        if selectedTags.contains(tag) {
                                            selectedTags.removeAll { $0 == tag }
                                        } else {
                                            selectedTags.append(tag)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Save Bookmark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveBookmark()
                    }
                    .disabled(title.isEmpty || isLoadingMetadata)
                }
            }
            .onAppear {
                loadMetadata()
                loadSuggestedTags()
                checkForDuplicates()
            }
        }
    }
    
    private func loadMetadata() {
        isLoadingMetadata = true
        
        // Extract domain for basic title
        if let url = URL(string: sharedURL) {
            title = url.host?.replacingOccurrences(of: "www.", with: "") ?? "Untitled"
        }
        
        // Attempt to fetch OG metadata
        Task {
            do {
                let metadata = try await fetchOGMetadata(url: sharedURL)
                await MainActor.run {
                    // Only update title if user hasn't manually edited it
                    if !hasUserEditedTitle, let fetchedTitle = metadata.title, !fetchedTitle.isEmpty {
                        self.title = fetchedTitle
                    }
                    self.ogImageURL = metadata.ogImage
                    self.isLoadingMetadata = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingMetadata = false
                }
            }
        }
    }
    
    private func loadSuggestedTags() {
        // Load from shared container
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return
        }
        
        let tagsURL = containerURL.appendingPathComponent("suggestedTags.json")
        
        guard FileManager.default.fileExists(atPath: tagsURL.path),
              let data = try? Data(contentsOf: tagsURL),
              let tags = try? JSONDecoder().decode([String].self, from: data) else {
            // Default suggested tags
            suggestedTags = ["article", "tutorial", "reference", "video", "tool"]
            return
        }
        
        suggestedTags = tags
    }
    
    private func checkForDuplicates() {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return
        }
        
        let bookmarksURL = containerURL.appendingPathComponent("savedBookmarks.json")
        
        guard FileManager.default.fileExists(atPath: bookmarksURL.path),
              let data = try? Data(contentsOf: bookmarksURL),
              let bookmarks = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return
        }
        
        isDuplicate = bookmarks.contains { ($0["url"] as? String) == sharedURL }
    }
    
    private func fetchOGMetadata(url: String) async throws -> (title: String?, ogImage: String?) {
        // Get auth token
        guard let authToken = getAuthToken() else {
            throw URLError(.userAuthenticationRequired)
        }
        
        // Call API to fetch metadata
        guard let apiURL = URL(string: "https://api.turbodoc.ai/v1/og-image?url=\(url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: apiURL)
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        struct OGResponse: Codable {
            let title: String?
            let ogImage: String?
        }
        
        let response = try JSONDecoder().decode(OGResponse.self, from: data)
        return (response.title, response.ogImage)
    }
    
    private func getAuthToken() -> String? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return nil
        }
        
        let authURL = containerURL.appendingPathComponent("auth.json")
        
        guard FileManager.default.fileExists(atPath: authURL.path),
              let data = try? Data(contentsOf: authURL),
              let authData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = authData["accessToken"] as? String else {
            return nil
        }
        
        return token
    }
    
    private func saveBookmark() {
        let bookmarkData = ShareBookmarkData(
            url: sharedURL,
            title: title,
            tags: selectedTags,
            status: status,
            ogImageURL: ogImageURL
        )
        
        onSave(bookmarkData)
    }
}

// MARK: - Supporting Types

struct ShareBookmarkData {
    let url: String
    let title: String
    let tags: [String]
    let status: String
    let ogImageURL: String?
}

struct TagChip: View {
    let tag: String
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(tag)
                    .font(.caption)
                
                if isSelected {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue : Color(.systemGray5))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(16)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX, y: bounds.minY + result.frames[index].minY), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var frames: [CGRect] = []
        var size: CGSize = .zero
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                
                frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}
