import SwiftUI
import SeemdCore

/// Renders a single `RenderBlock` with GitHub-style typography. Recurses for
/// nested containers (lists, blockquotes, task items).
struct BlockView: View {
    let block: RenderBlock
    @ObservedObject var model: DocumentModel

    private var palette: ThemePalette { model.palette }
    private var baseSize: CGFloat { 16.0 * CGFloat(model.zoom) }

    private var renderer: InlineRenderer {
        InlineRenderer(
            palette: palette,
            baseFontSize: baseSize,
            searchQuery: model.searchQuery,
            baseDirectory: model.documentDirectory
        )
    }

    private var bodyColor: Color { Color(hex: palette.bodyText, fallback: .primary) }
    private var secondaryColor: Color { Color(hex: palette.secondaryText, fallback: .secondary) }
    private var separatorColor: Color { Color(hex: palette.separator, fallback: Color.gray.opacity(0.3)) }

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
            CodeBlockView(code: code, language: language, model: model)

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
                      renderer: renderer, separator: separatorColor)

        case .thematicBreak:
            Divider().overlay(separatorColor).padding(.vertical, 8)
        }
    }

    // MARK: - Heading

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

    @ViewBuilder
    private func headingView(level: Int, inlines: [InlineNode]) -> some View {
        let size = baseSize * headingScale(level)
        VStack(alignment: .leading, spacing: 4) {
            Text(renderer.attributed(inlines))
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(bodyColor)
                .textSelection(.enabled)
            if level <= 2 {
                Divider().overlay(separatorColor)
            }
        }
        .padding(.top, level <= 2 ? 12 : 8)
        .padding(.bottom, 2)
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
                    BlockView(block: b, model: model)
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
                            BlockView(block: b, model: model)
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
                    BlockView(block: b, model: model)
                }
            }
        }
    }
}

// MARK: - Code block

private struct CodeBlockView: View {
    let code: String
    let language: String?
    @ObservedObject var model: DocumentModel
    @State private var tokens: [HighlightToken] = []

    private var baseSize: CGFloat { 16.0 * CGFloat(model.zoom) * 0.92 }
    private var codeBG: Color { Color(hex: model.palette.codeBackground, fallback: Color.gray.opacity(0.12)) }
    private var separator: Color { Color(hex: model.palette.separator, fallback: Color.gray.opacity(0.3)) }

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
        .task(id: TaskKey(code: code, dark: model.effectiveTheme == .dark)) {
            await refresh()
        }
    }

    private struct TaskKey: Equatable { let code: String; let dark: Bool }

    private var highlighted: AttributedString {
        guard !tokens.isEmpty else {
            var a = AttributedString(code)
            a.foregroundColor = Color(hex: model.palette.bodyText, fallback: .primary)
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
            model.highlightedTokens(code: code, language: language) { t in
                self.tokens = t
                cont.resume()
            }
        }
    }

    /// Map Splash token kinds to theme-aware colors.
    private func color(for kind: String) -> Color {
        let dark = model.effectiveTheme == .dark
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
        default:            return Color(hex: model.palette.bodyText, fallback: .primary)
        }
    }
}

// MARK: - Table

private struct TableView: View {
    let header: [[InlineNode]]
    let rows: [[[InlineNode]]]
    let alignments: [ColumnAlignment]
    let renderer: InlineRenderer
    let separator: Color

    private func alignment(_ col: Int) -> Alignment {
        guard col < alignments.count else { return .leading }
        switch alignments[col] {
        case .center: return .center
        case .right:  return .trailing
        default:      return .leading
        }
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(header.enumerated()), id: \.offset) { col, cell in
                    cellView(cell, col: col, header: true)
                }
            }
            Divider().overlay(separator)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { col, cell in
                        cellView(cell, col: col, header: false)
                    }
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6).stroke(separator, lineWidth: 1)
        )
        .padding(.vertical, 4)
    }

    private func cellView(_ cell: [InlineNode], col: Int, header: Bool) -> some View {
        Text(renderer.attributed(cell))
            .fontWeight(header ? .semibold : .regular)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: alignment(col))
            .textSelection(.enabled)
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
