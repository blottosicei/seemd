import SwiftUI
import SeemdCore

/// Builds `AttributedString` runs from `[InlineNode]`, applying GitHub-style
/// typography and optional search-match highlighting. Images are surfaced
/// separately so the block layer can render them as views.
struct InlineRenderer {
    let palette: ThemePalette
    let baseFontSize: CGFloat
    /// Lowercased search query; empty disables highlighting.
    let searchQuery: String
    /// Directory used to resolve relative local image paths.
    let baseDirectory: URL?
    /// Base font weight for plain runs. Body text is `.regular`; heading
    /// renderers pass `.semibold`/`.bold` so the weight is baked into the
    /// `AttributedString` runs (run-level font overrides the `Text` modifier,
    /// so the weight/size MUST come from here for headings to render correctly).
    var baseWeight: Font.Weight = .regular

    private var bodyColor: Color { Color(hex: palette.bodyText, fallback: .primary) }
    private var linkColor: Color { Color(hex: palette.accentLink, fallback: .accentColor) }
    private var codeBG: Color { Color(hex: palette.codeBackground, fallback: Color.gray.opacity(0.15)) }

    // MARK: - Attributed text

    /// Render inline nodes to a single `AttributedString` (images become their
    /// alt text — use `images(in:)` to lay them out as views).
    func attributed(_ nodes: [InlineNode]) -> AttributedString {
        var result = AttributedString()
        for node in nodes {
            result.append(render(node, bold: false, italic: false, strike: false))
        }
        return applySearchHighlight(result)
    }

    /// Collects image nodes (alt, resolved URL) found at the top level.
    func images(in nodes: [InlineNode]) -> [(alt: String, url: URL?)] {
        nodes.compactMap { node in
            if case let .image(alt, source) = node {
                return (alt, resolveImageURL(source))
            }
            return nil
        }
    }

    /// True if these inline nodes are exactly a single image.
    func isLoneImage(_ nodes: [InlineNode]) -> Bool {
        nodes.count == 1 && { if case .image = nodes[0] { return true } else { return false } }()
    }

    // MARK: - Recursion

    private func render(_ node: InlineNode,
                        bold: Bool,
                        italic: Bool,
                        strike: Bool) -> AttributedString {
        switch node {
        case .text(let s):
            return styled(s, bold: bold, italic: italic, strike: strike)

        case .code(let s):
            var a = AttributedString(s)
            a.font = .system(size: baseFontSize * 0.92, design: .monospaced)
            a.backgroundColor = codeBG
            a.foregroundColor = bodyColor
            return a

        case .emphasis(let children):
            return concat(children, bold: bold, italic: true, strike: strike)

        case .strong(let children):
            return concat(children, bold: true, italic: italic, strike: strike)

        case .strikethrough(let children):
            return concat(children, bold: bold, italic: italic, strike: true)

        case .link(let text, let destination):
            var a = concat(text, bold: bold, italic: italic, strike: strike)
            a.foregroundColor = linkColor
            if let url = URL(string: destination) {
                a.link = url
            }
            return a

        case .image(let alt, _):
            // Inline (non-lone) images fall back to their alt text.
            return styled(alt.isEmpty ? "" : alt,
                          bold: bold, italic: italic, strike: strike)

        case .lineBreak:
            return AttributedString("\n")
        }
    }

    private func concat(_ nodes: [InlineNode],
                        bold: Bool,
                        italic: Bool,
                        strike: Bool) -> AttributedString {
        var out = AttributedString()
        for n in nodes {
            out.append(render(n, bold: bold, italic: italic, strike: strike))
        }
        return out
    }

    private func styled(_ string: String,
                        bold: Bool,
                        italic: Bool,
                        strike: Bool) -> AttributedString {
        var a = AttributedString(string)
        // Bold inline goes one step heavier than the run's base weight, so a
        // body `**word**` is semibold while bold text inside an already-bold
        // heading reads as truly bold.
        let weight: Font.Weight = bold
            ? (baseWeight == .regular ? .semibold : .bold)
            : baseWeight
        var font = Font.system(size: baseFontSize, weight: weight)
        if italic { font = font.italic() }
        a.font = font
        a.foregroundColor = bodyColor
        if strike { a.strikethroughStyle = .single }
        return a
    }

    // MARK: - Search highlight

    private func applySearchHighlight(_ input: AttributedString) -> AttributedString {
        guard !searchQuery.isEmpty else { return input }
        var attr = input
        let plain = String(attr.characters)
        let ranges = SearchEngine.matches(in: plain, query: searchQuery)
        guard !ranges.isEmpty else { return attr }

        for r in ranges {
            let lower = plain.distance(from: plain.startIndex, to: r.lowerBound)
            let upper = plain.distance(from: plain.startIndex, to: r.upperBound)
            guard let start = attr.index(attr.startIndex,
                                         offsetByCharacters: lower,
                                         limitedBy: attr.endIndex),
                  let end = attr.index(attr.startIndex,
                                       offsetByCharacters: upper,
                                       limitedBy: attr.endIndex)
            else { continue }
            attr[start..<end].backgroundColor = .yellow.opacity(0.45)
        }
        return attr
    }

    // MARK: - Image URL resolution

    private func resolveImageURL(_ source: String) -> URL? {
        if let url = URL(string: source),
           let scheme = url.scheme,
           scheme == "http" || scheme == "https" {
            return url
        }
        // Local path: resolve relative to the document directory.
        if source.hasPrefix("/") {
            return URL(fileURLWithPath: source)
        }
        if let baseDirectory {
            return baseDirectory.appendingPathComponent(source)
        }
        return URL(string: source)
    }
}

private extension AttributedString {
    func index(_ base: AttributedString.Index,
               offsetByCharacters distance: Int,
               limitedBy limit: AttributedString.Index) -> AttributedString.Index? {
        characters.index(base, offsetBy: distance, limitedBy: limit)
    }
}
