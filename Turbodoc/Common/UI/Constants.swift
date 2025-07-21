import SwiftUI

struct Constants {
    struct Colors {
        // Primary colors matching web app hsl(207, 100%, 50%)
        static let primary = Color(hue: 207/360, saturation: 1.0, brightness: 0.5)
        static let primaryForeground = Color.white
        
        // Secondary colors matching web app
        static let secondary = Color(.systemGray6)
        static let secondaryForeground = Color(.label)
        
        // Background colors
        static let background = Color(.systemBackground)
        static let cardBackground = Color(.systemBackground)
        static let cardForeground = Color(.label)
        
        // Accent color matching web app hsl(25, 100%, 50%)
        static let accent = Color(hue: 25/360, saturation: 1.0, brightness: 0.5)
        static let accentForeground = Color.white
        
        // Status colors
        static let destructive = Color(hue: 0/360, saturation: 0.842, brightness: 0.602)
        static let destructiveForeground = Color.white
        static let success = Color(hue: 120/360, saturation: 1.0, brightness: 0.4)
        static let successForeground = Color.white
        static let warning = Color(hue: 45/360, saturation: 1.0, brightness: 0.5)
        static let warningForeground = Color.black
        
        // Utility colors
        static let muted = Color(.systemGray5)
        static let mutedForeground = Color(.systemGray)
        static let border = Color(.systemGray4)
        static let inputBackground = Color(.systemGray6)
        static let ring = Color(hue: 207/360, saturation: 1.0, brightness: 0.5)
        
        // Legacy aliases for backward compatibility
        static let error = destructive
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
        // Matching web app --radius: 0.75rem (12px)
        static let small: CGFloat = 8  // sm: calc(var(--radius) - 4px)
        static let medium: CGFloat = 10 // md: calc(var(--radius) - 2px)
        static let large: CGFloat = 12  // lg: var(--radius)
        
        // Legacy aliases
        static let `default` = large
    }
    
    struct Animation {
        static let quick = SwiftUI.Animation.easeInOut(duration: 0.2)
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.3)
        static let slow = SwiftUI.Animation.easeInOut(duration: 0.5)
    }
    
    struct Typography {
        struct FontSizes {
            static let xs: CGFloat = 12
            static let sm: CGFloat = 14
            static let base: CGFloat = 16
            static let lg: CGFloat = 18
            static let xl: CGFloat = 20
            static let xxl: CGFloat = 24
        }
    }
    
    struct App {
        static let name = "Turbodoc"
        static let version = "1.0.0"
    }
}