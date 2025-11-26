import SwiftUI

/// Comprehensive bookmark editor supporting title, URL, tags, and status
struct BookmarkEditView: View {
    let bookmark: BookmarkItem
    let onSave: (BookmarkItem) -> Void
    
    @State private var title: String
    @State private var url: String
    @State private var selectedTags: [String]
    @State private var status: BookmarkItem.ItemStatus
    @State private var shouldProcessTags = false
    @Environment(\.dismiss) private var dismiss
    
    init(bookmark: BookmarkItem, onSave: @escaping (BookmarkItem) -> Void) {
        self.bookmark = bookmark
        self.onSave = onSave
        _title = State(initialValue: bookmark.title)
        _url = State(initialValue: bookmark.url ?? "")
        _selectedTags = State(initialValue: bookmark.tags)
        _status = State(initialValue: bookmark.status)
    }
    
    var body: some View {
        NavigationView {
            Form {
                // Title Section
                Section(header: Text("Title")) {
                    TextField("Bookmark title", text: $title)
                }
                
                // URL Section
                Section(header: Text("URL")) {
                    TextField("https://example.com", text: $url)
                        .keyboardType(.URL)
                        .autocorrectionDisabled(true)
                        .autocapitalization(.none)
                }
                
                // Status Section
                Section(header: Text("Status")) {
                    Picker("Status", selection: $status) {
                        ForEach(BookmarkItem.ItemStatus.allCases, id: \.self) { status in
                            HStack {
                                Circle()
                                    .fill(colorForStatus(status))
                                    .frame(width: 10, height: 10)
                                Text(status.rawValue.capitalized)
                            }
                            .tag(status)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                // Tags Section
                Section(header: Text("Tags")) {
                    TagSuggestionsView(selectedTags: $selectedTags, shouldProcess: $shouldProcessTags)
                    
                    if !selectedTags.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Selected Tags")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            FlowLayout(spacing: 8) {
                                ForEach(selectedTags, id: \.self) { tag in
                                    HStack(spacing: 4) {
                                        Text(tag)
                                            .font(.caption)
                                        
                                        Button(action: {
                                            selectedTags.removeAll { $0 == tag }
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(.systemGray5))
                                    .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit Bookmark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        shouldProcessTags = true
                        // Give a moment for the state change to propagate
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            saveChanges()
                        }
                    }
                    .disabled(title.trim().isEmpty || url.trim().isEmpty)
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
    
    private func saveChanges() {
        var updatedBookmark = bookmark
        updatedBookmark.title = title.trim()
        updatedBookmark.url = url.trim()
        updatedBookmark.tags = selectedTags
        updatedBookmark.status = status
        
        onSave(updatedBookmark)
        dismiss()
    }
}

// MARK: - Flow Layout for Tags

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
            let position = result.positions[index]
            subview.place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if currentX + size.width > maxWidth && currentX > 0 {
                    // Move to next line
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }
                
                positions.append(CGPoint(x: currentX, y: currentY))
                currentX += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }
            
            self.size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}

// MARK: - String Extension

extension String {
    func trim() -> String {
        self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Preview

#Preview {
    let sampleBookmark = BookmarkItem(
        title: "SwiftUI Documentation",
        url: "https://developer.apple.com/documentation/swiftui",
        contentType: .link,
        userId: "user-123"
    )
    sampleBookmark.tags = ["swift", "ios", "development"]
    sampleBookmark.status = .unread
    
    return BookmarkEditView(bookmark: sampleBookmark) { updatedBookmark in
        print("Saved: \(updatedBookmark.title)")
    }
}
