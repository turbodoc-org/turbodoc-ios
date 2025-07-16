import SwiftUI

struct Constants {
    struct Colors {
        static let primary = Color.blue
        static let secondary = Color(.systemGray)
        static let background = Color(.systemBackground)
        static let secondaryBackground = Color(.systemGray6)
        static let accent = Color.orange
        static let error = Color.red
        static let success = Color.green
    }
    
    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }
    
    struct CornerRadius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
    }
    
    struct Animation {
        static let quick = SwiftUI.Animation.easeInOut(duration: 0.2)
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.3)
        static let slow = SwiftUI.Animation.easeInOut(duration: 0.5)
    }
    
    struct App {
        static let name = "Turbodoc"
        static let version = "1.0.0"
    }
}