import Foundation

/// Pure, value-typed render model produced from a parsed Markdown AST.
///
/// This is the view-model layer: a structural, `Equatable` description of a
/// document that the SwiftUI app target renders without touching
/// swift-markdown directly. It contains no UI types and is fully testable.

/// An inline (text-flow) node.
public indirect enum InlineNode: Equatable {
    /// Literal text run.
    case text(String)
    /// Inline code span (verbatim).
    case code(String)
    /// Emphasis (`*…*` / `_…_`).
    case emphasis([InlineNode])
    /// Strong emphasis (`**…**` / `__…__`).
    case strong([InlineNode])
    /// GFM strikethrough (`~~…~~`).
    case strikethrough([InlineNode])
    /// Hyperlink with inline label content and a destination URL string.
    case link(text: [InlineNode], destination: String)
    /// Image with alt text and a source URL string.
    case image(alt: String, source: String)
    /// Hard or soft line break, rendered as a space-equivalent break.
    case lineBreak
}

/// Per-column alignment for a GFM table.
public enum ColumnAlignment: Equatable {
    case none
    case left
    case center
    case right
}

/// A block-level node.
public indirect enum RenderBlock: Equatable {
    /// Heading with its de-duplicated GitHub-style anchor slug.
    case heading(level: Int, slug: String, inlines: [InlineNode])
    case paragraph([InlineNode])
    /// Fenced or indented code block; `language` is the fenced info string.
    case codeBlock(language: String?, code: String)
    case blockQuote([RenderBlock])
    /// Unordered list; each element is one item's child blocks.
    case unorderedList([[RenderBlock]])
    /// Ordered list with its starting number; each element is one item's blocks.
    case orderedList(start: Int, items: [[RenderBlock]])
    /// A GFM task-list item (`- [ ]` / `- [x]`).
    case taskListItem(checked: Bool, blocks: [RenderBlock])
    /// A GFM table: header cells, body rows, and per-column alignment.
    case table(header: [[InlineNode]], rows: [[[InlineNode]]], alignments: [ColumnAlignment])
    case thematicBreak
}
