import SwiftUI

/// Two-segment grid / list switch for the navigation bar.
struct ViewModePicker: View {
    @Binding var selection: ViewMode
    
    var body: some View {
        Picker("View", selection: $selection) {
            ForEach(ViewMode.allCases, id: \.self) { mode in
                Image(systemName: mode.iconName)
                    .accessibilityLabel(mode.rawValue)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .onChange(of: selection) {
            HapticManager.shared.selection()
        }
    }
}

/// The grid / list switch as a trailing toolbar item.
///
/// The segmented control already draws its own glass track, so on iOS 26 it
/// opts out of the toolbar's shared glass pill instead of sitting inside it.
struct ViewModeToolbarItem: ToolbarContent {
    @Binding var selection: ViewMode
    
    var body: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarTrailing) {
                ViewModePicker(selection: $selection)
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                ViewModePicker(selection: $selection)
            }
        }
    }
}

/// "267 saved · 3 broken links": the summary line above the filter chips.
///
/// Drawn as content rather than with `navigationSubtitle`, which leaves the
/// search field blank when the screen's scroll view isn't a List.
struct ListSummary: View {
    let text: String
    var highlight: String? = nil
    var highlightColor: Color = Theme.danger
    
    var body: some View {
        Group {
            if let highlight {
                Text("\(text) · ") + Text(highlight).foregroundStyle(highlightColor).fontWeight(.medium)
            } else {
                Text(text)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 2)
    }
}
