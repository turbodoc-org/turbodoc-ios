import SwiftUI

/// A lightweight rendering of the start of a Markdown note for card previews:
/// headings, bullets, checklists and code blocks. Not a full Markdown parser;
/// just enough to make a note recognisable at a glance.
struct MarkdownPreview: View {
    let blocks: [MarkdownPreviewBlock]
    
    init(markdown: String, maxBlocks: Int = 6) {
        blocks = MarkdownPreviewBlock.parse(markdown, limit: maxBlocks)
    }
    
    var body: some View {
        MarkdownPreviewBlocks(blocks: blocks)
    }
}

/// Renders already-parsed preview blocks.
struct MarkdownPreviewBlocks: View {
    let blocks: [MarkdownPreviewBlock]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    @ViewBuilder
    private func blockView(_ block: MarkdownPreviewBlock) -> some View {
        switch block {
        case .heading(let text):
            Text(text)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.thumbInk)
                .lineLimit(2)
        case .paragraph(let text):
            Text(text)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.thumbText)
                .lineLimit(3)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("•")
                Text(text).lineLimit(2)
            }
            .font(.system(size: 10.5))
            .foregroundStyle(Theme.thumbText)
        case .task(let text, let done):
            HStack(spacing: 6) {
                Image(systemName: done ? "checkmark.square.fill" : "square")
                    .font(.system(size: 11))
                    .foregroundStyle(done ? Color.accentColor : Theme.faint)
                Text(text)
                    .strikethrough(done)
                    .opacity(done ? 0.7 : 1)
                    .lineLimit(1)
            }
            .font(.system(size: 10.5))
            .foregroundStyle(Theme.thumbText)
        case .code(let text):
            Text(text)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Theme.codeInk)
                .lineLimit(4)
                .padding(.horizontal, 7)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.thumbLine))
        }
    }
}

enum MarkdownPreviewBlock: Equatable {
    case heading(String)
    case paragraph(String)
    case bullet(String)
    case task(String, done: Bool)
    case code(String)

    static func parse(_ markdown: String, limit: Int) -> [MarkdownPreviewBlock] {
        var blocks: [MarkdownPreviewBlock] = []
        var codeLines: [String]?

        for rawLine in markdown.components(separatedBy: .newlines) {
            guard blocks.count < limit else { break }
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                if let lines = codeLines {
                    blocks.append(.code(lines.joined(separator: "\n")))
                    codeLines = nil
                } else {
                    codeLines = []
                }
                continue
            }
            if codeLines != nil {
                codeLines?.append(rawLine)
                continue
            }
            // The editor writes empty paragraphs as "<br />".
            guard !line.isEmpty, !isLineBreak(line) else { continue }

            if let task = taskItem(line) {
                blocks.append(.task(task.text, done: task.done))
            } else if line.hasPrefix("#") {
                let text = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { blocks.append(.heading(inline(text))) }
            } else if let bullet = bulletText(line) {
                blocks.append(.bullet(inline(bullet)))
            } else {
                blocks.append(.paragraph(inline(line)))
            }
        }
        if let lines = codeLines, !lines.isEmpty, blocks.count < limit {
            blocks.append(.code(lines.joined(separator: "\n")))
        }
        return blocks
    }

    /// Completed and total checklist items in a note.
    static func taskProgress(in markdown: String) -> (done: Int, total: Int) {
        var done = 0
        var total = 0
        for line in markdown.components(separatedBy: .newlines) {
            guard let task = taskItem(line.trimmingCharacters(in: .whitespaces)) else { continue }
            total += 1
            if task.done { done += 1 }
        }
        return (done, total)
    }

    /// The first line of readable text after the title, for list snippets.
    static func snippet(from markdown: String, excluding title: String?) -> String? {
        for block in parse(markdown, limit: 4) {
            let text: String
            switch block {
            case .heading(let value), .paragraph(let value), .bullet(let value): text = value
            case .task(let value, _): text = value
            case .code: continue
            }
            if text != title { return text }
        }
        return nil
    }

    private static func isLineBreak(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "").lowercased()
        return ["<br>", "<br/>", "</br>"].contains(compact)
    }
    
    private static func taskItem(_ line: String) -> (text: String, done: Bool)? {
        for prefix in ["- [ ]", "* [ ]", "+ [ ]", "- [x]", "* [x]", "+ [x]", "- [X]", "* [X]"] {
            if line.hasPrefix(prefix) {
                let text = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
                return (inline(text), prefix.lowercased().contains("x"))
            }
        }
        return nil
    }

    private static func bulletText(_ line: String) -> String? {
        for prefix in ["- ", "* ", "+ "] where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count))
        }
        if let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber), !line[..<dot].isEmpty {
            return line[line.index(after: dot)...].trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// Strips inline Markdown markers so previews read as plain text.
    private static func inline(_ text: String) -> String {
        var result = text
        // [label](url) -> label
        while let open = result.range(of: "["),
              let close = result.range(of: "](", range: open.upperBound..<result.endIndex),
              let end = result.range(of: ")", range: close.upperBound..<result.endIndex) {
            let label = result[open.upperBound..<close.lowerBound]
            result.replaceSubrange(open.lowerBound..<end.upperBound, with: label)
        }
        for marker in ["**", "__", "`", "~~"] {
            result = result.replacingOccurrences(of: marker, with: "")
        }
        result = result.replacingOccurrences(of: "<br />", with: " ")
            .replacingOccurrences(of: "<br/>", with: " ")
            .replacingOccurrences(of: "<br>", with: " ")
        return result.replacingOccurrences(of: "\\", with: "")
    }
}
