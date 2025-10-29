import SwiftUI
import Combine

enum QuickAction: String {
    case newBookmark
    case newNote
    case search
}

class QuickActionService: ObservableObject {
    @Published var currentAction: QuickAction?
    
    func triggerAction(_ action: QuickAction) {
        currentAction = action
        
        // Reset after a short delay to allow re-triggering the same action
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.currentAction = nil
        }
    }
}
