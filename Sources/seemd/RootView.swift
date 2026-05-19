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

    /// The document text supplied by `DocumentGroup`.
    let text: String
    /// The document's file URL (nil for unsaved/untitled, which a viewer
    /// never produces in practice).
    let fileURL: URL?

    init(text: String, fileURL: URL?) {
        self.text = text
        self.fileURL = fileURL
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color(hex: model.palette.separator,
                            fallback: Color.gray.opacity(0.3)))
                .frame(height: 1)
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
        .frame(minWidth: 640, minHeight: 480)
        .background(WindowAccessor())
        .environmentObject(model)
        .environmentObject(tableLayout)
        .preferredColorScheme(model.forcedColorScheme)
        .onAppear {
            model.updateSystemAppearance(isDark: systemColorScheme == .dark)
            model.load(text: text, url: fileURL)
        }
        .onChange(of: text) {
            model.load(text: text, url: fileURL)
        }
        .onChange(of: systemColorScheme) {
            model.updateSystemAppearance(isDark: systemColorScheme == .dark)
        }
        .onReceive(NotificationCenter.default.publisher(for: .seemdToggleSidebar)) { _ in
            withAnimation(.easeInOut(duration: 0.18)) {
                columnVisibility = (columnVisibility == .detailOnly) ? .all : .detailOnly
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .seemdCommand)) { note in
            handleCommand(note)
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
    static let seemdCommand = Notification.Name("seemd.command")
    static let seemdFocusSearch = Notification.Name("seemd.focusSearch")
}

enum SeemdCommand {
    case zoomIn, zoomOut, zoomReset, find
    case setTheme(ThemeOverride)
}
