import Foundation
import Markdown

/// Parsed Markdown source plus derived navigation metadata.
///
/// Wraps swift-markdown's `Document` and extracts an ordered list of
/// headings with GitHub-style, de-duplicated slugs suitable for in-page
/// anchor navigation.
public struct MarkdownDocument {
    /// A heading discovered while walking the parsed AST.
    public struct Heading {
        /// Heading level, 1...6 (ATX `#`..`######` / Setext 1..2).
        public let level: Int
        /// Plain-text content of the heading (inline formatting stripped).
        public let text: String
        /// GitHub-style anchor slug, de-duplicated across the document.
        public let slug: String

        public init(level: Int, text: String, slug: String) {
            self.level = level
            self.text = text
            self.slug = slug
        }
    }

    /// The raw source the document was parsed from.
    public let source: String

    /// The parsed swift-markdown abstract syntax tree.
    public let document: Document

    /// Parse `source` into a Markdown document.
    public init(_ source: String) {
        self.source = source
        self.document = Document(parsing: source)
    }

    /// All headings in document order with de-duplicated GitHub-style slugs.
    public var headings: [Heading] {
        var result: [Heading] = []
        var slugCounts: [String: Int] = [:]

        for markup in Self.depthFirst(document) {
            guard let heading = markup as? Markdown.Heading else { continue }
            let text = Self.inlinePlainText(heading)
            let base = Self.slugify(text)
            let slug: String
            if let count = slugCounts[base] {
                slugCounts[base] = count + 1
                slug = "\(base)-\(count)"
            } else {
                slugCounts[base] = 1
                slug = base
            }
            result.append(Heading(level: heading.level, text: text, slug: slug))
        }
        return result
    }

    /// Depth-first, document-order traversal of every node in the tree.
    static func depthFirst(_ root: Markup) -> [Markup] {
        var out: [Markup] = []
        func visit(_ node: Markup) {
            out.append(node)
            for child in node.children { visit(child) }
        }
        for child in root.children { visit(child) }
        return out
    }

    /// Inline plain text with formatting stripped.
    ///
    /// `Markup.plainText` does not unwrap `InlineCode` (it carries its text in
    /// a `code` property, not child `Text` nodes) and swift-markdown's
    /// `Strikethrough.plainText` can retain delimiter tildes. This walks the
    /// inline tree and emits clean reading text for TOC labels.
    static func inlinePlainText(_ node: Markup) -> String {
        switch node {
        case let text as Markdown.Text:
            return text.string
        case let code as Markdown.InlineCode:
            return code.code
        case let html as Markdown.InlineHTML:
            return html.rawHTML
        case is Markdown.LineBreak, is Markdown.SoftBreak:
            return " "
        default:
            return node.children.map { inlinePlainText($0) }.joined()
        }
    }

    /// GitHub-style slug: lowercase, spaces -> '-', drop chars not [a-z0-9-].
    static func slugify(_ text: String) -> String {
        var slug = ""
        for scalar in text.lowercased().unicodeScalars {
            switch scalar {
            case " ", "\t", "\n":
                slug.append("-")
            case "a"..."z", "0"..."9", "-":
                slug.unicodeScalars.append(scalar)
            default:
                break
            }
        }
        return slug
    }
}
