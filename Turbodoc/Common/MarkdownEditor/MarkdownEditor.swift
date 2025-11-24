import SwiftUI
import UIKit

struct MarkdownEditor: UIViewRepresentable {
    @Binding var text: String
    var disableMarkdown: Bool = false
    
    func makeUIView(context: Context) -> UITextView {
        context.coordinator.disableMarkdown = disableMarkdown
        
        if disableMarkdown {
            // Use plain UITextView when markdown is disabled
            let textView = UITextView()
            textView.font = .systemFont(ofSize: 17)
            textView.textColor = .label
            textView.backgroundColor = .systemBackground
            textView.autocorrectionType = .default
            textView.autocapitalizationType = .sentences
            textView.delegate = context.coordinator
            return textView
        } else {
            // Use markdown text view when enabled
            let textView = MarkdownTextView()
            textView.externalDelegate = context.coordinator
            return textView
        }
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        // Check if we need to recreate the view due to markdown mode change
        let shouldBeMarkdown = !disableMarkdown
        let isCurrentlyMarkdown = uiView is MarkdownTextView
        
        if shouldBeMarkdown != isCurrentlyMarkdown {
            // The view type needs to change - SwiftUI will handle recreation
            return
        }
        
        // Only update if the text has actually changed AND it's not from internal editing
        if uiView.text != text && !context.coordinator.isInternalChange {
            uiView.text = text
        }
        context.coordinator.isInternalChange = false
    }
    
    // Add this to force view recreation when markdown mode changes
    static func dismantleUIView(_ uiView: UITextView, coordinator: Coordinator) {
        uiView.delegate = nil
        if let markdownView = uiView as? MarkdownTextView {
            markdownView.externalDelegate = nil
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: MarkdownEditor
        var isInternalChange = false
        var disableMarkdown = false
        
        init(_ parent: MarkdownEditor) {
            self.parent = parent
        }
        
        func textViewDidChange(_ textView: UITextView) {
            isInternalChange = true
            parent.text = textView.text ?? ""
        }
    }
}
