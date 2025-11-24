import SwiftUI

struct RootView: View {
    @EnvironmentObject var authService: AuthenticationService
    
    var body: some View {
        Group {
            switch authService.authenticationStatus {
            case .authenticated:
                MainTabView()
            case .notAuthenticated:
                SignInView()
            case .loading:
                loadingView
            }
        }
        .animation(.easeInOut(duration: 0.3), value: authService.authenticationStatus)
    }
    
    private var loadingView: some View {
        ZStack {
            Color(red: 0.12156862745098039, green: 0.12941176470588237, blue: 0.14117647058823529)
                .ignoresSafeArea()
            
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 154, height: 128)
                .offset(x: -5, y: -25)
        }
    }
}
