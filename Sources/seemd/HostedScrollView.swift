import SwiftUI
import AppKit
import SeemdCore

/// An app-owned `NSScrollView` whose `documentView` is an `NSHostingView` of
/// the rendered Markdown block content.
///
/// Why this exists: on macOS 14 a SwiftUI `ScrollView` no longer exposes its
/// backing `NSScrollView` via `enclosingScrollView` (it returns nil), so the
/// old introspection-based continuous editor↔preview sync was non-functional.
/// By hosting the *same* SwiftUI content (`VStack { ForEach … BlockView }`)
/// inside an `NSScrollView` this app owns, the per-window
/// `ScrollSyncCoordinator` gets a real `NSScrollView` it can observe and drive
/// directly — no SwiftUI introspection, fully deterministic.
///
/// The hosted content keeps the SAME `RenderContext` value + highlight closure
/// path into `BlockView` (perf decoupling intact — `BlockView` never observes a
/// heavy `ObservableObject`) and keeps the `HeadingFramePreferenceKey` overlay
/// + `"docScroll"` coordinate space so the per-heading content-Y table the
/// continuous sync needs is still produced. Scroll-spy (the TOC active-heading
/// highlight) is NO LONGER driven by that PreferenceKey — the hosted SwiftUI
/// content does not move in its own coordinate space when the NSScrollView
/// scrolls (the clip view moves), so `onPreferenceChange` never re-fires on
/// scroll. The `ScrollSyncCoordinator` instead drives scroll-spy from this
/// scroll view's real clip-offset on every `boundsDidChange`.
/// Deterministic top clearance constants (non-generic so they can be
/// referenced without `HostedScrollView`'s generic `Content`). Baked into the
/// hosted content as real top PADDING (not an `NSScrollView.contentInsets.top`)
/// so origin 0 == the true top and no `[0, maxScroll]` clamp can hide the H1
/// (the old negative-origin bug class). Viewer mode clears the unified title
/// bar only; edit mode also clears the SwiftUI FormatBar row + divider.
enum PreviewTopInset {
    static let viewer: CGFloat = 28
    static let edit: CGFloat = 64
}

struct HostedScrollView<Content: View>: NSViewRepresentable {
    /// Deterministic top clearance baked INTO the hosted SwiftUI content as
    /// real top padding (NOT an `NSScrollView.contentInsets.top`).
    ///
    /// Bug-class fix: a top *content inset* makes the fully-scrolled-to-top
    /// resting clip origin `bounds.origin.y == -inset`, NOT 0. But every
    /// scroll-up / programmatic-sync / spy path clamps the preview clip origin
    /// to `[0, maxScroll]` (`ScrollSyncMath.clampOffset`, the flipped clip
    /// view), so a scroll round-trip back to the top lands at origin 0 instead
    /// of `-inset` — the top `inset` points (the H1) stay hidden under the
    /// unified title bar / formatting toolbar. Initial layout respected the
    /// inset; any scroll round-trip silently lost it.
    ///
    /// The robust fix removes the negative-origin space entirely: we set NO
    /// top content inset and instead add this value as deterministic top
    /// padding inside the hosted content. Now origin 0 == the true top of the
    /// padding, the H1 is fully visible below the bar at origin 0, and the
    /// `"docScroll"` heading-Y table, the clip origin and `ScrollSyncMath`'s
    /// `[0, content-viewport]` clamp all live in ONE consistent space — there
    /// is no coordinate that can clamp the clearance away.
    ///
    /// Value covers the standard macOS unified title bar plus, in edit mode,
    /// the SwiftUI FormatBar row + divider that sit between the window
    /// title-bar safe area and this scroll view, so the H1 is fully clear in
    /// BOTH edit and viewer mode without an excessively large gap. This
    /// mirrors how the editor's `NSTextView` gets its own deterministic top
    /// clearance via `textContainerInset.height`.
    ///
    /// CRITICAL — sync/spy consistency: this is the SINGLE source of truth for
    /// the clearance and it is now part of content space. `ScrollSyncCoordinator`
    /// performs NO inset compensation — heading Ys (which already include this
    /// padding) and the clip origin are in the same space, so spy / TOC
    /// landing / continuous sync stay consistent with no double-counting.
    /// Max content width (point value, or `.infinity` to fill the window).
    let maxContentWidth: CGFloat
    /// Deterministic top clearance baked into content space (mode-aware:
    /// `previewTopInset` for viewer, `editTopInset` for edit mode).
    let topPadding: CGFloat
    /// Window background hex (palette) painted behind the content.
    let backgroundHex: String
    /// Per-window coordinator the created `NSScrollView` registers with.
    let coordinator: ScrollSyncCoordinator
    /// The rendered block content (rebuilt by SwiftUI when inputs change).
    @ViewBuilder let content: () -> Content

    func makeCoordinator() -> Coord { Coord() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = FlippedScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = true
        // Bug-class fix: NO top content inset. A top content inset makes the
        // fully-scrolled-to-top resting clip origin `-inset` (not 0), but every
        // scroll-up / sync / spy path clamps the clip origin to `[0, maxScroll]`
        // so a scroll round-trip back to the top lands at 0 and the top `inset`
        // points (the H1) stay hidden under the bar. We disable auto inset
        // adjustment AND zero `contentInsets`, then bake the title-bar /
        // FormatBar clearance into the hosted content as deterministic top
        // PADDING (see `wrapped()`), so origin 0 == the true top, the H1 is
        // fully visible there, and the heading-Y table, clip origin and
        // `ScrollSyncMath`'s clamp all share one consistent space — no
        // coordinate can clamp the clearance away.
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsetsZero
        scroll.scrollerStyle = .overlay
        scroll.verticalScrollElasticity = .allowed
        scroll.horizontalScrollElasticity = .none

        let hosting = NSHostingView(rootView: AnyView(wrapped()))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        // CRITICAL (truncation fix): by default an `NSHostingView` does NOT
        // propagate the full SwiftUI content height as its intrinsic content
        // size — it under-reports, so the pinned `docContainer` stays short,
        // the documentView is effectively clipped, and blocks past an early
        // point never lay out (preview blank past the top). Opting into
        // `.intrinsicContentSize` (macOS 13.0+; macOS 14 target) makes the
        // hosting view's intrinsicContentSize track the FULL measured SwiftUI
        // VStack height. The existing leading/trailing/top/bottom pin to the
        // flipped docContainer then propagates that full height to the
        // documentView, so the entire document lays out and is scrollable —
        // not just the first viewport-ish region.
        hosting.sizingOptions = [.intrinsicContentSize]
        // NOTE: explicit `wantsLayer = true` on this hosting view / the doc
        // container was tried as a P2 "scroll perf" tweak and made scrolling
        // WORSE: the entire document is eagerly rendered into one giant
        // NSHostingView, so layer-backing forces a single enormous backing
        // layer that exceeds the GPU max texture size on long docs and tiles/
        // re-rasterizes on scroll. Letting AppKit's NSClipView handle scroll
        // without an explicit huge layer is smoother — do NOT re-add wantsLayer
        // here.

        // A flipped document container so content lays out top-down and the
        // hosting view's intrinsic height drives the scrollable range.
        let docContainer = FlippedView()
        docContainer.translatesAutoresizingMaskIntoConstraints = false
        docContainer.addSubview(hosting)
        scroll.documentView = docContainer
        // NOTE: `copiesOnScroll` is intentionally not set — it is a no-op since
        // macOS 11 (NSClipView already minimizes the invalidated document-view
        // area automatically). The layer-backed hosting view above is the
        // actual scroll-compositing win; pixel reuse during scroll is handled
        // by the clip view's built-in minimal invalidation.
        context.coordinator.hosting = hosting

        // Width tracks the viewport (vertical scroll only); height is driven by
        // SwiftUI's measured content so a long document is taller than the clip
        // view (→ scrollable) and a short one is not.
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: docContainer.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: docContainer.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: docContainer.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: docContainer.bottomAnchor),
            hosting.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])

        applyBackground(scroll)
        // Register the real NSScrollView with the per-window coordinator
        // directly — NO `enclosingScrollView`, NO SwiftUI introspection.
        coordinator.registerPreview(scrollView: scroll)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        if let hosting = context.coordinator.hosting {
            hosting.rootView = AnyView(wrapped())
        }
        applyBackground(scroll)
        // Re-assert registration cheaply (idempotent) in case the view was
        // recreated by SwiftUI.
        coordinator.registerPreview(scrollView: scroll)
    }

    /// The content, framed exactly like the old SwiftUI `PreviewPane`
    /// (`.padding` + max-content-width centering) and carrying the
    /// `"docScroll"` coordinate space so the `HeadingFramePreferenceKey`
    /// overlay inside `BlockView` reports content-space heading Ys (consumed by
    /// the continuous sync + clip-offset scroll-spy as the heading-Y table).
    private func wrapped() -> some View {
        content()
            .padding(.horizontal, 32)
            // Deterministic top clearance baked into content space (NOT a
            // scroll-view content inset): `previewTopInset` clears the unified
            // title bar + (edit-mode) FormatBar so the H1 is fully visible at
            // clip origin 0 — the true top of this padding. Because the
            // clearance is now part of the rendered content, the "docScroll"
            // heading-Y table already includes it; clip origin 0 == top, and a
            // scroll round-trip back to the top can no longer clamp it away
            // (the old negative-origin bug class). Keep a generous bottom so
            // the last block can scroll clear of the window edge.
            .padding(.top, topPadding)
            .padding(.bottom, 28)
            .frame(maxWidth: maxContentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .coordinateSpace(name: "docScroll")
    }

    private func applyBackground(_ scroll: NSScrollView) {
        let bg = NSColor(Color(hex: backgroundHex,
                               fallback: Color(NSColor.textBackgroundColor)))
        scroll.backgroundColor = bg
        scroll.contentView.drawsBackground = true
        scroll.contentView.backgroundColor = bg
    }

    final class Coord {
        var hosting: NSHostingView<AnyView>?
    }
}

/// An `NSScrollView` whose clip view is flipped so content lays out top-down
/// (origin at top-left) — matches SwiftUI's expectation and makes content-space
/// heading Ys monotonically increase downward, as `ScrollSyncMath` assumes.
private final class FlippedScrollView: NSScrollView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        contentView = FlippedClipView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        contentView = FlippedClipView()
    }
}

private final class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

/// A flipped container used as the `NSScrollView.documentView`. Flipped so the
/// hosted content lays out top-down (origin at top-left); its height is driven
/// purely by the pinned `NSHostingView`'s Auto Layout intrinsic content size,
/// giving the scroll view a real scrollable range for long documents.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
