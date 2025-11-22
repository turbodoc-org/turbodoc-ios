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
        // Headers must be applied before lists to prevent indentation from list patterns
        applyHeaders(in: range, nsString: nsString)
        // Lists must be applied before italic to prevent * from being treated as italic
        applyLists(in: range, nsString: nsString)
        applyCodeBlocks(in: range, nsString: nsString)
        applyInlineCode(in: range, nsString: nsString)
        applyBold(in: range, nsString: nsString)
        applyItalic(in: range, nsString: nsString)
        applyStrikethrough(in: range, nsString: nsString)
        applyLinks(in: range, nsString: nsString)
    }
    
    private func applyHeaders(in range: NSRange, nsString: NSString) {
        let headerPattern = "^[ \t]*(#{1,6})(\\s+(.*))?$"
        guard let regex = try? NSRegularExpression(pattern: headerPattern, options: .anchorsMatchLines) else { return }
        
        regex.enumerateMatches(in: nsString as String, options: [], range: range) { match, _, _ in
            guard let match = match else { return }
            
            let fullRange = match.range
            let headerLevel = match.range(at: 1).length
            
            // Get header text range (capture group 3, if it exists)
            let headerTextRange = match.range(at: 3)
            let hasContent = headerTextRange.location != NSNotFound && headerTextRange.length > 0
            
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
            
            // Remove any leading whitespace indentation for headers
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.firstLineHeadIndent = 0
            paragraphStyle.headIndent = 0
            storage.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
            
            // Hide leading whitespace before ##
            let text = nsString.substring(with: fullRange)
            if let hashRange = text.range(of: "#") {
                let leadingWhitespaceLength = text.distance(from: text.startIndex, to: hashRange.lowerBound)
                if leadingWhitespaceLength > 0 {
                    let tinyFont = UIFont.systemFont(ofSize: 0.1)
                    storage.addAttribute(.font, value: tinyFont, range: NSRange(location: fullRange.location, length: leadingWhitespaceLength))
                    storage.addAttribute(.foregroundColor, value: UIColor.clear, range: NSRange(location: fullRange.location, length: leadingWhitespaceLength))
                }
            }
            
            // Hide the ## markers with a tiny font so they don't take up space
            let tinyFont = UIFont.systemFont(ofSize: 0.1)
            storage.addAttribute(.font, value: tinyFont, range: match.range(at: 1))
            storage.addAttribute(.foregroundColor, value: UIColor.clear, range: match.range(at: 1))
            
            // Apply header font to space and content after ##
            if match.range(at: 2).location != NSNotFound && match.range(at: 2).length > 0 {
                let spaceAndContentRange = match.range(at: 2)
                
                // Apply header font to the space + content
                storage.addAttribute(.font, value: headerFont, range: spaceAndContentRange)
                
                // Find how many leading spaces there are and hide them
                let spaceContent = nsString.substring(with: spaceAndContentRange)
                var spaceCount = 0
                for char in spaceContent {
                    if char == " " || char == "\t" {
                        spaceCount += 1
                    } else {
                        break
                    }
                }
                
                if spaceCount > 0 {
                    let spacesRange = NSRange(location: spaceAndContentRange.location, length: spaceCount)
                    storage.addAttribute(.foregroundColor, value: UIColor.clear, range: spacesRange)
                }
                
                // Style the content text
                if hasContent {
                    storage.addAttribute(.foregroundColor, value: UIColor.label, range: headerTextRange)
                }
            }
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
        // Pattern for **bold** or __bold__
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
        // Pattern that avoids matching asterisks at the start of lines (list markers)
        // E.g. *italic* but not list markers like * item
        let italicPattern = "(?<!\\*)(?<!^\\s*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)|(?<!_)_(?!_)(.+?)(?<!_)_(?!_)"
        guard let regex = try? NSRegularExpression(pattern: italicPattern, options: .anchorsMatchLines) else { return }
        
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
        let unorderedListPattern = "^([\\s]*)([-+])\\s+(.*)$"
        if let regex = try? NSRegularExpression(pattern: unorderedListPattern, options: .anchorsMatchLines) {
            regex.enumerateMatches(in: nsString as String, options: [], range: range) { match, _, _ in
                guard let match = match else { return }
                
                let fullRange = match.range
                
                // Apply consistent indentation for all list items
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.firstLineHeadIndent = 20
                paragraphStyle.headIndent = 20
                storage.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
            }
        }
        
        // Ordered lists
        let orderedListPattern = "^([\\s]*)(\\d+)\\.\\s+(.*)$"
        if let regex = try? NSRegularExpression(pattern: orderedListPattern, options: .anchorsMatchLines) {
            regex.enumerateMatches(in: nsString as String, options: [], range: range) { match, _, _ in
                guard let match = match else { return }
                
                let fullRange = match.range
                
                // Apply consistent indentation for all numbered items
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.firstLineHeadIndent = 20
                paragraphStyle.headIndent = 20
                storage.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
            }
        }
    }
}
