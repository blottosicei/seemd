import SwiftUI
import Combine
import SeemdCore

/// Per-window document state: parses Markdown, watches for external edits,
/// resolves the theme, and caches syntax-highlighted code blocks.
@MainActor
final class DocumentModel: ObservableObject {

    // MARK: - Published state

    @Published private(set) var url: URL?
    @Published private(set) var source: String = ""
    @Published private(set) var blocks: [RenderBlock] = []
    @Published private(set) var headings: [MarkdownDocument.Heading] = []
    /// Source character offset of the start of each heading line, in the SAME
    /// document order as `headings` (parallel arrays, equal count). Computed
    /// once per text change in `applySource` so editor↔preview scroll sync can
    /// binary-search instead of rescanning the source on every scroll event.
    @Published private(set) var headingCharOffsets: [Int] = []
    @Published private(set) var loadError: String?

    @Published var zoom: Double = ZoomScale.load()
    @Published var searchQuery: String = ""
    @Published var activeHeadingSlug: String?

    /// A slug the document view should scroll to (TOC click or live-reload
    /// scroll preservation). Cleared by the view after it scrolls.
    @Published var scrollTarget: String?

    // MARK: - Editor ↔ preview scroll arbiter

    /// Timestamp-based, deterministic anti-feedback gate. When one pane
    /// programmatically scrolls the other, it calls `suppressSync(...)` for
    /// the pane being driven; that pane then ignores its own scroll-driven
    /// sync until the deadline passes, so a programmatic scroll cannot echo
    /// back and bounce. The pane the user actively scrolls is never
    /// suppressed, so it always drives the other.
    private var suppressEditorSyncUntil: Date = .distantPast
    private var suppressPreviewSyncUntil: Date = .distantPast
    private static let syncSuppressionWindow: TimeInterval = 0.25

    /// Editor → preview just fired: silence the preview's scroll-spy so the
    /// resulting preview scroll does not bounce back into the editor.
    func suppressPreviewSync() {
        suppressPreviewSyncUntil =
            Date().addingTimeInterval(Self.syncSuppressionWindow)
    }

    /// Preview → editor just fired: silence the editor's bounds-driven sync
    /// so the resulting editor scroll does not bounce back into the preview.
    func suppressEditorSync() {
        suppressEditorSyncUntil =
            Date().addingTimeInterval(Self.syncSuppressionWindow)
    }

    /// True while the editor should ignore its bounds-change-driven sync
    /// because the preview is currently driving.
    var editorSyncSuppressed: Bool { Date() < suppressEditorSyncUntil }

    /// True while the preview should ignore its scroll-spy because the editor
    /// is currently driving.
    var previewSyncSuppressed: Bool { Date() < suppressPreviewSyncUntil }

    /// Per-window continuous scroll synchroniser (editor↔preview). Lazily
    /// created and owned here so it shares the window's lifetime; it is a
    /// plain helper object, never @Published and never injected into the
    /// block tree (BlockView stays decoupled — no heavy ObservableObject).
    private(set) lazy var scrollSync = ScrollSyncCoordinator(model: self)

    @Published private(set) var effectiveTheme: EffectiveTheme = .light
    @Published private(set) var palette: ThemePalette = ThemePalette.palette(for: .light)

    /// The user's theme override; published so the menu can bind to it.
    @Published var themeOverride: ThemeOverride = ThemePreferences.override() {
        didSet {
            guard themeOverride != oldValue else { return }
            ThemePreferences.setOverride(themeOverride)
            recomputeTheme()
        }
    }

    // MARK: - Highlight cache

    private struct CacheKey: Hashable {
        let code: String
        let lang: String
        let isDark: Bool
    }

    private let highlighter = SyntaxHighlighter()
    private var highlightCache: [CacheKey: [HighlightToken]] = [:]

    // MARK: - Private

    /// Set by the view while the in-app editor is active and has unsaved
    /// changes. While true, the file watcher's live-reload is suppressed so an
    /// external write cannot clobber the user's unsaved edits.
    var hasUnsavedEdits = false

    private var systemIsDark = false
    private let bookmarks = BookmarkStore()
    private var watcher: FileWatcher?
    private let reloadDebouncer = Debouncer(interval: 0.15)
    private var accessingURL: URL?

    var documentTitle: String { url?.lastPathComponent ?? "seemd" }
    /// Directory containing the open document (for resolving relative images).
    var documentDirectory: URL? { url?.deletingLastPathComponent() }
    /// Full file path shown as a small subtitle under the title, with the
    /// user's home directory abbreviated to `~`.
    var documentSubtitle: String {
        guard let path = url?.path else { return "" }
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    // MARK: - Lifecycle

    deinit {
        watcher?.stop()
        if let accessingURL {
            BookmarkStore().stopAccessing(accessingURL)
        }
    }

    // MARK: - Opening

    /// Load text supplied by `DocumentGroup`. Releases any prior security
    /// scope/watcher, parses the text, and (if a URL is present) resolves a
    /// security-scoped bookmark, records the recent document, and begins
    /// watching the file for external edits.
    func load(text: String, url: URL?) {
        // Release any previously held scope.
        if let accessingURL {
            bookmarks.stopAccessing(accessingURL)
            self.accessingURL = nil
        }
        watcher?.stop()
        watcher = nil

        loadError = nil

        guard let url else {
            self.url = nil
            applySource(text, resetScroll: true)
            return
        }

        // Prefer a resolved security-scoped bookmark if we have one.
        let target = bookmarks.resolve(url) ?? url
        if bookmarks.startAccessing(target) {
            accessingURL = target
        }

        self.url = target
        applySource(text, resetScroll: true)

        // Note recent + persist bookmark (best-effort).
        NSDocumentController.shared.noteNewRecentDocumentURL(target)
        try? bookmarks.save(target)

        startWatching(target)
    }

    private func startWatching(_ url: URL) {
        watcher = FileWatcher(url: url) { [weak self] in
            guard let self else { return }
            self.reloadDebouncer.schedule {
                Task { @MainActor [weak self] in
                    self?.reload()
                }
            }
        }
    }

    /// Reload from disk, preserving the top-most visible heading.
    private func reload() {
        guard let url else { return }
        guard let text = Self.readFile(url) else { return }
        // If the file on disk now matches our in-memory source, the most
        // recent write was our own Save — the editor and disk are back in
        // sync, so clear the unsaved guard and stop (nothing to reload).
        guard text != source else {
            hasUnsavedEdits = false
            return
        }
        // Disk genuinely diverged. Never let an external write stomp the
        // user's unsaved in-app edits.
        guard !hasUnsavedEdits else { return }
        let preserved = activeHeadingSlug
        applySource(text, resetScroll: false)
        if let preserved, headings.contains(where: { $0.slug == preserved }) {
            scrollTarget = preserved
        }
    }

    /// Re-parse + rebuild the rendered block tree from edited source while the
    /// in-app editor is the source of truth. Deliberately does NOT reset scroll
    /// and does NOT touch `activeHeadingSlug` so live-preview edits cannot
    /// trigger a scroll jump or TOC re-highlight storm. The view debounces the
    /// calls; this only mutates `source`/`headings`/`blocks`.
    func applyEditedSource(_ text: String) {
        guard text != source else { return }
        applySource(text, resetScroll: false)
    }

    private func applySource(_ text: String, resetScroll: Bool) {
        source = text
        let doc = MarkdownDocument(text)
        let parsedHeadings = doc.headings
        headings = parsedHeadings
        headingCharOffsets = Self.headingLineOffsets(
            in: text, count: parsedHeadings.count)
        blocks = RenderBuilder.build(doc)
        if resetScroll {
            activeHeadingSlug = headings.first?.slug
        }
    }

    /// One-pass O(n) scan of `text` collecting the UTF-16 character offset of
    /// the start of every ATX heading line (same rule as
    /// `MarkdownEditor.isHeadingLine`: optional ≤3 spaces, 1–6 `#`, then a
    /// space/tab). Truncated/padded to `count` so it stays a parallel array
    /// with `headings` even when Setext headings or `#` inside fenced code
    /// blocks make the line scan and the AST walk disagree (heading detection
    /// inside fences is intentionally imperfect — kept simple and O(n)).
    private static func headingLineOffsets(in text: String,
                                           count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let ns = text as NSString
        let length = ns.length
        var offsets: [Int] = []
        offsets.reserveCapacity(count)
        var loc = 0
        while loc < length {
            let lineRange = ns.lineRange(
                for: NSRange(location: loc, length: 0))
            let line = ns.substring(with: lineRange)
            if isHeadingLine(line) { offsets.append(lineRange.location) }
            let next = lineRange.location + lineRange.length
            if next <= loc { break }
            loc = next
        }
        if offsets.count > count {
            offsets.removeLast(offsets.count - count)
        } else if offsets.count < count {
            offsets.append(
                contentsOf: Array(repeating: length,
                                  count: count - offsets.count))
        }
        return offsets
    }

    /// Heading-line predicate, identical rule to
    /// `MarkdownEditor.Coordinator.isHeadingLine`.
    private static func isHeadingLine(_ line: String) -> Bool {
        var s = Substring(line)
        var spaces = 0
        while let f = s.first, f == " ", spaces < 3 {
            s = s.dropFirst(); spaces += 1
        }
        var hashes = 0
        while let f = s.first, f == "#", hashes < 7 {
            s = s.dropFirst(); hashes += 1
        }
        guard (1...6).contains(hashes) else { return false }
        return s.first == " " || s.first == "\t"
    }

    private static func readFile(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
    }

    // MARK: - Theme

    /// Recompute theme/palette from the latest system appearance.
    func updateSystemAppearance(isDark: Bool) {
        systemIsDark = isDark
        recomputeTheme()
    }

    private func recomputeTheme() {
        let resolved = ThemeResolver.resolve(override: themeOverride,
                                             systemIsDark: systemIsDark)
        guard resolved != effectiveTheme || blocks.isEmpty else {
            // Still refresh palette in case override changed within same theme.
            palette = ThemePalette.palette(for: resolved)
            return
        }
        effectiveTheme = resolved
        palette = ThemePalette.palette(for: resolved)
        // Theme change invalidates dark/light highlight variants implicitly
        // (cache is keyed by isDark) but stale entries are harmless; drop
        // them to bound memory.
        highlightCache = highlightCache.filter { $0.key.isDark == (resolved == .dark) }
    }

    /// Whether to force a SwiftUI color scheme (nil = follow the OS).
    var forcedColorScheme: ColorScheme? {
        switch themeOverride {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    // MARK: - Zoom

    func zoomIn()    { setZoom(ZoomScale.zoomIn(zoom)) }
    func zoomOut()   { setZoom(ZoomScale.zoomOut(zoom)) }
    func zoomReset() { setZoom(ZoomScale.reset()) }

    private func setZoom(_ value: Double) {
        zoom = ZoomScale.clamp(value)
        ZoomScale.save(zoom)
    }

    // MARK: - Highlighting

    /// Returns cached tokens if present, otherwise highlights asynchronously
    /// and invokes `completion` on the main actor when ready.
    func highlightedTokens(code: String,
                           language: String?,
                           completion: @escaping ([HighlightToken]) -> Void) {
        let isDark = effectiveTheme == .dark
        let key = CacheKey(code: code, lang: language ?? "", isDark: isDark)
        if let cached = highlightCache[key] {
            completion(cached)
            return
        }
        let theme: CodeTheme = isDark ? .dark : .light
        Task { [highlighter] in
            let tokens = await highlighter.highlight(code,
                                                     language: language,
                                                     theme: theme)
            await MainActor.run {
                self.highlightCache[key] = tokens
                completion(tokens)
            }
        }
    }
}
