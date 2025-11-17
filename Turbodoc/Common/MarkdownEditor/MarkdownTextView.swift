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
