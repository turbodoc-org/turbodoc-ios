import SwiftUI
import UIKit

/// Colors for the gallery and list screens, matching the "Theme" tokens in the
/// Turbodoc design file (nano.design, page "iOS app — Bookmarks & Notes").
enum Theme {
    /// Screen background behind cards (`color/bg`).
    static let background = dynamic(light: 0xFAFAFA, dark: 0x0B0B0D)
    /// Card surface (`color/surface`).
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x131418)
    /// Filter chips and search field (`color/surface-2`).
    static let surfaceSecondary = dynamic(light: 0xF4F4F5, dark: 0x1A1C21)
    /// Card border (`color/line`).
    static let line = dynamic(light: 0xE4E4E7, dark: 0x24262C)
    static let lineStrong = dynamic(light: 0xD4D4D8, dark: 0x363944)
    /// Preview area inside a card (`color/thumb`).
    static let thumb = dynamic(light: 0xF7F7F8, dark: 0x17181D)
    static let thumbLine = dynamic(light: 0xECECEF, dark: 0x202228)
    /// Headings inside a preview (`color/thumb-ink`).
    static let thumbInk = dynamic(light: 0x27272A, dark: 0xD4D4D8)
    /// Body text inside a preview (`color/thumb-text`).
    static let thumbText = dynamic(light: 0x5B5D66, dark: 0x9A9CA6)
    /// Secondary metadata (`color/faint`).
    static let faint = dynamic(light: 0x71717A, dark: 0x80838E)
    static let codeInk = dynamic(light: 0x3F3F46, dark: 0xC4C6CF)

    /// Note identity color (`accent/note`).
    static let noteAccent = dynamic(light: 0xD97706, dark: 0xF5A524)
    /// Unread dot (`ios/unread`).
    static let unread = dynamic(light: 0x2563EB, dark: 0x4F8FF7)
    /// Favorite star (`ios/favorite`).
    static let favorite = dynamic(light: 0xF5B800, dark: 0xFFD60A)
    /// Broken links (`ios/danger`).
    static let danger = dynamic(light: 0xDC2626, dark: 0xFF6961)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Date {
    /// Short, scannable dates for list metadata: "Today", "Yesterday", "3d",
    /// "Oct 28", or "Oct 28, 2025" for earlier years.
    var compactDisplay: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return "Today" }
        if calendar.isDateInYesterday(self) { return "Yesterday" }

        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: self),
            to: calendar.startOfDay(for: Date())
        ).day ?? 0
        if days > 0 && days < 7 { return "\(days)d" }

        if calendar.isDate(self, equalTo: Date(), toGranularity: .year) {
            return formatted(.dateTime.month(.abbreviated).day())
        }
        return formatted(.dateTime.month(.abbreviated).day().year())
    }
}

/// Buckets for grouping a date-sorted list into sections.
enum DateSection: String, CaseIterable {
    case today = "Today"
    case thisWeek = "This Week"
    case thisMonth = "This Month"
    case earlier = "Earlier"

    init(_ date: Date, now: Date = Date()) {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            self = .today
        } else if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 7 {
            self = .thisWeek
        } else if calendar.isDate(date, equalTo: now, toGranularity: .month) {
            self = .thisMonth
        } else {
            self = .earlier
        }
    }
}

/// Groups items into consecutive date sections, keeping their order.
func groupedByDateSection<Item>(
    _ items: [Item],
    date: (Item) -> Date
) -> [(section: DateSection, items: [Item])] {
    var groups: [(section: DateSection, items: [Item])] = []
    for item in items {
        let section = DateSection(date(item))
        if groups.last?.section == section {
            groups[groups.count - 1].items.append(item)
        } else {
            groups.append((section, [item]))
        }
    }
    return groups
}

/// A stable, pleasant gradient for a string (e.g. a domain), used when a
/// bookmark has no preview image.
func fallbackGradient(for key: String) -> LinearGradient {
    let hash = key.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
    let hue = Double(abs(hash) % 360) / 360
    return LinearGradient(
        colors: [
            Color(hue: hue, saturation: 0.45, brightness: 0.95),
            Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.6, brightness: 0.8),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
