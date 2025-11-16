import SwiftUI
import UIKit

struct MarkdownEditor: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onTextChange: ((String) -> Void)?
    
    func makeUIView(context: Context) -> MarkdownTextView {
        let textView = MarkdownTextView()
        textView.delegate = context.coordinator
        textView.markdownText = text
        
        // Add placeholder if needed
        if text.isEmpty {
            textView.text = placeholder
            textView.textColor = .placeholderText
        }
        
        return textView
    }
    
    func updateUIView(_ uiView: MarkdownTextView, context: Context) {
        // Only update if the text is different to avoid cursor jumping
        if uiView.markdownText != text {
            let selectedRange = uiView.selectedRange
            uiView.markdownText = text
            
            // Restore cursor position if possible
            if selectedRange.location <= uiView.markdownText.count {
                uiView.selectedRange = selectedRange
            }
        }
        
        // Handle placeholder
        if text.isEmpty && uiView.markdownText != placeholder {
            uiView.text = placeholder
            uiView.textColor = .placeholderText
        } else if !text.isEmpty && uiView.textColor == .placeholderText {
            uiView.textColor = .label
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: MarkdownEditor
        
        init(_ parent: MarkdownEditor) {
            self.parent = parent
        }
        
        func textViewDidChange(_ textView: UITextView) {
            guard let markdownTextView = textView as? MarkdownTextView else { return }
            
            // Update binding
            parent.text = markdownTextView.markdownText
            
            // Call callback
            parent.onTextChange?(markdownTextView.markdownText)
        }
        
        func textViewDidBeginEditing(_ textView: UITextView) {
            // Remove placeholder
            if textView.textColor == .placeholderText {
                textView.text = ""
                textView.textColor = .label
            }
        }
        
        func textViewDidEndEditing(_ textView: UITextView) {
            // Restore placeholder if empty
            if textView.text.isEmpty {
                textView.text = parent.placeholder
                textView.textColor = .placeholderText
            }
        }
    }
}
