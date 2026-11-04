import SwiftUI

struct FilterPill: View {
    let title: String
    let count: Int?
    let isSelected: Bool
    var tint: Color = .blue
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            HapticManager.shared.selection()
            action()
        }) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                
                if let count = count, count > 0 {
                    Text("(\(count))")
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                isSelected ? tint : Color(.systemGray6)
            )
            .foregroundColor(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct FilterPillsBar: View {
    let filters: [FilterItem]
    let selectedFilter: String
    let onSelect: (String) -> Void
    
    struct FilterItem: Identifiable {
        let id: String
        let title: String
        let count: Int?
        let tint: Color
        
        init(id: String, title: String, count: Int? = nil, tint: Color = .blue) {
            self.id = id
            self.title = title
            self.count = count
            self.tint = tint
        }
    }
    
    var body: some View {
        // A second scroll view on screen stops tap-the-status-bar from
        // scrolling the list to the top, so only scroll when the pills don't
        // fit (large Dynamic Type sizes).
        ViewThatFits(in: .horizontal) {
            pills
            
            ScrollView(.horizontal, showsIndicators: false) {
                pills
            }
            .scrollClipDisabled()
        }
    }
    
    private var pills: some View {
        HStack(spacing: 12) {
            ForEach(filters) { filter in
                FilterPill(
                    title: filter.title,
                    count: filter.count,
                    isSelected: selectedFilter == filter.id,
                    tint: filter.tint,
                    action: {
                        onSelect(filter.id)
                    }
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    VStack(spacing: 20) {
        FilterPillsBar(
            filters: [
                .init(id: "all", title: "All", count: 42),
                .init(id: "favorites", title: "Favorites", count: 5),
                .init(id: "recent", title: "Recent", count: 12),
                .init(id: "tag1", title: "Work", count: 8)
            ],
            selectedFilter: "all",
            onSelect: { _ in }
        )
        
        FilterPillsBar(
            filters: [
                .init(id: "all", title: "All", count: 128),
                .init(id: "unread", title: "Unread", count: 45),
                .init(id: "favorites", title: "Favorites", count: 12),
                .init(id: "archived", title: "Archived", count: 23)
            ],
            selectedFilter: "favorites",
            onSelect: { _ in }
        )
    }
}
