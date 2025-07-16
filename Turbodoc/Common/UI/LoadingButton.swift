import SwiftUI

struct LoadingButton: View {
    let title: String
    let isLoading: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                }
                Text(title)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Constants.Colors.primary)
            .foregroundColor(.white)
            .cornerRadius(Constants.CornerRadius.medium)
        }
        .disabled(isLoading)
    }
}

#Preview {
    VStack {
        LoadingButton(title: "Sign In", isLoading: false) {
            print("Button tapped")
        }
        
        LoadingButton(title: "Loading...", isLoading: true) {
            print("Button tapped")
        }
    }
    .padding()
}