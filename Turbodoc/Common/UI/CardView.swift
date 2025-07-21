import SwiftUI

// MARK: - Card Component matching web app design

struct CardView<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .background(Constants.Colors.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: Constants.CornerRadius.large)
                .stroke(Constants.Colors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Constants.CornerRadius.large))
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct CardHeader<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
            content
        }
        .padding(Constants.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CardTitle: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.system(size: Constants.Typography.FontSizes.xl, weight: .semibold))
            .foregroundColor(Constants.Colors.cardForeground)
            .lineLimit(nil)
    }
}

struct CardDescription: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.system(size: Constants.Typography.FontSizes.sm))
            .foregroundColor(Constants.Colors.mutedForeground)
            .lineLimit(nil)
    }
}

struct CardContent<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.md) {
            content
        }
        .padding(Constants.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CardFooter<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        HStack {
            content
        }
        .padding(Constants.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: Constants.Spacing.lg) {
        CardView {
            CardHeader {
                CardTitle(text: "Login")
                CardDescription(text: "Enter your email below to login to your account")
            }
            
            CardContent {
                VStack(spacing: Constants.Spacing.md) {
                    TextField("Email", text: .constant(""))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    SecureField("Password", text: .constant(""))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
            }
            
            CardFooter {
                Button("Login") {
                    // Action
                }
                .primaryButtonStyle()
            }
        }
    }
    .padding()
    .background(Constants.Colors.background)
}