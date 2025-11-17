import SwiftUI
import UIKit

struct MarkdownEditor: UIViewRepresentable {
    @Binding var text: String
    
    func makeUIView(context: Context) -> MarkdownTextView {
        let textView = MarkdownTextView()
        textView.markdownDelegate = context.coordinator
        return textView
    }
    
    func updateUIView(_ uiView: MarkdownTextView, context: Context) {
        // Only update if the text has actually changed to avoid cursor jumping
        if uiView.markdownText != text {
            uiView.markdownText = text
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
            DispatchQueue.main.async {
                self.parent.text = textView.text ?? ""
            }
        }
    }
}
