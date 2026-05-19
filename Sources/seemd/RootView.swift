import SwiftUI
import SeemdCore

/// Window root: empty state or split view (TOC | document). Owns the
/// per-window `DocumentModel` and applies the resolved theme.
struct RootView: View {
    @StateObject private var model = DocumentModel()
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    /// A document to open as soon as the window appears (set by AppDelegate).
    let pendingURL: URL?

    init(pendingURL: URL? = nil) {
        self.pendingURL = pendingURL
    }

    var body: some View {
        Group {
            if model.hasDocument {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    TOCSidebar(model: model)
                        .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 360)
                } detail: {
                    DocumentView(model: model)
                        .navigationTitle(model.documentTitle)
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                EmptyStateView(model: model)
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .environmentObject(model)
        .preferredColorScheme(model.forcedColorScheme)
        .onAppear {
            model.updateSystemAppearance(isDark: systemColorScheme == .dark)
            if let pendingURL { model.open(pendingURL) }
        }
        .onChange(of: systemColorScheme) {
            model.updateSystemAppearance(isDark: systemColorScheme == .dark)
        }
        .onReceive(NotificationCenter.default.publisher(for: .seemdOpenURL)) { note in
            if let url = note.object as? URL { model.open(url) }
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
    static let seemdOpenURL = Notification.Name("seemd.openURL")
    static let seemdToggleSidebar = Notification.Name("seemd.toggleSidebar")
    static let seemdCommand = Notification.Name("seemd.command")
    static let seemdFocusSearch = Notification.Name("seemd.focusSearch")
}

enum SeemdCommand {
    case zoomIn, zoomOut, zoomReset, find
    case setTheme(ThemeOverride)
}
