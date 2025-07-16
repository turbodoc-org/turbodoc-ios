import SwiftUI

class AuthenticationCoordinator: ObservableObject {
    @Published var currentScreen: AuthScreen = .signIn
    
    enum AuthScreen {
        case signIn
        case signUp
        case forgotPassword
    }
    
    func showSignUp() {
        currentScreen = .signUp
    }
    
    func showSignIn() {
        currentScreen = .signIn
    }
    
    func showForgotPassword() {
        currentScreen = .forgotPassword
    }
}