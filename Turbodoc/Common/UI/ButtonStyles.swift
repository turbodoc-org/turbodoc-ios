import SwiftUI

// MARK: - Button Styles matching web app design system

struct PrimaryButtonStyle: ButtonStyle {
    let isLoading: Bool
    
    init(isLoading: Bool = false) {
        self.isLoading = isLoading
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: Constants.Typography.FontSizes.sm, weight: .medium))
            .foregroundColor(Constants.Colors.primaryForeground)
            .frame(maxWidth: .infinity)
            .frame(height: 36) // h-9 in Tailwind
            .padding(.horizontal, Constants.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Constants.CornerRadius.medium)
                    .fill(Constants.Colors.primary)
                    .opacity(configuration.isPressed ? 0.9 : 1.0)
            )
            .opacity(isLoading ? 0.5 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(Constants.Animation.quick, value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: Constants.Typography.FontSizes.sm, weight: .medium))
            .foregroundColor(Constants.Colors.secondaryForeground)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .padding(.horizontal, Constants.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Constants.CornerRadius.medium)
                    .fill(Constants.Colors.secondary)
                    .opacity(configuration.isPressed ? 0.8 : 1.0)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(Constants.Animation.quick, value: configuration.isPressed)
    }
}

struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: Constants.Typography.FontSizes.sm, weight: .medium))
            .foregroundColor(Constants.Colors.cardForeground)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .padding(.horizontal, Constants.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Constants.CornerRadius.medium)
                    .fill(Constants.Colors.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: Constants.CornerRadius.medium)
                            .stroke(Constants.Colors.border, lineWidth: 1)
                    )
                    .opacity(configuration.isPressed ? 0.9 : 1.0)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(Constants.Animation.quick, value: configuration.isPressed)
    }
}

struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: Constants.Typography.FontSizes.sm, weight: .medium))
            .foregroundColor(Constants.Colors.destructiveForeground)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .padding(.horizontal, Constants.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Constants.CornerRadius.medium)
                    .fill(Constants.Colors.destructive)
                    .opacity(configuration.isPressed ? 0.9 : 1.0)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(Constants.Animation.quick, value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: Constants.Typography.FontSizes.sm, weight: .medium))
            .foregroundColor(Constants.Colors.cardForeground)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .padding(.horizontal, Constants.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Constants.CornerRadius.medium)
                    .fill(configuration.isPressed ? Constants.Colors.accent.opacity(0.1) : Color.clear)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(Constants.Animation.quick, value: configuration.isPressed)
    }
}

// MARK: - Button View Extensions

extension View {
    func primaryButtonStyle(isLoading: Bool = false) -> some View {
        self.buttonStyle(PrimaryButtonStyle(isLoading: isLoading))
    }
    
    func secondaryButtonStyle() -> some View {
        self.buttonStyle(SecondaryButtonStyle())
    }
    
    func outlineButtonStyle() -> some View {
        self.buttonStyle(OutlineButtonStyle())
    }
    
    func destructiveButtonStyle() -> some View {
        self.buttonStyle(DestructiveButtonStyle())
    }
    
    func ghostButtonStyle() -> some View {
        self.buttonStyle(GhostButtonStyle())
    }
    
    /// Circular floating action button surface: tinted Liquid Glass on
    /// iOS 26+, a solid circle with a soft shadow before that.
    func floatingActionButtonBackground(_ tint: Color) -> some View {
        modifier(FloatingActionButtonBackground(tint: tint))
    }
}

/// Press feedback for tappable cards (bookmark tiles, note cards): a slight
/// shrink, like Apple's own card-style buttons.
struct CardPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

private struct FloatingActionButtonBackground: ViewModifier {
    let tint: Color
    
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(tint).interactive(), in: .circle)
        } else {
            content
                .background(
                    Circle()
                        .fill(tint)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                )
                .shadow(color: tint.opacity(0.3), radius: 8, x: 0, y: 4)
                .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
        }
    }
}