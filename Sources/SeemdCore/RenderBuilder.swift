import Foundation
import Markdown

/// Walks a parsed swift-markdown AST and produces the pure `RenderBlock`
/// model. No UI types are involved; the result is fully `Equatable` and
/// self-testable.
public enum RenderBuilder {
    /// Build the render model for `doc`.
    ///
    /// Heading slugs are taken from `doc.headings` (the same de-duplicated,
    /// GitHub-style slugs used for TOC navigation) by consuming them in
    /// document order, so anchors stay in sync with the table of contents.
    public static func build(_ doc: MarkdownDocument) -> [RenderBlock] {
        let slugs = doc.headings.map { $0.slug }
        var slugIndex = 0
        func nextSlug() -> String {
            guard slugIndex < slugs.count else { return "" }
            defer { slugIndex += 1 }
            return slugs[slugIndex]
        }
        return blocks(from: Array(doc.document.children), nextSlug: nextSlug)
    }

    // MARK: - Block walking

    private static func blocks(from markups: [Markup],
                               nextSlug: () -> String) -> [RenderBlock] {
        var out: [RenderBlock] = []
        for markup in markups {
            if let b = block(from: markup, nextSlug: nextSlug) {
                out.append(b)
            }
        }
        return out
    }

    private static func block(from markup: Markup,
                              nextSlug: () -> String) -> RenderBlock? {
        switch markup {
        case let heading as Markdown.Heading:
            return .heading(level: heading.level,
                            slug: nextSlug(),
                            inlines: inlines(from: heading))

        case let paragraph as Markdown.Paragraph:
            return .paragraph(inlines(from: paragraph))

        case let code as Markdown.CodeBlock:
            // `language` is the fenced info string; nil/empty -> nil.
            let lang = code.language.flatMap { $0.isEmpty ? nil : $0 }
            return .codeBlock(language: lang, code: code.code)

        case let quote as Markdown.BlockQuote:
            return .blockQuote(blocks(from: Array(quote.children),
                                      nextSlug: nextSlug))

        case let list as Markdown.UnorderedList:
            return .unorderedList(listItems(list, nextSlug: nextSlug))

        case let list as Markdown.OrderedList:
            let start = Int(list.startIndex)
            return .orderedList(start: start,
                                items: listItems(list, nextSlug: nextSlug))

        case let table as Markdown.Table:
            return tableBlock(table)

        case is Markdown.ThematicBreak:
            return .thematicBreak

        case let html as Markdown.HTMLBlock:
            // Render raw HTML as a literal paragraph of text.
            return .paragraph([.text(html.rawHTML)])

        default:
            // Unknown container: recurse children; if none, fall back to
            // its inline plain text as a paragraph.
            let children = Array(markup.children)
            if !children.isEmpty {
                let nested = blocks(from: children, nextSlug: nextSlug)
                if nested.count == 1 { return nested[0] }
                if !nested.isEmpty { return .blockQuote(nested) }
            }
            let text = MarkdownDocument.inlinePlainText(markup)
            return text.isEmpty ? nil : .paragraph([.text(text)])
        }
    }

    /// Map a list's items to their child block arrays, splitting out GFM
    /// task-list items into `.taskListItem` wrappers.
    private static func listItems(_ list: ListItemContainer,
                                  nextSlug: () -> String) -> [[RenderBlock]] {
        var items: [[RenderBlock]] = []
        for case let item as Markdown.ListItem in list.children {
            let childBlocks = blocks(from: Array(item.children),
                                     nextSlug: nextSlug)
            if let checkbox = item.checkbox {
                items.append([.taskListItem(checked: checkbox == .checked,
                                            blocks: childBlocks)])
            } else {
                items.append(childBlocks)
            }
        }
        return items
    }

    private static func tableBlock(_ table: Markdown.Table) -> RenderBlock {
        let alignments: [ColumnAlignment] = table.columnAlignments.map {
            switch $0 {
            case .some(.left): return .left
            case .some(.center): return .center
            case .some(.right): return .right
            case nil: return .none
            }
        }

        let header: [[InlineNode]] = table.head.cells.map { inlines(from: $0) }

        var rows: [[[InlineNode]]] = []
        for row in table.body.rows {
            rows.append(row.cells.map { inlines(from: $0) })
        }

        return .table(header: header, rows: rows, alignments: alignments)
    }

    // MARK: - Inline walking

    private static func inlines(from container: Markup) -> [InlineNode] {
        container.children.flatMap { inlineNodes(from: $0) }
    }

    private static func inlineNodes(from markup: Markup) -> [InlineNode] {
        switch markup {
        case let text as Markdown.Text:
            return [.text(text.string)]

        case let code as Markdown.InlineCode:
            return [.code(code.code)]

        case let emphasis as Markdown.Emphasis:
            return [.emphasis(inlines(from: emphasis))]

        case let strong as Markdown.Strong:
            return [.strong(inlines(from: strong))]

        case let strike as Markdown.Strikethrough:
            return [.strikethrough(inlines(from: strike))]

        case let link as Markdown.Link:
            return [.link(text: inlines(from: link),
                          destination: link.destination ?? "")]

        case let image as Markdown.Image:
            return [.image(alt: MarkdownDocument.inlinePlainText(image),
                           source: image.source ?? "")]

        case is Markdown.LineBreak, is Markdown.SoftBreak:
            return [.lineBreak]

        case let html as Markdown.InlineHTML:
            return [.text(html.rawHTML)]

        default:
            // Unknown inline: recurse children, else use plain text.
            let children = Array(markup.children)
            if !children.isEmpty {
                return children.flatMap { inlineNodes(from: $0) }
            }
            let text = MarkdownDocument.inlinePlainText(markup)
            return text.isEmpty ? [] : [.text(text)]
        }
    }
}
