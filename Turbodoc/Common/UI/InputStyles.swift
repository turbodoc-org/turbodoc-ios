import SwiftUI

// MARK: - Input Field Styles matching web app design

struct PrimaryTextFieldStyle: TextFieldStyle {
    @FocusState private var isFocused: Bool
    
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: Constants.Typography.FontSizes.sm))
            .foregroundColor(Constants.Colors.cardForeground)
            .padding(.horizontal, Constants.Spacing.sm + 4) // 12px to match web
            .padding(.vertical, Constants.Spacing.sm)       // 8px to match web
            .frame(height: 36) // h-9 in Tailwind
            .background(
                RoundedRectangle(cornerRadius: Constants.CornerRadius.medium)
                    .fill(Constants.Colors.inputBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: Constants.CornerRadius.medium)
                            .stroke(
                                isFocused ? Constants.Colors.ring : Constants.Colors.border,
                                lineWidth: isFocused ? 2 : 1
                            )
                    )
            )
            .focused($isFocused)
            .animation(Constants.Animation.quick, value: isFocused)
    }
}

struct ErrorTextFieldStyle: TextFieldStyle {
    @FocusState private var isFocused: Bool
    
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: Constants.Typography.FontSizes.sm))
            .foregroundColor(Constants.Colors.cardForeground)
            .padding(.horizontal, Constants.Spacing.sm + 4)
            .padding(.vertical, Constants.Spacing.sm)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: Constants.CornerRadius.medium)
                    .fill(Constants.Colors.inputBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: Constants.CornerRadius.medium)
                            .stroke(Constants.Colors.destructive, lineWidth: 1)
                    )
            )
            .focused($isFocused)
    }
}

// MARK: - Secure Field with Visibility Toggle

struct SecureFieldWithToggle: View {
    let placeholder: String
    @Binding var text: String
    @State private var isPasswordVisible = false
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 0) {
            Group {
                if isPasswordVisible {
                    TextField(placeholder, text: $text)
                        .focused($isFocused)
                } else {
                    SecureField(placeholder, text: $text)
                        .focused($isFocused)
                }
            }
            .font(.system(size: Constants.Typography.FontSizes.sm))
            .foregroundColor(Constants.Colors.cardForeground)
            
            Button(action: { isPasswordVisible.toggle() }) {
                Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: Constants.Typography.FontSizes.sm))
                    .foregroundColor(Constants.Colors.mutedForeground)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, Constants.Spacing.sm + 4)
        .padding(.vertical, Constants.Spacing.sm)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: Constants.CornerRadius.medium)
                .fill(Constants.Colors.inputBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: Constants.CornerRadius.medium)
                        .stroke(
                            isFocused ? Constants.Colors.ring : Constants.Colors.border,
                            lineWidth: isFocused ? 2 : 1
                        )
                )
        )
        .animation(Constants.Animation.quick, value: isFocused)
    }
}

// MARK: - Form Field Component

struct FormField<Content: View>: View {
    let label: String
    let error: String?
    let content: Content
    
    init(
        label: String,
        error: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.label = label
        self.error = error
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
            Text(label)
                .font(.system(size: Constants.Typography.FontSizes.sm, weight: .medium))
                .foregroundColor(Constants.Colors.cardForeground)
            
            content
            
            if let error = error {
                Text(error)
                    .font(.system(size: Constants.Typography.FontSizes.xs))
                    .foregroundColor(Constants.Colors.destructive)
            }
        }
    }
}

// MARK: - View Extensions

extension View {
    func primaryTextFieldStyle() -> some View {
        self.textFieldStyle(PrimaryTextFieldStyle())
    }
    
    func errorTextFieldStyle() -> some View {
        self.textFieldStyle(ErrorTextFieldStyle())
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: Constants.Spacing.lg) {
        FormField(label: "Email") {
            TextField("mail@example.com", text: .constant(""))
                .primaryTextFieldStyle()
        }
        
        FormField(label: "Password", error: "Password is required") {
            SecureField("Password", text: .constant(""))
                .errorTextFieldStyle()
        }
    }
    .padding()
    .background(Constants.Colors.background)
}