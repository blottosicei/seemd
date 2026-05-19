import SwiftUI
import AppKit
import SeemdCore

// MARK: - Formatting actions

/// Imperative formatting commands the toolbar sends to the active editor.
enum FormatAction {
    // Inline paired markers (wrap selection / insert pair at caret).
    case bold          // **…**
    case italic        // *…*
    case underline     // <u>…</u>  (no Markdown equivalent; source convenience)
    case inlineCode    // `…`
    // Line-prefix toggles applied to every selected line.
    case h1, h2, h3    // "# " / "## " / "### "
    case quote         // "> "
    case bullet        // "- "
    case numbered      // "1. " incrementing per line
    case task          // "- [ ] "
    // Block.
    case codeBlock     // fenced ``` … ```
    case link          // [selection](url)
}

/// Posted by `FormattingToolbar` so the focused `MarkdownEditor` performs the
/// action. Object is the `FormatAction`.
extension Notification.Name {
    static let seemdFormat = Notification.Name("seemd.format")
}

// MARK: - Editor

/// Raw Markdown source editor: an `NSTextView` in an `NSScrollView`. Bound to a
/// `String` binding (the DocumentGroup document text) so edits flow through the
/// native dirty/undo/save machinery. Applies lightweight, debounced Markdown
/// syntax coloring and exposes an imperative formatting API.
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat
    let palette: ThemePalette
    /// The per-window document model. Read-only here: supplies the precomputed
    /// `headingCharOffsets` table (O(log n) binary search instead of an
    /// O(n)-per-event source rescan) and the scroll-sync arbiter.
    @ObservedObject var model: DocumentModel

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let textView = scroll.documentView as? NSTextView else { return scroll }

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = true
        textView.isContinuousSpellCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.textContainerInset = NSSize(width: 12, height: 14)

        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        context.coordinator.textView = textView
        context.coordinator.applyTheme(to: textView, palette: palette,
                                       fontSize: fontSize)
        textView.string = text
        context.coordinator.recolor(textView)

        // Continuous editor↔preview scroll sync: hand our NSScrollView (and
        // a layout-manager-backed heading-Y resolver + document height) to the
        // per-window coordinator, which drives offset interpolation directly
        // on both panes' clip views.
        context.coordinator.register(scroll)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        // Guard the update loop: only overwrite when the binding genuinely
        // diverged from the text view (external/programmatic change), never
        // for an echo of the user's own keystroke.
        if textView.string != text {
            let selected = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(
                NSRange(location: min(selected.location, (text as NSString).length),
                        length: 0))
            context.coordinator.recolor(textView)
        }
        context.coordinator.applyTheme(to: textView, palette: palette,
                                       fontSize: fontSize)
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        weak var textView: NSTextView?
        private let recolorDebouncer = Debouncer(interval: 0.12)
        private var formatObserver: NSObjectProtocol?

        init(_ parent: MarkdownEditor) {
            self.parent = parent
            super.init()
            formatObserver = NotificationCenter.default.addObserver(
                forName: .seemdFormat, object: nil, queue: .main
            ) { [weak self] note in
                guard let self,
                      let tv = self.textView,
                      tv.window?.firstResponder === tv,
                      let action = note.object as? FormatAction else { return }
                self.apply(action, to: tv)
            }
        }

        deinit {
            if let formatObserver {
                NotificationCenter.default.removeObserver(formatObserver)
            }
        }

        // MARK: Continuous scroll sync registration

        /// Hand the editor's `NSScrollView` to the per-window coordinator,
        /// along with closures it needs to resolve heading content-Y (via the
        /// layout manager — only this Coordinator owns the `NSTextView`) and
        /// the document height. The coordinator owns the bounds observer and
        /// the offset interpolation; nothing here writes `@Published` state or
        /// touches the block tree.
        @MainActor
        func register(_ scroll: NSScrollView) {
            parent.model.scrollSync.registerEditor(
                scrollView: scroll,
                headingY: { [weak self] index in
                    self?.editorHeadingY(index)
                },
                contentHeight: { [weak self] in
                    self?.textView?.bounds.height ?? 0
                })
        }

        /// Editor content-Y of heading `index` (document order): glyph
        /// bounding rect of the heading-line start offset, shifted by the
        /// text-container inset to land in text-view (== clip) coordinates.
        /// O(log n) is not needed — the caller passes the index directly; this
        /// is the precomputed `headingCharOffsets[index]` → layout lookup.
        @MainActor
        private func editorHeadingY(_ index: Int) -> CGFloat? {
            guard let tv = textView,
                  let lm = tv.layoutManager,
                  let tc = tv.textContainer else { return nil }
            let offsets = parent.model.headingCharOffsets
            guard index >= 0, index < offsets.count else { return nil }
            let ns = tv.string as NSString
            let safe = max(0, min(offsets[index], ns.length))
            let glyphRange = lm.glyphRange(
                forCharacterRange: NSRange(location: safe, length: 0),
                actualCharacterRange: nil)
            // Force layout up to this glyph: NSLayoutManager lays out lazily,
            // so without this a heading far below the viewport returns (0,0)
            // and large-doc sync collapses to forward-filled zeros until the
            // user scrolls near it. ensureLayout makes the Y accurate up-front.
            lm.ensureLayout(forGlyphRange: glyphRange)
            let rect = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
            return rect.origin.y + tv.textContainerInset.height
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            recolorDebouncer.schedule { [weak self, weak tv] in
                guard let self, let tv else { return }
                self.recolor(tv)
            }
        }

        // MARK: Theme

        func applyTheme(to tv: NSTextView, palette: ThemePalette,
                        fontSize: CGFloat) {
            let font = NSFont.monospacedSystemFont(ofSize: fontSize,
                                                   weight: .regular)
            tv.font = font
            let bg = NSColor(Color(hex: palette.windowBackground,
                                   fallback: Color(NSColor.textBackgroundColor)))
            let fg = NSColor(Color(hex: palette.bodyText,
                                   fallback: Color(NSColor.textColor)))
            tv.backgroundColor = bg
            tv.textColor = fg
            tv.insertionPointColor = fg
            tv.typingAttributes = [
                .font: font,
                .foregroundColor: fg,
            ]
        }

        // MARK: Syntax coloring (O(n), debounced)

        func recolor(_ tv: NSTextView) {
            guard let storage = tv.textStorage else { return }
            let ns = tv.string as NSString
            let full = NSRange(location: 0, length: ns.length)
            let baseFont = NSFont.monospacedSystemFont(
                ofSize: parent.fontSize, weight: .regular)
            let body = NSColor(Color(hex: parent.palette.bodyText,
                                     fallback: Color(NSColor.textColor)))
            let accent = NSColor(Color(hex: parent.palette.accentLink,
                                       fallback: Color(NSColor.systemBlue)))
            let secondary = NSColor(Color(hex: parent.palette.secondaryText,
                                          fallback: Color(NSColor.secondaryLabelColor)))

            storage.beginEditing()
            storage.setAttributes([.font: baseFont, .foregroundColor: body],
                                  range: full)

            func color(_ pattern: String, _ c: NSColor,
                       options: NSRegularExpression.Options = [],
                       bold: Bool = false) {
                guard let re = try? NSRegularExpression(pattern: pattern,
                                                        options: options) else { return }
                re.enumerateMatches(in: tv.string, options: [],
                                    range: full) { m, _, _ in
                    guard let r = m?.range, r.length > 0 else { return }
                    storage.addAttribute(.foregroundColor, value: c, range: r)
                    if bold {
                        let bf = NSFontManager.shared.convert(
                            baseFont, toHaveTrait: .boldFontMask)
                        storage.addAttribute(.font, value: bf, range: r)
                    }
                }
            }

            // Headings (whole line), blockquote, list markers.
            color("(?m)^#{1,6}[ \\t].*$", accent, bold: true)
            color("(?m)^[ \\t]*>.*$", secondary)
            color("(?m)^[ \\t]*([-*+]|\\d+\\.)[ \\t]", accent)
            // Fenced code blocks and inline code.
            color("(?s)```.*?```", secondary)
            color("`[^`\\n]+`", secondary)
            // Bold then italic (bold first so ** wins over *).
            color("\\*\\*[^*\\n]+\\*\\*", body, bold: true)
            color("(?<!\\*)\\*(?!\\*)[^*\\n]+\\*(?!\\*)", body)
            color("(?<![A-Za-z0-9_])_[^_\\n]+_(?![A-Za-z0-9_])", body)
            // Links: [text](url).
            color("\\[[^\\]\\n]*\\]\\([^)\\n]*\\)", accent)

            storage.endEditing()
        }

        // MARK: Formatting API

        func apply(_ action: FormatAction, to tv: NSTextView) {
            switch action {
            case .bold:       wrapInline(tv, "**", "**")
            case .italic:     wrapInline(tv, "*", "*")
            case .underline:  wrapInline(tv, "<u>", "</u>")
            case .inlineCode: wrapInline(tv, "`", "`")
            case .h1:         togglePrefix(tv, "# ")
            case .h2:         togglePrefix(tv, "## ")
            case .h3:         togglePrefix(tv, "### ")
            case .quote:      togglePrefix(tv, "> ")
            case .bullet:     togglePrefix(tv, "- ")
            case .task:       togglePrefix(tv, "- [ ] ")
            case .numbered:   numberLines(tv)
            case .codeBlock:  wrapCodeBlock(tv)
            case .link:       insertLink(tv)
            }
        }

        /// Replace `range` with `replacement` through the native text system so
        /// Undo works, then push the binding and recolor.
        private func replace(_ tv: NSTextView, _ range: NSRange,
                             _ replacement: String,
                             select: NSRange? = nil) {
            guard tv.shouldChangeText(in: range,
                                      replacementString: replacement) else { return }
            tv.textStorage?.replaceCharacters(in: range, with: replacement)
            tv.didChangeText()
            if let select { tv.setSelectedRange(select) }
            parent.text = tv.string
            recolor(tv)
        }

        private func wrapInline(_ tv: NSTextView, _ open: String,
                                _ close: String) {
            let sel = tv.selectedRange()
            let ns = tv.string as NSString
            if sel.length == 0 {
                let insert = open + close
                replace(tv, sel, insert,
                        select: NSRange(location: sel.location + open.count,
                                        length: 0))
            } else {
                let selected = ns.substring(with: sel)
                let wrapped = open + selected + close
                replace(tv, sel, wrapped,
                        select: NSRange(location: sel.location + open.count,
                                        length: selected.count))
            }
        }

        /// Range covering all full lines intersecting the selection.
        private func lineRange(_ tv: NSTextView) -> NSRange {
            let ns = tv.string as NSString
            return ns.lineRange(for: tv.selectedRange())
        }

        private func togglePrefix(_ tv: NSTextView, _ prefix: String) {
            let ns = tv.string as NSString
            let range = lineRange(tv)
            let block = ns.substring(with: range)
            var lines = block.components(separatedBy: "\n")
            // A trailing empty element from a final newline should be ignored.
            let hadTrailingNewline = block.hasSuffix("\n")
            if hadTrailingNewline { lines.removeLast() }
            let allPrefixed = lines.allSatisfy {
                $0.hasPrefix(prefix) || $0.isEmpty
            }
            let transformed = lines.map { line -> String in
                if allPrefixed {
                    return line.hasPrefix(prefix)
                        ? String(line.dropFirst(prefix.count)) : line
                }
                return line.isEmpty ? line : prefix + line
            }
            var result = transformed.joined(separator: "\n")
            if hadTrailingNewline { result += "\n" }
            replace(tv, range, result,
                    select: NSRange(location: range.location,
                                    length: (result as NSString).length))
        }

        private func numberLines(_ tv: NSTextView) {
            let ns = tv.string as NSString
            let range = lineRange(tv)
            let block = ns.substring(with: range)
            var lines = block.components(separatedBy: "\n")
            let hadTrailingNewline = block.hasSuffix("\n")
            if hadTrailingNewline { lines.removeLast() }
            let numberRE = try? NSRegularExpression(pattern: "^\\d+\\. ")
            let allNumbered = lines.allSatisfy { line in
                line.isEmpty || (numberRE?.firstMatch(
                    in: line, range: NSRange(location: 0,
                                             length: (line as NSString).length)) != nil)
            }
            var n = 1
            let transformed = lines.map { line -> String in
                if line.isEmpty { return line }
                if allNumbered, let re = numberRE {
                    let lr = NSRange(location: 0,
                                     length: (line as NSString).length)
                    return re.stringByReplacingMatches(
                        in: line, range: lr, withTemplate: "")
                }
                let out = "\(n). \(line)"
                n += 1
                return out
            }
            var result = transformed.joined(separator: "\n")
            if hadTrailingNewline { result += "\n" }
            replace(tv, range, result,
                    select: NSRange(location: range.location,
                                    length: (result as NSString).length))
        }

        private func wrapCodeBlock(_ tv: NSTextView) {
            let sel = tv.selectedRange()
            let ns = tv.string as NSString
            let selected = ns.substring(with: sel)
            let body = selected.isEmpty ? "" : selected
            let wrapped = "```\n" + body + (body.hasSuffix("\n") || body.isEmpty
                                            ? "" : "\n") + "```"
            // Caret on the fence language slot when empty.
            let caret = selected.isEmpty
                ? NSRange(location: sel.location + 3, length: 0)
                : NSRange(location: sel.location,
                          length: (wrapped as NSString).length)
            replace(tv, sel, wrapped, select: caret)
        }

        private func insertLink(_ tv: NSTextView) {
            let sel = tv.selectedRange()
            let ns = tv.string as NSString
            let selected = ns.substring(with: sel)
            let placeholder = "url"
            let out = "[\(selected)](\(placeholder))"
            // Select the `url` placeholder so the user can paste over it.
            let urlStart = sel.location + 1 + (selected as NSString).length + 2
            replace(tv, sel, out,
                    select: NSRange(location: urlStart,
                                    length: (placeholder as NSString).length))
        }
    }
}
