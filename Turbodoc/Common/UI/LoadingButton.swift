import SwiftUI

struct LoadingButton: View {
    let title: String
    let isLoading: Bool
    let action: () -> Void
    let variant: ButtonVariant
    
    enum ButtonVariant {
        case primary
        case secondary
        case outline
        case destructive
        case ghost
    }
    
    init(
        title: String,
        isLoading: Bool = false,
        variant: ButtonVariant = .primary,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isLoading = isLoading
        self.variant = variant
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: Constants.Spacing.sm) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: foregroundColor))
                        .scaleEffect(0.8)
                }
                Text(isLoading ? "Loading..." : title)
            }
        }
        .disabled(isLoading)
        .applyButtonStyle(variant: variant, isLoading: isLoading)
    }
    
    private var foregroundColor: Color {
        switch variant {
        case .primary:
            return Constants.Colors.primaryForeground
        case .secondary:
            return Constants.Colors.secondaryForeground
        case .outline:
            return Constants.Colors.cardForeground
        case .destructive:
            return Constants.Colors.destructiveForeground
        case .ghost:
            return Constants.Colors.cardForeground
        }
    }
}

#Preview {
    VStack(spacing: Constants.Spacing.md) {
        LoadingButton(title: "Primary", variant: .primary) {
            print("Primary button tapped")
        }
        
        LoadingButton(title: "Secondary", variant: .secondary) {
            print("Secondary button tapped")
        }
        
        LoadingButton(title: "Outline", variant: .outline) {
            print("Outline button tapped")
        }
        
        LoadingButton(title: "Loading...", isLoading: true, variant: .primary) {
            print("Loading button tapped")
        }
        
        LoadingButton(title: "Destructive", variant: .destructive) {
            print("Destructive button tapped")
        }
    }
    .padding()
    .background(Constants.Colors.background)
}

// MARK: - Button Style Extension

extension View {
    @ViewBuilder
    func applyButtonStyle(variant: LoadingButton.ButtonVariant, isLoading: Bool) -> some View {
        switch variant {
        case .primary:
            self.buttonStyle(PrimaryButtonStyle(isLoading: isLoading))
        case .secondary:
            self.buttonStyle(SecondaryButtonStyle())
        case .outline:
            self.buttonStyle(OutlineButtonStyle())
        case .destructive:
            self.buttonStyle(DestructiveButtonStyle())
        case .ghost:
            self.buttonStyle(GhostButtonStyle())
        }
    }
}