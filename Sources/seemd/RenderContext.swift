import SwiftUI
import SeemdCore

/// `ThemePalette` is a SeemdCore value type of HEX strings. Conform it to
/// `Equatable` in the app layer so `RenderContext` can diff cheaply without
/// modifying SeemdCore.
extension ThemePalette: Equatable {
    public static func == (lhs: ThemePalette, rhs: ThemePalette) -> Bool {
        lhs.windowBackground == rhs.windowBackground &&
        lhs.bodyText == rhs.bodyText &&
        lhs.secondaryText == rhs.secondaryText &&
        lhs.accentLink == rhs.accentLink &&
        lhs.codeBackground == rhs.codeBackground &&
        lhs.separator == rhs.separator
    }
}

/// Immutable, value-typed rendering inputs handed to `BlockView` and friends.
///
/// This is the linchpin of the performance fix: `BlockView` used to hold an
/// `@ObservedObject DocumentModel`, so *every* `@Published` mutation — including
/// the per-frame `activeHeadingSlug` writes driven by scroll-spy — invalidated
/// the entire rendered block tree (rebuilding every `AttributedString` and
/// allocating a fresh `InlineRenderer` per block). By passing this `Equatable`
/// value instead, scroll-spy / `scrollTarget` / `activeHeadingSlug` mutations no
/// longer touch the block tree, and SwiftUI can skip untouched rows.
struct RenderContext: Equatable {
    let palette: ThemePalette
    let baseFontSize: CGFloat
    let searchQuery: String
    let baseDirectory: URL?
    let isDark: Bool

    /// Build the `InlineRenderer` from the context (was previously derived
    /// from the model directly inside `BlockView`).
    var renderer: InlineRenderer {
        InlineRenderer(
            palette: palette,
            baseFontSize: baseFontSize,
            searchQuery: searchQuery,
            baseDirectory: baseDirectory
        )
    }

    /// A renderer at a specific size/weight (used for headings, whose size and
    /// weight must be baked into the runs — see `InlineRenderer.baseWeight`).
    func renderer(fontSize: CGFloat, weight: Font.Weight) -> InlineRenderer {
        InlineRenderer(
            palette: palette,
            baseFontSize: fontSize,
            searchQuery: searchQuery,
            baseDirectory: baseDirectory,
            baseWeight: weight
        )
    }
}

/// Async syntax-highlight provider closure passed by value to `CodeBlockView`.
/// Bound to `DocumentModel.highlightedTokens` by `DocumentView` so the code
/// block never observes the whole model.
typealias HighlightProvider =
    (_ code: String, _ language: String?,
     _ completion: @escaping ([HighlightToken]) -> Void) -> Void
