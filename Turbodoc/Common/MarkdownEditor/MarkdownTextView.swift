import UIKit

class MarkdownTextView: UITextView {
    private let markdownStorage = MarkdownTextStorage()
    
    // External delegate to forward UITextViewDelegate methods
    weak var externalDelegate: UITextViewDelegate?
    
    override init(frame: CGRect, textContainer: NSTextContainer?) {
        // Create the text system components
        let layoutManager = NSLayoutManager()
        markdownStorage.addLayoutManager(layoutManager)
        
        let container = textContainer ?? NSTextContainer()
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        
        super.init(frame: frame, textContainer: container)
        
        setupTextView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTextView()
    }
    
    private func setupTextView() {
        font = .systemFont(ofSize: 17)
        textColor = .label
        backgroundColor = .systemBackground
        autocorrectionType = .default
        autocapitalizationType = .sentences
        keyboardType = .default
        returnKeyType = .default
        enablesReturnKeyAutomatically = false
        
        // Important for smooth typing
        layoutManager.allowsNonContiguousLayout = true
        
        // Set self as the delegate to intercept calls
        delegate = self
    }
    
    // Helper to get/set plain markdown text
    var markdownText: String {
        get { return text ?? "" }
        set { text = newValue }
    }
}

// MARK: - UITextViewDelegate
extension MarkdownTextView: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // Handle list continuation on Enter key
        if text == "\n" {
            let currentText = textView.text as NSString
            let lineRange = currentText.lineRange(for: range)
            let lineText = currentText.substring(with: lineRange)
            
            // Check for unordered list markers (-, *, +)
            let unorderedListPattern = "^(\\s*)([-*+])\\s+(.*)$"
            if let regex = try? NSRegularExpression(pattern: unorderedListPattern, options: []),
               let match = regex.firstMatch(in: lineText, options: [], range: NSRange(location: 0, length: lineText.count)) {
                
                let indentRange = match.range(at: 1)
                let markerRange = match.range(at: 2)
                let contentRange = match.range(at: 3)
                
                let indent = (lineText as NSString).substring(with: indentRange)
                let marker = (lineText as NSString).substring(with: markerRange)
                let content = (lineText as NSString).substring(with: contentRange)
                
                // If the line has no content (empty list item), remove the marker
                if content.trimmingCharacters(in: .whitespaces).isEmpty {
                    textView.text = (currentText.replacingCharacters(in: lineRange, with: "\n") as NSString) as String
                    textView.selectedRange = NSRange(location: lineRange.location + 1, length: 0)
                    externalDelegate?.textViewDidChange?(textView)
                    return false
                }
                
                // Insert new list item with same marker
                let newListItem = "\n\(indent)\(marker) "
                textView.insertText(newListItem)
                externalDelegate?.textViewDidChange?(textView)
                return false
            }
            
            // Check for ordered list markers (1., 2., etc.)
            let orderedListPattern = "^(\\s*)(\\d+)\\.\\s+(.*)$"
            if let regex = try? NSRegularExpression(pattern: orderedListPattern, options: []),
               let match = regex.firstMatch(in: lineText, options: [], range: NSRange(location: 0, length: lineText.count)) {
                
                let indentRange = match.range(at: 1)
                let numberRange = match.range(at: 2)
                let contentRange = match.range(at: 3)
                
                let indent = (lineText as NSString).substring(with: indentRange)
                let numberStr = (lineText as NSString).substring(with: numberRange)
                let content = (lineText as NSString).substring(with: contentRange)
                
                // If the line has no content (empty list item), remove the marker
                if content.trimmingCharacters(in: .whitespaces).isEmpty {
                    textView.text = (currentText.replacingCharacters(in: lineRange, with: "\n") as NSString) as String
                    textView.selectedRange = NSRange(location: lineRange.location + 1, length: 0)
                    externalDelegate?.textViewDidChange?(textView)
                    return false
                }
                
                // Insert new list item with incremented number
                if let number = Int(numberStr) {
                    let newListItem = "\n\(indent)\(number + 1). "
                    textView.insertText(newListItem)
                    externalDelegate?.textViewDidChange?(textView)
                    return false
                }
            }
        }
        
        return externalDelegate?.textView?(textView, shouldChangeTextIn: range, replacementText: text) ?? true
    }
    
    func textViewDidChange(_ textView: UITextView) {
        externalDelegate?.textViewDidChange?(textView)
    }
    
    func textViewDidChangeSelection(_ textView: UITextView) {
        externalDelegate?.textViewDidChangeSelection?(textView)
    }
    
    func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
        return externalDelegate?.textViewShouldBeginEditing?(textView) ?? true
    }
    
    func textViewShouldEndEditing(_ textView: UITextView) -> Bool {
        return externalDelegate?.textViewShouldEndEditing?(textView) ?? true
    }
    
    func textViewDidBeginEditing(_ textView: UITextView) {
        externalDelegate?.textViewDidBeginEditing?(textView)
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        externalDelegate?.textViewDidEndEditing?(textView)
    }
}
