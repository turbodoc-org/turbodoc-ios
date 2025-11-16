import UIKit

class MarkdownTextStorage: NSTextStorage {
    private let storage = NSMutableAttributedString()
    
    override var string: String {
        return storage.string
    }
    
    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key : Any] {
        return storage.attributes(at: location, effectiveRange: range)
    }
    
    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        storage.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range, changeInLength: str.count - range.length)
        endEditing()
    }
    
    override func setAttributes(_ attrs: [NSAttributedString.Key : Any]?, range: NSRange) {
        beginEditing()
        storage.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }
    
    override func processEditing() {
        super.processEditing()
        
        if editedMask.contains(.editedCharacters) {
            let extendedRange = NSString(string: storage.string).paragraphRange(for: editedRange)
            applyMarkdownStyling(in: extendedRange)
        }
    }
    
    private func applyMarkdownStyling(in range: NSRange) {
        let text = storage.string
        let nsString = text as NSString
        
        // Base attributes
        let baseFont = UIFont.systemFont(ofSize: 17)
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: UIColor.label
        ]
        
        storage.setAttributes(baseAttributes, range: range)
        
        // Apply markdown styling in order of precedence
        applyHeaders(in: range, nsString: nsString)
        applyCodeBlocks(in: range, nsString: nsString)
        applyInlineCode(in: range, nsString: nsString)
        applyBold(in: range, nsString: nsString)
        applyItalic(in: range, nsString: nsString)
        applyStrikethrough(in: range, nsString: nsString)
        applyLinks(in: range, nsString: nsString)
        applyLists(in: range, nsString: nsString)
    }
    
    private func applyHeaders(in range: NSRange, nsString: NSString) {
        let headerPattern = "^(#{1,6})\\s+(.+)$"
        guard let regex = try? NSRegularExpression(pattern: headerPattern, options: .anchorsMatchLines) else { return }
        
        regex.enumerateMatches(in: nsString as String, options: [], range: range) { match, _, _ in
            guard let match = match else { return }
            
            let headerLevel = match.range(at: 1).length
            let headerTextRange = match.range(at: 2)
            let fullRange = match.range
            
            // Font size based on header level
            let fontSize: CGFloat = {
                switch headerLevel {
                case 1: return 32
                case 2: return 28
                case 3: return 24
                case 4: return 20
                case 5: return 18
                case 6: return 17
                default: return 17
                }
            }()
            
            let headerFont = UIFont.boldSystemFont(ofSize: fontSize)
            
            // Hide the ## markers
            storage.addAttribute(.foregroundColor, value: UIColor.clear, range: match.range(at: 1))
            storage.addAttribute(.foregroundColor, value: UIColor.clear, range: NSRange(location: match.range(at: 1).upperBound, length: 1))
            
            // Style the header text
            storage.addAttribute(.font, value: headerFont, range: headerTextRange)
            storage.addAttribute(.foregroundColor, value: UIColor.label, range: headerTextRange)
        }
    }
    
    private func applyCodeBlocks(in range: NSRange, nsString: NSString) {
        let codeBlockPattern = "```[\\s\\S]*?```"
        guard let regex = try? NSRegularExpression(pattern: codeBlockPattern, options: []) else { return }
        
        regex.enumerateMatches(in: nsString as String, options: [], range: range) { match, _, _ in
            guard let match = match else { return }
            
            let codeFont = UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)
            storage.addAttribute(.font, value: codeFont, range: match.range)
            storage.addAttribute(.backgroundColor, value: UIColor.systemGray6, range: match.range)
            storage.addAttribute(.foregroundColor, value: UIColor.systemRed, range: match.range)
            
            // Hide the ``` markers
            let text = nsString.substring(with: match.range)
            if text.hasPrefix("```") {
                let startMarkerRange = NSRange(location: match.range.location, length: 3)
                storage.addAttribute(.foregroundColor, value: UIColor.clear, range: startMarkerRange)
            }
            if text.hasSuffix("```") {
                let endMarkerRange = NSRange(location: match.range.upperBound - 3, length: 3)
                storage.addAttribute(.foregroundColor, value: UIColor.clear, range: endMarkerRange)
            }
        }
    }
    
    private func applyInlineCode(in range: NSRange, nsString: NSString) {
        let inlineCodePattern = "`([^`]+)`"
        guard let regex = try? NSRegularExpression(pattern: inlineCodePattern, options: []) else { return }
        
        regex.enumerateMatches(in: nsString as String, options: [], range: range) { match, _, _ in
            guard let match = match else { return }
            
            let codeFont = UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)
            storage.addAttribute(.font, value: codeFont, range: match.range)
            storage.addAttribute(.backgroundColor, value: UIColor.systemGray6, range: match.range)
            storage.addAttribute(.foregroundColor, value: UIColor.systemRed, range: match.range)
            
            // Hide the backticks
            storage.addAttribute(.foregroundColor, value: UIColor.clear, range: NSRange(location: match.range.location, length: 1))
            storage.addAttribute(.foregroundColor, value: UIColor.clear, range: NSRange(location: match.range.upperBound - 1, length: 1))
        }
    }
    
    private func applyBold(in range: NSRange, nsString: NSString) {
        let boldPattern = "\\*\\*(.+?)\\*\\*|__(.+?)__"
        guard let regex = try? NSRegularExpression(pattern: boldPattern, options: []) else { return }
        
        regex.enumerateMatches(in: nsString as String, options: [], range: range) { match, _, _ in
            guard let match = match else { return }
            
            let boldFont = UIFont.boldSystemFont(ofSize: 17)
            storage.addAttribute(.font, value: boldFont, range: match.range)
            
            // Hide the ** or __ markers
            let text = nsString.substring(with: match.range)
            if text.hasPrefix("**") {
                storage.addAttribute(.foregroundColor, value: UIColor.clear, range: NSRange(location: match.range.location, length: 2))
                storage.addAttribute(.foregroundColor, value: UIColor.clear, range: NSRange(location: match.range.upperBound - 2, length: 2))
            } else if text.hasPrefix("__") {
                storage.addAttribute(.foregroundColor, value: UIColor.clear, range: NSRange(location: match.range.location, length: 2))
                storage.addAttribute(.foregroundColor, value: UIColor.clear, range: NSRange(location: match.range.upperBound - 2, length: 2))
            }
        }
    }
    
    private func applyItalic(in range: NSRange, nsString: NSString) {
        let italicPattern = "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)|(?<!_)_(?!_)(.+?)(?<!_)_(?!_)"
        guard let regex = try? NSRegularExpression(pattern: italicPattern, options: []) else { return }
        
        regex.enumerateMatches(in: nsString as String, options: [], range: range) { match, _, _ in
            guard let match = match else { return }
            
            let italicFont = UIFont.italicSystemFont(ofSize: 17)
            storage.addAttribute(.font, value: italicFont, range: match.range)
            
            // Hide the * or _ markers
            storage.addAttribute(.foregroundColor, value: UIColor.clear, range: NSRange(location: match.range.location, length: 1))
            storage.addAttribute(.foregroundColor, value: UIColor.clear, range: NSRange(location: match.range.upperBound - 1, length: 1))
        }
    }
    
    private func applyStrikethrough(in range: NSRange, nsString: NSString) {
        let strikethroughPattern = "~~(.+?)~~"
        guard let regex = try? NSRegularExpression(pattern: strikethroughPattern, options: []) else { return }
        
        regex.enumerateMatches(in: nsString as String, options: [], range: range) { match, _, _ in
            guard let match = match else { return }
            
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: match.range)
            storage.addAttribute(.strikethroughColor, value: UIColor.label, range: match.range)
            
            // Hide the ~~ markers
            storage.addAttribute(.foregroundColor, value: UIColor.clear, range: NSRange(location: match.range.location, length: 2))
            storage.addAttribute(.foregroundColor, value: UIColor.clear, range: NSRange(location: match.range.upperBound - 2, length: 2))
        }
    }
    
    private func applyLinks(in range: NSRange, nsString: NSString) {
        let linkPattern = "\\[(.+?)\\]\\((.+?)\\)"
        guard let regex = try? NSRegularExpression(pattern: linkPattern, options: []) else { return }
        
        regex.enumerateMatches(in: nsString as String, options: [], range: range) { match, _, _ in
            guard let match = match else { return }
            
            let linkTextRange = match.range(at: 1)
            let urlRange = match.range(at: 2)
            let url = nsString.substring(with: urlRange)
            
            // Style the link text
            storage.addAttribute(.foregroundColor, value: UIColor.systemBlue, range: linkTextRange)
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: linkTextRange)
            storage.addAttribute(.link, value: url, range: linkTextRange)
            
            // Hide the markdown syntax
            storage.addAttribute(.foregroundColor, value: UIColor.clear, range: NSRange(location: match.range.location, length: 1)) // [
            storage.addAttribute(.foregroundColor, value: UIColor.clear, range: NSRange(location: linkTextRange.upperBound, length: 2)) // ](
            storage.addAttribute(.foregroundColor, value: UIColor.clear, range: urlRange)
            storage.addAttribute(.foregroundColor, value: UIColor.clear, range: NSRange(location: match.range.upperBound - 1, length: 1)) // )
        }
    }
    
    private func applyLists(in range: NSRange, nsString: NSString) {
        // Unordered lists
        let unorderedListPattern = "^[\\s]*[-*+]\\s+(.+)$"
        if let regex = try? NSRegularExpression(pattern: unorderedListPattern, options: .anchorsMatchLines) {
            regex.enumerateMatches(in: nsString as String, options: [], range: range) { match, _, _ in
                guard let match = match else { return }
                
                let fullRange = match.range
                let bulletRange = NSRange(location: fullRange.location, length: 2)
                
                // Hide the markdown bullet
                storage.addAttribute(.foregroundColor, value: UIColor.clear, range: bulletRange)
                
                // Add a styled bullet
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.firstLineHeadIndent = 0
                paragraphStyle.headIndent = 20
                storage.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
            }
        }
        
        // Ordered lists
        let orderedListPattern = "^[\\s]*(\\d+)\\.\\s+(.+)$"
        if let regex = try? NSRegularExpression(pattern: orderedListPattern, options: .anchorsMatchLines) {
            regex.enumerateMatches(in: nsString as String, options: [], range: range) { match, _, _ in
                guard let match = match else { return }
                
                let fullRange = match.range
                let numberRange = match.range(at: 1)
                let dotSpaceRange = NSRange(location: numberRange.upperBound, length: 2)
                
                // Hide the dot and space
                storage.addAttribute(.foregroundColor, value: UIColor.clear, range: dotSpaceRange)
                
                // Add indentation
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.firstLineHeadIndent = 0
                paragraphStyle.headIndent = 25
                storage.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
            }
        }
    }
}
