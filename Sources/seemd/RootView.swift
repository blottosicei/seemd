import SwiftUI
import SeemdCore

/// Window root: empty state or split view (TOC | document). Owns the
/// per-window `DocumentModel` and applies the resolved theme.
struct RootView: View {
    @StateObject private var model = DocumentModel()
    /// Per-window store for resizable table column widths. Shared with all
    /// `TableView`s in this window via `.environmentObject`; only tables
    /// observe it, so it cannot trigger block-tree re-renders.
    @StateObject private var tableLayout = TableLayoutStore()
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isEditing = false
    @FocusState private var searchFocused: Bool

    /// The editable document supplied by `DocumentGroup`. Mutating
    /// `document.text` is what marks the window dirty and feeds Undo/Save.
    @Binding var document: MarkdownFileDocument
    /// The document's file URL (nil for unsaved/untitled).
    let fileURL: URL?

    /// Debounces live-preview reparsing so rapid keystrokes don't reparse
    /// per character. Reuses the SeemdCore `Debouncer`.
    private let previewDebouncer = Debouncer(interval: 0.2)

    init(document: Binding<MarkdownFileDocument>, fileURL: URL?) {
        self._document = document
        self.fileURL = fileURL
    }

    /// Binding into the document's text — the single source of truth while
    /// editing; writing it drives DocumentGroup dirty/undo/save.
    private var textBinding: Binding<String> {
        Binding(
            get: { document.text },
            set: { document.text = $0 }
        )
    }

    private var editorFontSize: CGFloat { 14.0 * CGFloat(model.zoom) }

    private var searchMatchCount: Int {
        guard !model.searchQuery.isEmpty else { return 0 }
        return SearchEngine.matchCount(in: model.source,
                                       query: model.searchQuery)
    }

    @ViewBuilder
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Find", text: $model.searchQuery)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .focused($searchFocused)
            if !model.searchQuery.isEmpty {
                Text("\(searchMatchCount)")
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

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color(hex: model.palette.separator,
                            fallback: Color.gray.opacity(0.3)))
                .frame(height: 1)
            if isEditing {
                VStack(spacing: 0) {
                    // Centered formatting bar as a dedicated content row
                    // (fully layout-controlled — avoids the unreliable
                    // `.principal` window-toolbar centering).
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        FormattingButtons()
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.bar)
                    Divider()
                        .overlay(Color(hex: model.palette.separator,
                                       fallback: Color.gray.opacity(0.3)))
                    HSplitView {
                        MarkdownEditor(text: textBinding,
                                       fontSize: editorFontSize,
                                       palette: model.palette,
                                       model: model)
                            .frame(minWidth: 280)
                        PreviewPane(model: model)
                            .frame(minWidth: 280)
                    }
                }
                .navigationTitle(model.documentTitle)
                .navigationSubtitle(model.documentSubtitle)
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    TOCSidebar(model: model)
                        .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 360)
                } detail: {
                    DocumentView(model: model)
                        .navigationTitle(model.documentTitle)
                        .navigationSubtitle(model.documentSubtitle)
                }
                .navigationSplitViewStyle(.balanced)
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .background(WindowAccessor())
        .environmentObject(model)
        .environmentObject(tableLayout)
        .preferredColorScheme(model.forcedColorScheme)
        // Formatting bar centered (.principal) like before; the edit/preview
        // toggle is pinned to the far-right (.primaryAction, declared last) so
        // it stays in a fixed position across modes. Search sits left of the
        // toggle in preview mode. All in one view → deterministic ordering.
        // Window toolbar holds only the trailing group: [search (preview)] +
        // the edit/preview toggle declared LAST so it stays pinned far-right
        // in a fixed position across modes. The formatting bar is a separate
        // centered content row (see body), not a toolbar item.
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if !isEditing {
                    searchField
                }
                Button {
                    toggleEditing()
                } label: {
                    Image(systemName: isEditing ? "eye" : "square.and.pencil")
                }
                .help(isEditing ? "Preview (⌘E)" : "Edit (⌘E)")
            }
        }
        .onAppear {
            model.updateSystemAppearance(isDark: systemColorScheme == .dark)
            model.load(text: document.text, url: fileURL)
        }
        .onChange(of: document.text) {
            if isEditing {
                // The editor is the source of truth: reparse the preview
                // (debounced) WITHOUT resetting scroll or churning the
                // active-heading slug. Mark unsaved so the file watcher
                // cannot clobber the edit.
                model.hasUnsavedEdits = true
                let latest = document.text
                previewDebouncer.schedule {
                    Task { @MainActor in
                        model.applyEditedSource(latest)
                    }
                }
            } else {
                // External/programmatic change (e.g. revert/open): full load.
                model.load(text: document.text, url: fileURL)
            }
        }
        // NOTE: preview → editor live sync is NOT driven from
        // `activeHeadingSlug` any more (that snapped the editor to a heading
        // anchor). `ScrollSyncCoordinator` now tracks the preview's real
        // NSScrollView and moves the editor continuously by offset
        // interpolation. `activeHeadingSlug` is still maintained for the TOC
        // highlight and reload scroll preservation, and `model.scrollTarget`
        // still drives TOC sidebar clicks (preview-only mode) untouched.
        .onChange(of: systemColorScheme) {
            model.updateSystemAppearance(isDark: systemColorScheme == .dark)
        }
        .onReceive(NotificationCenter.default.publisher(for: .seemdToggleSidebar)) { _ in
            withAnimation(.easeInOut(duration: 0.18)) {
                columnVisibility = (columnVisibility == .detailOnly) ? .all : .detailOnly
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .seemdToggleEdit)) { _ in
            toggleEditing()
        }
        .onReceive(NotificationCenter.default.publisher(for: .seemdFocusSearch)) { _ in
            if !isEditing { searchFocused = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .seemdCommand)) { note in
            handleCommand(note)
        }
    }

    private func toggleEditing() {
        withAnimation(.easeInOut(duration: 0.18)) {
            isEditing.toggle()
        }
        if isEditing {
            // Sync the preview to the current text on entering edit mode.
            model.applyEditedSource(document.text)
        }
    }

    private func handleCommand(_ note: Notification) {
        guard let cmd = note.object as? SeemdCommand else { return }
        switch cmd {
        case .zoomIn:    model.zoomIn()
        case .zoomOut:   model.zoomOut()
        case .zoomReset: model.zoomReset()
        case .find:
            NotificationCenter.default.post(name: .seemdFocusSearch, object: nil)
        case let .setTheme(override):
            model.themeOverride = override
        }
    }
}

// MARK: - Cross-cutting notifications

extension Notification.Name {
    static let seemdToggleSidebar = Notification.Name("seemd.toggleSidebar")
    static let seemdToggleEdit = Notification.Name("seemd.toggleEdit")
    static let seemdCommand = Notification.Name("seemd.command")
    static let seemdFocusSearch = Notification.Name("seemd.focusSearch")
}

enum SeemdCommand {
    case zoomIn, zoomOut, zoomReset, find
    case setTheme(ThemeOverride)
}
