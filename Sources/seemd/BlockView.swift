import SwiftUI
import AppKit
import SeemdCore

/// Renders a single `RenderBlock` with GitHub-style typography. Recurses for
/// nested containers (lists, blockquotes, task items).
struct BlockView: View {
    let block: RenderBlock
    let context: RenderContext
    let highlight: HighlightProvider

    private var palette: ThemePalette { context.palette }
    private var baseSize: CGFloat { context.baseFontSize }

    private var renderer: InlineRenderer { context.renderer }

    private var bodyColor: Color { Color(hex: palette.bodyText, fallback: .primary) }
    private var secondaryColor: Color { Color(hex: palette.secondaryText, fallback: .secondary) }
    private var separatorColor: Color { Color(hex: palette.separator, fallback: Color.gray.opacity(0.3)) }
    /// Brighter, theme-aware border color used only for tables (outer rounded
    /// stroke + header divider + visible inner column dividers + row dividers)
    /// so the table reads as a distinct structure rather than blending into
    /// the dim paragraph-divider tone.
    private var tableBorderColor: Color { bodyColor.opacity(0.28) }

    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        switch block {
        case let .heading(level, slug, inlines):
            headingView(level: level, inlines: inlines)
                .id(slug)
                .background(HeadingFramePreference.reporter(slug: slug))

        case let .paragraph(inlines):
            paragraphView(inlines)

        case let .codeBlock(language, code):
            CodeBlockView(code: code, language: language,
                          context: context, highlight: highlight)

        case let .blockQuote(blocks):
            blockQuoteView(blocks)

        case let .unorderedList(items):
            listView(items: items, ordered: false, start: 1)

        case let .orderedList(start, items):
            listView(items: items, ordered: true, start: start)

        case let .taskListItem(checked, blocks):
            taskItemView(checked: checked, blocks: blocks)

        case let .table(header, rows, alignments):
            TableView(header: header, rows: rows, alignments: alignments,
                      renderer: renderer,
                      separator: separatorColor,
                      border: tableBorderColor)

        case .thematicBreak:
            Divider().overlay(separatorColor).padding(.vertical, 8)
        }
    }

    // MARK: - Heading

    /// GitHub Markdown CSS scale (what VS Code's preview uses): h1 2em … h6 .85em.
    private func headingScale(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 2.0
        case 2: return 1.5
        case 3: return 1.25
        case 4: return 1.0
        case 5: return 0.875
        default: return 0.85
        }
    }

    /// Stronger weight contrast than GitHub's flat 600 so the hierarchy reads
    /// clearly: H1/H2 bold, H3–H6 semibold (body stays regular).
    private func headingWeight(_ level: Int) -> Font.Weight {
        level <= 2 ? .bold : .semibold
    }

    @ViewBuilder
    private func headingView(level: Int, inlines: [InlineNode]) -> some View {
        let size = baseSize * headingScale(level)
        // Build a renderer at the heading size+weight so they are baked into
        // the AttributedString runs (run-level font overrides .font(), which is
        // why headings previously rendered at body size).
        let hRenderer = context.renderer(fontSize: size,
                                         weight: headingWeight(level))
        let color = level >= 6 ? secondaryColor : bodyColor
        VStack(alignment: .leading, spacing: 4) {
            Text(hRenderer.attributed(inlines))
                .foregroundStyle(color)
                .lineSpacing(size * 0.12)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if level <= 2 {
                Divider().overlay(separatorColor)
            }
        }
        .padding(.top, level == 1 ? 24 : level == 2 ? 20 : level <= 3 ? 14 : 10)
        .padding(.bottom, level <= 2 ? 6 : 2)
    }

    // MARK: - Paragraph

    @ViewBuilder
    private func paragraphView(_ inlines: [InlineNode]) -> some View {
        if renderer.isLoneImage(inlines),
           let img = renderer.images(in: inlines).first {
            MarkdownImageView(alt: img.alt, url: img.url)
        } else {
            Text(renderer.attributed(inlines))
                .font(.system(size: baseSize))
                .foregroundStyle(bodyColor)
                .lineSpacing(baseSize * 0.6)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Blockquote

    @ViewBuilder
    private func blockQuoteView(_ blocks: [RenderBlock]) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(separatorColor)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                    BlockView(block: b, context: context, highlight: highlight)
                }
            }
            .padding(.leading, 12)
            .foregroundStyle(secondaryColor)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Lists

    @ViewBuilder
    private func listView(items: [[RenderBlock]], ordered: Bool, start: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, itemBlocks in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    marker(ordered: ordered, index: idx, start: start, itemBlocks: itemBlocks)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(itemBlocks.enumerated()), id: \.offset) { _, b in
                            BlockView(block: b, context: context, highlight: highlight)
                        }
                    }
                }
            }
        }
        .padding(.leading, 8)
    }

    @ViewBuilder
    private func marker(ordered: Bool, index: Int, start: Int,
                        itemBlocks: [RenderBlock]) -> some View {
        // Task-list items render their own checkbox; suppress bullet.
        if case .taskListItem = itemBlocks.first {
            EmptyView()
        } else if ordered {
            Text("\(start + index).")
                .font(.system(size: baseSize, design: .default).monospacedDigit())
                .foregroundStyle(secondaryColor)
        } else {
            Text("•")
                .font(.system(size: baseSize))
                .foregroundStyle(secondaryColor)
        }
    }

    // MARK: - Task item

    @ViewBuilder
    private func taskItemView(checked: Bool, blocks: [RenderBlock]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .foregroundStyle(checked ? Color(hex: palette.accentLink, fallback: .accentColor) : secondaryColor)
                .font(.system(size: baseSize))
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                    BlockView(block: b, context: context, highlight: highlight)
                }
            }
        }
    }
}

// MARK: - Code block

private struct CodeBlockView: View {
    let code: String
    let language: String?
    let context: RenderContext
    let highlight: HighlightProvider
    @State private var tokens: [HighlightToken] = []

    private var baseSize: CGFloat { context.baseFontSize * 0.92 }
    private var codeBG: Color { Color(hex: context.palette.codeBackground, fallback: Color.gray.opacity(0.12)) }
    private var separator: Color { Color(hex: context.palette.separator, fallback: Color.gray.opacity(0.3)) }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(highlighted)
                .font(.system(size: baseSize, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
        }
        .background(codeBG)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(separator, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.vertical, 4)
        .task(id: TaskKey(code: code, dark: context.isDark)) {
            await refresh()
        }
    }

    private struct TaskKey: Equatable { let code: String; let dark: Bool }

    private var highlighted: AttributedString {
        guard !tokens.isEmpty else {
            var a = AttributedString(code)
            a.foregroundColor = Color(hex: context.palette.bodyText, fallback: .primary)
            return a
        }
        var result = AttributedString()
        for token in tokens {
            var piece = AttributedString(token.text)
            piece.foregroundColor = color(for: token.kind)
            result.append(piece)
        }
        return result
    }

    private func refresh() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            highlight(code, language) { t in
                self.tokens = t
                cont.resume()
            }
        }
    }

    /// Map Splash token kinds to theme-aware colors.
    private func color(for kind: String) -> Color {
        let dark = context.isDark
        switch kind {
        case "keyword":     return dark ? Color(hex: "#FF7AB2")! : Color(hex: "#CF222E")!
        case "string":      return dark ? Color(hex: "#A5D6FF")! : Color(hex: "#0A3069")!
        case "type":        return dark ? Color(hex: "#79C0FF")! : Color(hex: "#0550AE")!
        case "call":        return dark ? Color(hex: "#D2A8FF")! : Color(hex: "#8250DF")!
        case "number":      return dark ? Color(hex: "#79C0FF")! : Color(hex: "#0550AE")!
        case "comment":     return dark ? Color(hex: "#8B949E")! : Color(hex: "#6E7781")!
        case "property":    return dark ? Color(hex: "#79C0FF")! : Color(hex: "#0550AE")!
        case "dotAccess":   return dark ? Color(hex: "#79C0FF")! : Color(hex: "#0550AE")!
        case "preprocessing": return dark ? Color(hex: "#FFA657")! : Color(hex: "#953800")!
        default:            return Color(hex: context.palette.bodyText, fallback: .primary)
        }
    }
}

// MARK: - Table

/// Notion-style table with explicit per-column widths and draggable dividers.
///
/// This view is a LEAF: it is the only place that observes `TableLayoutStore`
/// (via `@EnvironmentObject`). Width drags re-render this `TableView` only — the
/// store never propagates into `BlockView`/`DocumentView`, and its keys are
/// derived from immutable table content, so there is no scroll-spy / render
/// feedback loop. `RenderContext` is untouched (width is layout, not a
/// rendering input).
private struct TableView: View {
    let header: [[InlineNode]]
    let rows: [[[InlineNode]]]
    let alignments: [ColumnAlignment]
    let renderer: InlineRenderer
    /// Dim color used only for paragraph-level separators in context.
    let separator: Color
    /// Brighter border color for outer stroke, header divider, row dividers,
    /// and visible inner column dividers — makes the table read as a distinct
    /// structure.
    let border: Color

    @EnvironmentObject private var layout: TableLayoutStore

    // Resize constraints / divider geometry.
    private let minColumnWidth: CGFloat = 48
    private let maxColumnWidth: CGFloat = 800
    private let dividerHitWidth: CGFloat = 8
    /// Generous cap for the auto (no-wrap) default width so only pathologically
    /// long cells ever wrap; normal content keeps its natural single-line width
    /// and the table scrolls horizontally if the total exceeds the viewport.
    private let maxNaturalWidth: CGFloat = 720
    /// Horizontal cell padding (12 left + 12 right) plus a small anti-clip fudge.
    private let cellPadding: CGFloat = 24 + 4

    private var columnCount: Int { header.count }

    /// Stable key derived from immutable table content: column count + joined
    /// header plaintext + row count. Survives LazyVStack recycling and tab
    /// switches; content-derived so it cannot cause a feedback loop.
    private var tableKey: String {
        let headerText = header
            .map { String(renderer.attributed($0).characters) }
            .joined(separator: "\u{1F}")
        return "\(columnCount)\u{1E}\(headerText)\u{1E}\(rows.count)"
    }

    /// Measured single-line width of `s` in the cell's actual font. Uses real
    /// text metrics (not a per-character estimate) so CJK/Korean full-width
    /// glyphs are sized correctly and don't get force-wrapped.
    private func textWidth(_ s: String, header: Bool) -> CGFloat {
        let font = NSFont.systemFont(ofSize: renderer.baseFontSize,
                                     weight: header ? .semibold : .regular)
        // Widest line if the cell happens to contain hard breaks.
        let widest = s.split(separator: "\n", omittingEmptySubsequences: false)
            .map { (String($0) as NSString)
                .size(withAttributes: [.font: font]).width }
            .max() ?? 0
        return ceil(widest)
    }

    /// Default width = the column's natural no-wrap width (widest cell), so
    /// cells never wrap by default. Only a pathologically long cell is capped
    /// (`maxNaturalWidth`); overflow is handled by horizontal scrolling, never
    /// by shrinking columns into wrapping.
    private func defaultWidth(col: Int) -> CGFloat {
        func cellWidth(_ nodes: [InlineNode], header: Bool) -> CGFloat {
            textWidth(String(renderer.attributed(nodes).characters),
                      header: header)
        }
        var natural: CGFloat = col < header.count
            ? cellWidth(header[col], header: true) : 0
        for row in rows where col < row.count {
            natural = max(natural, cellWidth(row[col], header: false))
        }
        let target = natural + cellPadding
        return min(max(target, minColumnWidth + 40), maxNaturalWidth)
    }

    private var defaultWidths: [CGFloat] {
        (0..<columnCount).map { defaultWidth(col: $0) }
    }

    /// Current widths from the store, or the computed defaults.
    private var widths: [CGFloat] {
        if let stored = layout.widths(for: tableKey),
           stored.count == columnCount {
            return stored
        }
        return defaultWidths
    }

    private func alignment(_ col: Int) -> Alignment {
        guard col < alignments.count else { return .leading }
        switch alignments[col] {
        case .center: return .center
        case .right:  return .trailing
        default:      return .leading
        }
    }

    var body: some View {
        let cols = widths
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                rowView(cells: header, widths: cols, header: true)
                // Crisp 1pt header underline in the prominent border color.
                Rectangle().fill(border).frame(height: 1)
                ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                    rowView(cells: row, widths: cols, header: false)
                    if idx < rows.count - 1 {
                        // Row inter-dividers use the same prominent border
                        // color so rows read as clearly separated.
                        Rectangle().fill(border).frame(height: 1)
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                dividerOverlay(widths: cols)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(border, lineWidth: 2)
                    .allowsHitTesting(false)
            )
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func rowView(cells: [[InlineNode]], widths cols: [CGFloat],
                         header: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<columnCount, id: \.self) { col in
                Text(col < cells.count
                     ? renderer.attributed(cells[col]) : AttributedString())
                    .fontWeight(header ? .semibold : .regular)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(width: cols[col], alignment: alignment(col))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Thin (1pt visible, ~8pt hit) draggable dividers between columns, laid
    /// out positionally (no offset math, no ScrollView gesture conflict). Drag
    /// adjusts the LEFT column's width live; double-click resets it.
    @ViewBuilder
    private func dividerOverlay(widths cols: [CGFloat]) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<columnCount, id: \.self) { col in
                Color.clear
                    .frame(width: cols[col])
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: .trailing) {
                        // Handle on every column boundary; the LAST column's
                        // handle stays hittable for resize but draws no line,
                        // so the outer rounded-rect stroke is the only visible
                        // line at the right edge (no doubled seam).
                        ColumnDivider(
                            color: border,
                            hitWidth: dividerHitWidth,
                            drawsLine: col < columnCount - 1,
                            currentWidth: cols[col],
                            onResize: { newWidth in
                                setColumnWidth(col: col, to: newWidth,
                                               base: cols)
                            },
                            onReset: { resetWidth(col: col) }
                        )
                        // Straddle the column boundary so the hit area is
                        // centered on the visible seam.
                        .offset(x: dividerHitWidth / 2)
                    }
            }
        }
    }

    private func setColumnWidth(col: Int, to newWidth: CGFloat,
                                base: [CGFloat]) {
        guard col < base.count else { return }
        var next = base
        next[col] = min(max(newWidth, minColumnWidth), maxColumnWidth)
        layout.setWidths(next, for: tableKey)
    }

    private func resetWidth(col: Int) {
        var next = widths
        guard col < next.count else { return }
        next[col] = defaultWidth(col: col)
        layout.setWidths(next, for: tableKey)
    }
}

/// A single draggable column divider: 1pt visible line inside an ~8pt hit area,
/// resize cursor on hover, live drag, double-click reset.
private struct ColumnDivider: View {
    let color: Color
    let hitWidth: CGFloat
    /// Whether to render the visible 1pt line. The last column's handle stays
    /// hittable for resize but draws no line, so the outer rounded-rect stroke
    /// is the only visible vertical at the table's right edge (no doubled seam).
    let drawsLine: Bool
    /// The column's current width, snapshotted at drag start.
    let currentWidth: CGFloat
    /// Absolute new width for the column (already mouse-tracked).
    let onResize: (CGFloat) -> Void
    let onReset: () -> Void

    /// Column width captured at gesture start; new width = start + global
    /// translation, so the line tracks the mouse 1:1 and never drifts even as
    /// the divider itself moves with the growing column.
    @State private var startWidth: CGFloat?
    /// Guards `NSCursor` push/pop so they stay balanced across rebuilds.
    @State private var cursorPushed = false

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: hitWidth)
            .frame(maxHeight: .infinity)
            .overlay {
                if drawsLine {
                    Rectangle()
                        .fill(color)
                        .frame(width: 1)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    if !cursorPushed {
                        NSCursor.resizeLeftRight.push()
                        cursorPushed = true
                    }
                case .ended:
                    if cursorPushed {
                        NSCursor.pop()
                        cursorPushed = false
                    }
                }
            }
            // High priority so the drag wins over the enclosing horizontal
            // ScrollView's pan gesture. Global coordinate space so translation
            // is the raw pointer delta, unaffected by this divider moving as
            // the column grows (the cause of the runaway drift/jitter).
            .highPriorityGesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let base = startWidth ?? currentWidth
                        if startWidth == nil { startWidth = base }
                        onResize(base + value.translation.width)
                    }
                    .onEnded { _ in startWidth = nil }
            )
            .onTapGesture(count: 2) { onReset() }
            .onDisappear {
                if cursorPushed { NSCursor.pop(); cursorPushed = false }
            }
    }
}

// MARK: - Image

private struct MarkdownImageView: View {
    let alt: String
    let url: URL?

    var body: some View {
        Group {
            if let url, url.isFileURL {
                if let nsImage = NSImage(contentsOf: url) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                } else {
                    placeholder
                }
            } else if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    case .failure:
                        placeholder
                    case .empty:
                        ProgressView()
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var placeholder: some View {
        HStack(spacing: 6) {
            Image(systemName: "photo")
            Text(alt.isEmpty ? "image" : alt)
        }
        .foregroundStyle(.secondary)
        .font(.callout)
    }
}

// MARK: - Heading frame preference (scroll-spy)

/// App-internal frame snapshot used by the SwiftUI PreferenceKey machinery.
/// Uses CGFloat to match GeometryReader output directly.
struct AppHeadingFrame: Equatable {
    let slug: String
    let minY: CGFloat
}

struct HeadingFramePreferenceKey: PreferenceKey {
    static var defaultValue: [AppHeadingFrame] = []
    static func reduce(value: inout [AppHeadingFrame], nextValue: () -> [AppHeadingFrame]) {
        value.append(contentsOf: nextValue())
    }
}

enum HeadingFramePreference {
    static func reporter(slug: String) -> some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: HeadingFramePreferenceKey.self,
                value: [AppHeadingFrame(slug: slug,
                                        minY: geo.frame(in: .named("docScroll")).minY)]
            )
        }
    }
}
