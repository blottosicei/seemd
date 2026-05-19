import SwiftUI
import AppKit
import SeemdCore

/// An app-owned `NSScrollView` whose `documentView` is an `NSHostingView` of
/// the rendered Markdown block content.
///
/// Why this exists: on macOS 14 a SwiftUI `ScrollView` no longer exposes its
/// backing `NSScrollView` via `enclosingScrollView` (it returns nil), so the
/// old introspection-based continuous editor↔preview sync was non-functional.
/// By hosting the *same* SwiftUI content (`LazyVStack { ForEach … BlockView }`)
/// inside an `NSScrollView` this app owns, the per-window
/// `ScrollSyncCoordinator` gets a real `NSScrollView` it can observe and drive
/// directly — no SwiftUI introspection, fully deterministic.
///
/// The hosted content keeps the SAME `RenderContext` value + highlight closure
/// path into `BlockView` (perf decoupling intact — `BlockView` never observes a
/// heavy `ObservableObject`) and keeps the `HeadingFramePreferenceKey` overlay
/// + `"docScroll"` coordinate space so scroll-spy keeps working.
struct HostedScrollView<Content: View>: NSViewRepresentable {
    /// Max content width (point value, or `.infinity` to fill the window).
    let maxContentWidth: CGFloat
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
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsetsZero
        scroll.scrollerStyle = .overlay
        scroll.verticalScrollElasticity = .allowed
        scroll.horizontalScrollElasticity = .none

        let hosting = NSHostingView(rootView: AnyView(wrapped()))
        hosting.translatesAutoresizingMaskIntoConstraints = true
        // Width tracks the clip view (vertical scroll only); height grows to
        // the content's intrinsic size so the document scrolls.
        hosting.autoresizingMask = [.width]
        scroll.documentView = hosting
        context.coordinator.hosting = hosting

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
    /// overlay inside `BlockView` reports content-space heading Ys.
    private func wrapped() -> some View {
        content()
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
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
