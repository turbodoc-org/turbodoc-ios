import UIKit

/// Centralized haptic feedback management.
///
/// Conventions, following Apple's HIG — use the same feedback for the same
/// kind of interaction on every screen:
/// - `selection()`: a value or selection changes (filter pills, sort, view
///   mode, favorite, read/archive status, checklist items).
/// - `light()`: a floating action button is pressed.
/// - `success()` / `error()`: an action the user started finishes (save,
///   delete, copy, sign in, transcription, text recognition).
/// - Nothing for plain navigation, Cancel/Done, opening items or menus; the
///   system already provides feedback for swipe actions and context menus.
class HapticManager {
    static let shared = HapticManager()
    
    private init() {}
    
    // MARK: - Impact Feedback
    
    func light() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    func medium() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
    
    func heavy() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
    }
    
    func rigid() {
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.impactOccurred()
    }
    
    func soft() {
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.impactOccurred()
    }
    
    // MARK: - Notification Feedback
    
    func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
    
    func warning() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }
    
    func error() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }
    
    // MARK: - Selection Feedback
    
    func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
}
