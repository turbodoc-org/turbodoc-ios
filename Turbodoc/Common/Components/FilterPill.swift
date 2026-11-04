import SwiftUI

struct FilterPill: View {
    let title: String
    let count: Int?
    let isSelected: Bool
    /// `nil` for the standard ink chip; a color (e.g. red for Broken) tints it.
    var tint: Color? = nil
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            HapticManager.shared.selection()
            action()
        }) {
            HStack(spacing: 6) {
                Text(title)
                    .fontWeight(isSelected ? .semibold : .medium)
                
                if let count {
                    Text("\(count)")
                        .fontWeight(.medium)
                        .foregroundStyle(countStyle)
                        .monospacedDigit()
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
    
    private var foreground: Color {
        if isSelected { return tint == nil ? Theme.background : .white }
        return tint ?? .primary
    }
    
    private var background: Color {
        if isSelected { return tint ?? .primary }
        return tint?.opacity(0.12) ?? Theme.surfaceSecondary
    }
    
    private var countStyle: Color {
        if isSelected || tint != nil { return foreground.opacity(0.7) }
        return Theme.faint
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
        let tint: Color?
        
        init(id: String, title: String, count: Int? = nil, tint: Color? = nil) {
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
        HStack(spacing: 8) {
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
        .padding(.top, 6)
        .padding(.bottom, 10)
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
