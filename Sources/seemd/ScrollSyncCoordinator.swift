import AppKit
import SwiftUI
import SeemdCore

/// Per-window continuous editor↔preview scroll synchroniser.
///
/// Both panes are now app-owned `NSScrollView`s: the editor's lives in
/// `MarkdownEditor`, the preview's in `HostedScrollView`. Neither is obtained
/// by SwiftUI introspection (`enclosingScrollView` returns nil on macOS 14, so
/// the old `ScrollViewCapture` path was non-functional and is gone).
///
/// On every `NSView.boundsDidChangeNotification` of the pane the user is
/// physically scrolling, this object builds content-space heading-Y arrays for
/// both panes and calls the pure, self-tested
/// `SeemdCore.ScrollSyncMath.followerOffset(...)` to map the driver's
/// viewport-top to the follower's content offset, then sets the follower clip
/// view origin directly (continuous, frame-by-frame, no snap). A deterministic
/// Date-based ~250ms arbiter on `DocumentModel` plus per-tick follower
/// suppression prevents programmatic scrolls from echoing back.
///
/// It is a plain `@MainActor` class — deliberately NOT an `ObservableObject`
/// and never injected into the block tree, so `BlockView` keeps observing only
/// its Equatable `RenderContext` value (no scroll-spy / render storm).
@MainActor
final class ScrollSyncCoordinator {

    // MARK: Registered panes

    /// The editor's `NSScrollView` (owned by `MarkdownEditor`).
    private weak var editorScroll: NSScrollView?
    /// The preview's app-owned `NSScrollView` (owned by `HostedScrollView`).
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
        editorHeadingY = headingY
        editorContentHeight = contentHeight
        guard editorScroll !== scrollView else { return }
        editorScroll = scrollView
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

    /// Called by `HostedScrollView` once its app-owned `NSScrollView` exists.
    /// Registers the real scroll view directly — NO `enclosingScrollView`, NO
    /// SwiftUI introspection.
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

    // MARK: TOC click / reload preservation (preview-only mode)

    /// Scroll the preview's app-owned `NSScrollView` so the heading with
    /// `slug` is at the viewport top. Used by `PreviewPane` in preview-only
    /// mode for TOC sidebar clicks and live-reload scroll preservation
    /// (previously a SwiftUI `ScrollViewReader.scrollTo(id)`). Returns true if
    /// it scrolled (slug found + scroll view available).
    @discardableResult
    func scrollPreview(toHeadingSlug slug: String) -> Bool {
        guard let model, let previewScroll,
              let index = model.headings.firstIndex(where: { $0.slug == slug }),
              index < previewHeadingY.count else { return false }
        let viewport = previewScroll.contentView.bounds.height
        let content = max(previewScroll.documentView?.bounds.height ?? 0,
                          viewport)
        let y = ScrollSyncMath.clampOffset(
            Double(previewHeadingY[index]),
            contentHeight: Double(content),
            viewportHeight: Double(viewport))
        Self.apply(targetY: CGFloat(y), to: previewScroll)
        return true
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
              let editorContentHeight else { return }
        let editorContent = max(editorContentHeight(),
                                editorScroll.contentView.bounds.height)
        let previewContent = max(previewScroll.documentView?.bounds.height ?? 0,
                                 previewScroll.contentView.bounds.height)
        // Preview is being driven: silence its scroll-driven sync so it
        // cannot bounce back into the editor.
        syncDriver(editorScroll,
                   driverHeadingYs: editorHeadingYTable(),
                   driverContent: editorContent,
                   follower: previewScroll,
                   followerHeadingYs: previewHeadingY,
                   followerContent: previewContent,
                   suppressFollower: model.suppressPreviewSync)
    }

    /// Preview is the driver → move the editor continuously.
    private func syncFromPreview() {
        guard let model, !model.previewSyncSuppressed,
              let editorScroll, let previewScroll,
              let editorContentHeight else { return }
        let previewContent = max(previewScroll.documentView?.bounds.height ?? 0,
                                 previewScroll.contentView.bounds.height)
        let editorContent = max(editorContentHeight(),
                                editorScroll.contentView.bounds.height)
        // Editor is being driven: silence its bounds-driven sync so it cannot
        // bounce back into the preview.
        syncDriver(previewScroll,
                   driverHeadingYs: previewHeadingY,
                   driverContent: previewContent,
                   follower: editorScroll,
                   followerHeadingYs: editorHeadingYTable(),
                   followerContent: editorContent,
                   suppressFollower: model.suppressEditorSync)
    }

    /// Map `driver`'s viewport-top to `follower`'s content offset via the pure
    /// `ScrollSyncMath` interpolation, suppress the follower's own sync (so the
    /// programmatic scroll cannot echo back), then set the follower offset.
    private func syncDriver(_ driver: NSScrollView,
                            driverHeadingYs: [CGFloat],
                            driverContent: CGFloat,
                            follower: NSScrollView,
                            followerHeadingYs: [CGFloat],
                            followerContent: CGFloat,
                            suppressFollower: () -> Void) {
        let driverClip = driver.contentView
        let targetY = ScrollSyncMath.followerOffset(
            driverTop: Double(driverClip.bounds.origin.y),
            driverContentHeight: Double(driverContent),
            driverViewportHeight: Double(driverClip.bounds.height),
            driverHeadingYs: driverHeadingYs.map(Double.init),
            followerContentHeight: Double(followerContent),
            followerViewportHeight: Double(follower.contentView.bounds.height),
            followerHeadingYs: followerHeadingYs.map(Double.init))
        suppressFollower()
        Self.apply(targetY: CGFloat(targetY), to: follower)
    }

    /// Editor heading Y table in document order (only indices the layout
    /// manager can resolve are filled; others are forward-filled from the
    /// previous known Y so the shared-prefix interpolation stays monotonic).
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
