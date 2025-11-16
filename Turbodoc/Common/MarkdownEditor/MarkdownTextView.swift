import UIKit

class MarkdownTextView: UITextView {
    private let markdownStorage = MarkdownTextStorage()
    
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
    }
    
    // Helper to get/set plain markdown text
    var markdownText: String {
        get { return text ?? "" }
        set { text = newValue }
    }
}
