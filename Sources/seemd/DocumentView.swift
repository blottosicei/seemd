import SwiftUI
import SeemdCore

/// The scrollable rendered Markdown surface (no toolbar). Reused both inside
/// `DocumentView` (preview-only mode) and as the right-hand pane of the split
/// editor. Keeps the same `RenderContext` + highlight-closure perf model: it
/// observes the model only for `blocks`/scroll state, never feeding the heavy
/// object into `BlockView`.
///
/// The scroll container is an app-owned `NSScrollView` (`HostedScrollView`),
/// NOT a SwiftUI `ScrollView`: on macOS 14 a SwiftUI `ScrollView` no longer
/// exposes its backing `NSScrollView`, which broke the continuous
/// editor↔preview sync. Hosting the same SwiftUI block content in an
/// `NSScrollView` this app owns makes the sync deterministic (the per-window
/// `ScrollSyncCoordinator` observes/drives the real clip view directly).
struct PreviewPane: View {
    @ObservedObject var model: DocumentModel
    /// Top content clearance. Viewer mode (default) clears the title bar only;
    /// edit mode passes `HostedScrollView.editTopInset` to also clear the
    /// FormatBar row.
    var topPadding: CGFloat = PreviewTopInset.viewer

    @AppStorage(ContentWidthPreferences.widthKey)
    private var contentWidth: Double = ContentWidthPreferences.defaultWidth

    @AppStorage(ContentWidthPreferences.fillKey)
    private var fillWindowWidth: Bool = false

    private var maxContentWidth: CGFloat {
        if fillWindowWidth { return .infinity }
        let clamped = min(max(contentWidth, ContentWidthPreferences.minWidth),
                          ContentWidthPreferences.maxWidth)
        return CGFloat(clamped)
    }

    private var renderContext: RenderContext {
        RenderContext(
            palette: model.palette,
            baseFontSize: 16.0 * CGFloat(model.zoom),
            searchQuery: model.searchQuery,
            baseDirectory: model.documentDirectory,
            isDark: model.effectiveTheme == .dark
        )
    }

    var body: some View {
        let context = renderContext
        let highlight: HighlightProvider = { code, language, completion in
            model.highlightedTokens(code: code, language: language,
                                    completion: completion)
        }
        return HostedScrollView(
            maxContentWidth: maxContentWidth,
            topPadding: topPadding,
            backgroundHex: model.palette.windowBackground,
            coordinator: model.scrollSync
        ) {
            // Regular VStack (NOT LazyVStack): a LazyVStack does not report a
            // finite intrinsic height to the enclosing NSHostingView, so the
            // app-owned NSScrollView's documentView would collapse to the clip
            // height and never become scrollable. Per-block BlockView is still
            // cheap and RenderContext+closure decoupled (no .drawingGroup()).
            VStack(alignment: .leading, spacing: 14) {
                ForEach(model.blocks.indices, id: \.self) { i in
                    BlockView(block: model.blocks[i],
                              context: context,
                              highlight: highlight)
                }
            }
            .onPreferenceChange(HeadingFramePreferenceKey.self) { frames in
                // Feed per-heading content-Y to the continuous coordinator
                // (editor↔preview offset interpolation) AND the clip-offset
                // scroll-spy table. Scroll-spy itself is NO LONGER driven from
                // this PreferenceKey: the hosted SwiftUI content does not move
                // in its own coordinate space when the NSScrollView scrolls
                // (the clip view moves), so `onPreferenceChange` never re-fires
                // on scroll. `ScrollSyncCoordinator.previewScrollSpy()` now
                // derives `activeHeadingSlug` from the real clip offset on
                // every `boundsDidChange` (works in both viewer + edit mode).
                model.scrollSync.updatePreviewHeadingFrames(frames)
            }
        }
        .onChange(of: model.scrollTarget) {
            guard let target = model.scrollTarget else { return }
            // Preview-only mode (TOC sidebar click) + live-reload scroll
            // preservation. The hosted NSScrollView is scrolled to the
            // heading's content-Y via the same preview heading-Y table the
            // continuous sync uses. NOT the live editor↔preview sync (that
            // path no longer reads `scrollTarget`). The resulting clip
            // `boundsDidChange` lets the coordinator's scroll-spy re-derive
            // the active heading to match the scrolled-to target.
            model.scrollSync.scrollPreview(toHeadingSlug: target)
            if model.scrollTarget != nil { model.scrollTarget = nil }
        }
    }
}

/// The scrollable rendered Markdown surface plus the find toolbar (preview-only
/// mode detail pane).
/// Preview-only surface. The search field lives in `RootView`'s consolidated
/// toolbar so toolbar ordering (search → … → edit toggle) is deterministic.
struct DocumentView: View {
    @ObservedObject var model: DocumentModel

    var body: some View {
        PreviewPane(model: model)
    }
}
