import SwiftUI
import SeemdCore

/// The scrollable rendered Markdown surface (no toolbar). Reused both inside
/// `DocumentView` (preview-only mode) and as the right-hand pane of the split
/// editor. Keeps the same `RenderContext` + highlight-closure perf model: it
/// observes the model only for `blocks`/scroll state, never feeding the heavy
/// object into `BlockView`.
struct PreviewPane: View {
    @ObservedObject var model: DocumentModel

    @AppStorage(ContentWidthPreferences.widthKey)
    private var contentWidth: Double = ContentWidthPreferences.defaultWidth

    @AppStorage(ContentWidthPreferences.fillKey)
    private var fillWindowWidth: Bool = false

    @State private var suppressSpyUntil: Date = .distantPast

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
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(model.blocks.indices, id: \.self) { i in
                        BlockView(block: model.blocks[i],
                                  context: context,
                                  highlight: highlight)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                .frame(maxWidth: maxContentWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .coordinateSpace(name: "docScroll")
            .background(Color(hex: model.palette.windowBackground, fallback: Color(NSColor.textBackgroundColor)))
            // Capture the NSScrollView backing this SwiftUI ScrollView and
            // hand it to the per-window coordinator for continuous offset
            // sync. Inside the ScrollView so `enclosingScrollView` resolves.
            .background(ScrollViewCapture(coordinator: model.scrollSync))
            .onPreferenceChange(HeadingFramePreferenceKey.self) { frames in
                // Feed per-heading content-Y to the continuous coordinator
                // (editor↔preview offset interpolation) AND keep the existing
                // scroll-spy that maintains `activeHeadingSlug` for the TOC.
                model.scrollSync.updatePreviewHeadingFrames(frames)
                updateActiveHeading(frames)
            }
            .onChange(of: model.scrollTarget) {
                guard let target = model.scrollTarget else { return }
                suppressSpyUntil = Date().addingTimeInterval(0.25)
                proxy.scrollTo(target, anchor: .top)
                if model.scrollTarget != nil { model.scrollTarget = nil }
            }
        }
    }

    /// Scroll-spy: delegates to the pure `ScrollSpy.activeSlug` function in
    /// SeemdCore, using a 12-pt inset to match the previous threshold behaviour.
    private func updateActiveHeading(_ frames: [AppHeadingFrame]) {
        guard !frames.isEmpty else { return }
        guard Date() >= suppressSpyUntil else { return }
        // Editor is the active driver: do not let its programmatic preview
        // scroll re-derive an active slug that would bounce back to the editor.
        guard !model.previewSyncSuppressed else { return }
        let coreFrames = frames.map {
            HeadingFrame(slug: $0.slug, minY: Double($0.minY))
        }
        let candidate = ScrollSpy.activeSlug(
            headingFrames: coreFrames,
            viewportTopInset: 12
        )
        if let candidate, candidate != model.activeHeadingSlug {
            model.activeHeadingSlug = candidate
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
