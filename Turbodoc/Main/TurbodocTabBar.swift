import SwiftUI

/// Tabs shown in the custom bottom bar.
enum AppTab: Hashable, CaseIterable {
    case bookmarks, notes, profile

    var title: String {
        switch self {
        case .bookmarks: return "Bookmarks"
        case .notes: return "Notes"
        case .profile: return "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .bookmarks: return "bookmark.fill"
        case .notes: return "text.justify"
        case .profile: return "person.fill"
        }
    }
}

/// The bottom bar from the design: a glass capsule with the tabs and a solid
/// blue add button beside it.
///
/// Drawn by the app rather than the system tab bar because iOS places (and
/// colours) its own extra tab-bar button differently per device and version.
struct TurbodocTabBar: View {
    @Binding var selection: AppTab
    let addTitle: String
    let onAdd: () -> Void

    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                ForEach(AppTab.allCases, id: \.self, content: tabButton)
            }
            .padding(4)
            .frame(maxWidth: .infinity)
            .barBackground(in: Capsule())

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 62, height: 62)
                    .floatingActionButtonBackground(.accentColor)
            }
            .buttonStyle(CardPressButtonStyle())
            .accessibilityLabel(addTitle)
        }
        .frame(maxWidth: 480)
        .padding(.horizontal, 16)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = tab == selection
        return Button {
            guard !isSelected else { return }
            withAnimation(.spring(duration: 0.3)) {
                selection = tab
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 20, weight: .medium))
                    .frame(height: 26)
                Text(tab.title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private extension View {
    /// Liquid Glass on iOS 26+, a material capsule before that.
    @ViewBuilder
    func barBackground(in shape: Capsule) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.06)))
                .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        }
    }
}

/// Lets a pushed screen (e.g. the note editor) hide the bottom bar.
@MainActor
@Observable
final class TabBarVisibility {
    fileprivate(set) var hiddenRequests = 0
    var isHidden: Bool { hiddenRequests > 0 }

    fileprivate func hide() { hiddenRequests += 1 }
    fileprivate func show() { hiddenRequests = max(0, hiddenRequests - 1) }
}

private struct HidesTabBar: ViewModifier {
    @Environment(TabBarVisibility.self) private var visibility

    func body(content: Content) -> some View {
        content
            .onAppear { withAnimation(.easeOut(duration: 0.2)) { visibility.hide() } }
            .onDisappear { withAnimation(.easeOut(duration: 0.2)) { visibility.show() } }
    }
}

extension View {
    /// Hides the bottom bar while this view is on screen.
    func hidesTabBar() -> some View {
        modifier(HidesTabBar())
    }
}
