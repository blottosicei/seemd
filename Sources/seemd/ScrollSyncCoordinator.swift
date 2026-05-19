import AppKit
import SwiftUI
import SeemdCore

/// Per-window continuous editor↔preview scroll synchroniser.
///
/// Replaces the old anchor-snap mechanism (`model.scrollTarget` +
/// `ScrollViewReader.scrollTo(id)`), which teleported the followed pane to a
/// heading when the user stopped scrolling. Instead this object holds the
/// underlying `NSScrollView` of BOTH panes and, on every bounds change of the
/// pane the user is physically scrolling, maps that pane's viewport-top Y to
/// the other pane's content Y by *linear interpolation between the two
/// surrounding headings* (proportional whole-document fallback when there are
/// 0/1 headings or the viewport is before the first / after the last heading).
/// The followed pane's clip-view origin is set directly, so it tracks the
/// driver smoothly frame-by-frame with no snap.
///
/// It is a plain `@MainActor` class — deliberately NOT an `ObservableObject`
/// and never injected into the block tree, so `BlockView` keeps observing only
/// its Equatable `RenderContext` value (no scroll-spy / render storm).
@MainActor
final class ScrollSyncCoordinator {

    // MARK: Registered panes

    /// The editor's `NSScrollView` (owned by `MarkdownEditor`).
    private weak var editorScroll: NSScrollView?
    /// The preview's underlying `NSScrollView` (captured via introspection).
    private weak var previewScroll: NSScrollView?

    /// Resolves the editor content-Y of heading `i` (document order) using the
    /// text view's layout manager. Supplied by `MarkdownEditor.Coordinator`
    /// because only it owns the `NSTextView`. Returns nil if unavailable.
    private var editorHeadingY: ((Int) -> CGFloat?)?
    /// Total editor document height (text view bounds height).
    private var editorContentHeight: (() -> CGFloat)?

    /// Latest preview per-heading content-Y, indexed to match
    /// `model.headings` (document order). Built from the SwiftUI
    /// `HeadingFramePreferenceKey` frames (already in "docScroll" content
    /// space). Count may differ transiently from the editor table; the
    /// interpolation only uses indices valid in BOTH tables.
    private var previewHeadingY: [CGFloat] = []

    private weak var model: DocumentModel?

    private var editorObserver: NSObjectProtocol?
    private var previewObserver: NSObjectProtocol?

    /// Coalesces the bounds-change storm onto the main run loop's next turn so
    /// the followed pane moves at animation-frame cadence (continuous, not
    /// stepped) while still doing only O(log n)+O(1) work per turn.
    private var editorTick = false
    private var previewTick = false

    init(model: DocumentModel) {
        self.model = model
    }

    deinit {
        if let editorObserver {
            NotificationCenter.default.removeObserver(editorObserver)
        }
        if let previewObserver {
            NotificationCenter.default.removeObserver(previewObserver)
        }
    }

    // MARK: Registration

    /// Called by `MarkdownEditor.Coordinator` once its scroll view exists.
    func registerEditor(scrollView: NSScrollView,
                        headingY: @escaping (Int) -> CGFloat?,
                        contentHeight: @escaping () -> CGFloat) {
        editorScroll = scrollView
        editorHeadingY = headingY
        editorContentHeight = contentHeight
        scrollView.contentView.postsBoundsChangedNotifications = true
        if let editorObserver {
            NotificationCenter.default.removeObserver(editorObserver)
        }
        editorObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleEditorSync() }
        }
    }

    /// Called by `ScrollViewCapture` once it has walked to the preview's
    /// enclosing `NSScrollView`.
    func registerPreview(scrollView: NSScrollView) {
        guard previewScroll !== scrollView else { return }
        previewScroll = scrollView
        scrollView.contentView.postsBoundsChangedNotifications = true
        if let previewObserver {
            NotificationCenter.default.removeObserver(previewObserver)
        }
        previewObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedulePreviewSync() }
        }
    }

    /// Fed by `PreviewPane` on every `HeadingFramePreferenceKey` change. The
    /// frames carry the slug + content-space minY of every rendered heading;
    /// we align them to `model.headings` document order so index `i` means the
    /// same heading in both the editor and preview Y tables.
    func updatePreviewHeadingFrames(_ frames: [AppHeadingFrame]) {
        guard let model else { return }
        let headings = model.headings
        guard !headings.isEmpty else { previewHeadingY = []; return }
        // slug → content Y (a slug is unique per document by construction).
        var ys = Array<CGFloat?>(repeating: nil, count: headings.count)
        var slugToIndex: [String: Int] = [:]
        for (i, h) in headings.enumerated() { slugToIndex[h.slug] = i }
        for f in frames {
            if let i = slugToIndex[f.slug] { ys[i] = f.minY }
        }
        // Forward-fill any heading not currently rendered (lazy stack) with
        // the previous known Y so the table stays monotonic & usable; trailing
        // unknowns fall back to content height handled at lookup time.
        var filled: [CGFloat] = []
        filled.reserveCapacity(ys.count)
        var last: CGFloat = 0
        for v in ys {
            if let v { last = v }
            filled.append(last)
        }
        previewHeadingY = filled
    }

    // MARK: Sync scheduling (coalesced to next run-loop turn)

    private func scheduleEditorSync() {
        guard !editorTick else { return }
        editorTick = true
        DispatchQueue.main.async { [weak self] in
            self?.editorTick = false
            self?.syncFromEditor()
        }
    }

    private func schedulePreviewSync() {
        guard !previewTick else { return }
        previewTick = true
        DispatchQueue.main.async { [weak self] in
            self?.previewTick = false
            self?.syncFromPreview()
        }
    }

    // MARK: Drivers

    /// Editor is the driver → move the preview continuously.
    private func syncFromEditor() {
        guard let model, !model.editorSyncSuppressed,
              let editorScroll, let previewScroll,
              let contentHeight = editorContentHeight else { return }
        let aClip = editorScroll.contentView
        let topA = aClip.bounds.origin.y
        let viewportA = aClip.bounds.height
        let contentA = max(contentHeight(), viewportA)

        let ay = editorHeadingYTable()
        let by = previewHeadingY
        let viewportB = previewScroll.contentView.bounds.height
        let contentB = max(previewScroll.documentView?.bounds.height ?? 0,
                            viewportB)

        guard let targetY = Self.interpolatedTarget(
            topA: topA, viewportA: viewportA, contentA: contentA,
            ay: ay, by: by, viewportB: viewportB, contentB: contentB)
        else { return }

        // Preview is being driven: silence its scroll-driven sync so it
        // cannot bounce back into the editor.
        model.suppressPreviewSync()
        Self.apply(targetY: targetY, to: previewScroll)
    }

    /// Preview is the driver → move the editor continuously.
    private func syncFromPreview() {
        guard let model, !model.previewSyncSuppressed,
              let editorScroll, let previewScroll,
              let contentHeight = editorContentHeight else { return }
        let aClip = previewScroll.contentView
        let topA = aClip.bounds.origin.y
        let viewportA = aClip.bounds.height
        let contentA = max(previewScroll.documentView?.bounds.height ?? 0,
                            viewportA)

        let ay = previewHeadingY
        let by = editorHeadingYTable()
        let viewportB = editorScroll.contentView.bounds.height
        let contentB = max(contentHeight(), viewportB)

        guard let targetY = Self.interpolatedTarget(
            topA: topA, viewportA: viewportA, contentA: contentA,
            ay: ay, by: by, viewportB: viewportB, contentB: contentB)
        else { return }

        // Editor is being driven: silence its bounds-driven sync so it cannot
        // bounce back into the preview.
        model.suppressEditorSync()
        Self.apply(targetY: targetY, to: editorScroll)
    }

    /// Editor heading Y table in document order (only indices the layout
    /// manager can resolve are filled; others are dropped from the tail so the
    /// shared-prefix interpolation stays monotonic).
    private func editorHeadingYTable() -> [CGFloat] {
        guard let model, let resolve = editorHeadingY else { return [] }
        let count = model.headings.count
        guard count > 0 else { return [] }
        var ys: [CGFloat] = []
        ys.reserveCapacity(count)
        var last: CGFloat = 0
        for i in 0..<count {
            if let y = resolve(i) { last = y }
            ys.append(last)
        }
        return ys
    }

    // MARK: Interpolation math

    /// Map the driver pane's viewport-top `topA` to the followed pane's
    /// content Y.
    ///
    /// - Heading-anchored linear interpolation: find the greatest heading
    ///   index `i` with `ay[i] <= topA`; with the next heading `i+1` compute
    ///   `f = (topA - ay[i]) / (ay[i+1] - ay[i])` clamped to 0…1, then return
    ///   `by[i] + f * (by[i+1] - by[i])`. This keeps the SAME heading aligned
    ///   in both panes and moves smoothly between them.
    /// - Proportional fallback (0/1 headings, before the first heading, after
    ///   the last heading, or mismatched/empty tables): map the scroll
    ///   *fraction* `topA / (contentA - viewportA)` onto
    ///   `frac * (contentB - viewportB)`.
    ///
    /// The followed pane's max scroll is always clamped so we never overscroll.
    static func interpolatedTarget(topA: CGFloat,
                                   viewportA: CGFloat,
                                   contentA: CGFloat,
                                   ay: [CGFloat],
                                   by: [CGFloat],
                                   viewportB: CGFloat,
                                   contentB: CGFloat) -> CGFloat? {
        let maxB = max(0, contentB - viewportB)

        func proportional() -> CGFloat {
            let denom = max(1, contentA - viewportA)
            let frac = min(1, max(0, topA / denom))
            return min(maxB, max(0, frac * maxB))
        }

        // Usable shared prefix: both tables must have an entry per index.
        let n = min(ay.count, by.count)
        guard n >= 2 else { return proportional() }

        // Greatest i in 0..<n with ay[i] <= topA (ay is monotonic
        // non-decreasing by construction).
        var lo = 0
        var hi = n - 1
        var i = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if ay[mid] <= topA {
                i = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }

        // Before the first heading, or after the last → proportional so the
        // pre-/post-heading regions still track continuously.
        guard i >= 0 else { return proportional() }
        guard i < n - 1 else { return proportional() }

        let span = ay[i + 1] - ay[i]
        let f: CGFloat = span > 0
            ? min(1, max(0, (topA - ay[i]) / span))
            : 0
        let target = by[i] + f * (by[i + 1] - by[i])
        return min(maxB, max(0, target))
    }

    // MARK: Apply

    /// Set `scrollView`'s clip-view origin directly (no animation, no
    /// `ScrollViewReader`) so the followed pane tracks the driver frame by
    /// frame. No-op when already within sub-pixel of the target to avoid an
    /// idempotent bounds-change echo.
    static func apply(targetY: CGFloat, to scrollView: NSScrollView) {
        let clip = scrollView.contentView
        if abs(clip.bounds.origin.y - targetY) < 0.5 { return }
        clip.scroll(to: CGPoint(x: clip.bounds.origin.x, y: targetY))
        scrollView.reflectScrolledClipView(clip)
    }
}

// MARK: - Preview NSScrollView introspection

/// Captures the `NSScrollView` backing the SwiftUI preview `ScrollView` and
/// hands it to the per-window `ScrollSyncCoordinator`. Placed in `.background`
/// of the preview `ScrollView`; on macOS a SwiftUI `ScrollView` is backed by
/// an `NSScrollView`, reachable from any subview via `enclosingScrollView`.
struct ScrollViewCapture: NSViewRepresentable {
    let coordinator: ScrollSyncCoordinator

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { [weak view] in
            Self.capture(from: view, into: coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            Self.capture(from: nsView, into: coordinator)
        }
    }

    @MainActor
    private static func capture(from view: NSView?,
                                into coordinator: ScrollSyncCoordinator) {
        guard let view, let scroll = view.enclosingScrollView else { return }
        coordinator.registerPreview(scrollView: scroll)
    }
}
