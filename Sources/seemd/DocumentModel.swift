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
    @Published private(set) var loadError: String?

    @Published var zoom: Double = ZoomScale.load()
    @Published var searchQuery: String = ""
    @Published var activeHeadingSlug: String?

    /// A slug the document view should scroll to (TOC click or live-reload
    /// scroll preservation). Cleared by the view after it scrolls.
    @Published var scrollTarget: String?

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
        guard text != source else { return }
        let preserved = activeHeadingSlug
        applySource(text, resetScroll: false)
        if let preserved, headings.contains(where: { $0.slug == preserved }) {
            scrollTarget = preserved
        }
    }

    private func applySource(_ text: String, resetScroll: Bool) {
        source = text
        let doc = MarkdownDocument(text)
        headings = doc.headings
        blocks = RenderBuilder.build(doc)
        if resetScroll {
            activeHeadingSlug = headings.first?.slug
        }
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
