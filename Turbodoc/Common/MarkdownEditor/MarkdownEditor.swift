import SwiftUI
import UIKit

struct MarkdownEditor: UIViewRepresentable {
    @Binding var text: String
    
    func makeUIView(context: Context) -> MarkdownTextView {
        let textView = MarkdownTextView()
        textView.externalDelegate = context.coordinator
        return textView
    }
    
    func updateUIView(_ uiView: MarkdownTextView, context: Context) {
        // Only update if the text has actually changed AND it's not from internal editing
        if uiView.text != text && !context.coordinator.isInternalChange {
            uiView.text = text
        }
        context.coordinator.isInternalChange = false
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: MarkdownEditor
        var isInternalChange = false
        
        init(_ parent: MarkdownEditor) {
            self.parent = parent
        }
        
        func textViewDidChange(_ textView: UITextView) {
            isInternalChange = true
            parent.text = textView.text ?? ""
        }
    }
}
