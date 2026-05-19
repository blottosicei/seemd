import SwiftUI
import SeemdCore

/// The scrollable rendered Markdown surface.
struct DocumentView: View {
    @ObservedObject var model: DocumentModel
    @FocusState private var searchFocused: Bool

    /// Layout-only preferences. Read reactively so changing them in Settings
    /// updates open documents live. Deliberately NOT part of `RenderContext`:
    /// width is the container frame, not a per-block rendering input, so a
    /// change here only re-lays the outer frame — no block re-render storm.
    @AppStorage(ContentWidthPreferences.widthKey)
    private var contentWidth: Double = ContentWidthPreferences.defaultWidth

    @AppStorage(ContentWidthPreferences.fillKey)
    private var fillWindowWidth: Bool = false

    /// Suppress scroll-spy model writes until this time. Set when a
    /// programmatic (TOC-initiated) scroll begins so the per-frame preference
    /// storm during the animated scroll does not thrash `activeHeadingSlug`.
    @State private var suppressSpyUntil: Date = .distantPast

    /// `.infinity` when fill-window is on (content uses full available width
    /// minus the existing horizontal padding); otherwise the clamped width cap.
    private var maxContentWidth: CGFloat {
        if fillWindowWidth { return .infinity }
        let clamped = min(max(contentWidth, ContentWidthPreferences.minWidth),
                          ContentWidthPreferences.maxWidth)
        return CGFloat(clamped)
    }

    private var matchCount: Int {
        guard !model.searchQuery.isEmpty else { return 0 }
        return SearchEngine.matchCount(in: model.source, query: model.searchQuery)
    }

    /// One value-typed render context, recomputed only when palette / zoom /
    /// search / theme / document directory actually change. Passing this (and a
    /// stable highlight closure) into each `BlockView` lets SwiftUI skip
    /// untouched rows and keeps scroll-spy mutations off the block tree.
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
        documentScroll
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Find", text: $model.searchQuery)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
                            .focused($searchFocused)
                        if !model.searchQuery.isEmpty {
                            Text("\(matchCount)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Button {
                                model.searchQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .seemdFocusSearch)) { _ in
                searchFocused = true
            }
    }

    private var documentScroll: some View {
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
            .onPreferenceChange(HeadingFramePreferenceKey.self) { frames in
                updateActiveHeading(frames)
            }
            .onChange(of: model.scrollTarget) {
                guard let target = model.scrollTarget else { return }
                // Suppress scroll-spy writes while the programmatic scroll is
                // in flight so the per-frame preference storm cannot thrash
                // `activeHeadingSlug` (which would re-highlight the TOC and
                // fight the jump). ~250ms covers the scroll settle window.
                suppressSpyUntil = Date().addingTimeInterval(0.25)
                proxy.scrollTo(target, anchor: .top)
                // Clear without extra heavy work; the guard above already
                // returns when nil so this is a single cheap @Published write.
                if model.scrollTarget != nil { model.scrollTarget = nil }
            }
        }
    }

    /// Scroll-spy: delegates to the pure `ScrollSpy.activeSlug` function in
    /// SeemdCore, using a 12-pt inset to match the previous threshold behaviour.
    private func updateActiveHeading(_ frames: [AppHeadingFrame]) {
        guard !frames.isEmpty else { return }
        // While a TOC-initiated scroll is settling, suppress spy writes so the
        // jump is not fought by per-frame highlight churn.
        guard Date() >= suppressSpyUntil else { return }
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
