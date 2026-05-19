import SwiftUI
import AppKit

/// Forces document windows to open as tabs by default and keeps a hairline
/// under the title/tab bar on every tab.
///
/// `DocumentGroup` honors the OS "Prefer tabs" preference (default: full-screen
/// only), so new documents open standalone. Giving every document window
/// `tabbingMode = .preferred` with a shared `tabbingIdentifier` — and merging a
/// freshly opened window into the existing tab group — makes "new document =
/// new tab" the default (PRD §3.7). Tabs can still be torn off (native), and
/// ⌘⇧N opens a fresh window.
///
/// A window's `titlebarSeparatorStyle` must be (re)applied as tabs are added
/// and switched: a window added to a tab group after creation, or activated
/// later, otherwise falls back to the system default and the header blends
/// into the tab strip. `TabWindowCoordinator` observes window activation and
/// reapplies the separator to all document windows so every tab is consistent.
struct WindowAccessor: NSViewRepresentable {
    static let sharedTabbingIdentifier = NSWindow.TabbingIdentifier("seemd.document")

    func makeNSView(context: Context) -> NSView {
        TabWindowCoordinator.shared.activate()
        let view = NSView()
        DispatchQueue.main.async { Self.configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.configure(nsView.window) }
    }

    /// Apply tabbing + separator to `window`, merging it into an existing
    /// document tab group if it is still standalone.
    static func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.tabbingMode = .preferred
        window.tabbingIdentifier = sharedTabbingIdentifier
        // The native title-bar separator misrenders with NavigationSplitView in
        // tabbed windows (absent on 2nd+ tabs, leaks into the sidebar). Disable
        // it; RootView draws its own consistent hairline atop the content.
        window.titlebarSeparatorStyle = .none

        if window.tabbedWindows == nil {
            let host = NSApp.windows.first { other in
                other !== window
                    && other.tabbingIdentifier == sharedTabbingIdentifier
                    && other.isVisible
                    && !other.isMiniaturized
            }
            if let host {
                host.addTabbedWindow(window, ordered: .above)
                window.makeKeyAndOrderFront(nil)
            }
        }

        // Keep the native separator disabled across the whole tab group: a
        // window joining late can otherwise reset it on its siblings.
        TabWindowCoordinator.applySeparatorToAllDocumentWindows()
    }
}

/// Reapplies the title-bar separator whenever any document window becomes
/// active, so tabs added or switched to after the first stay consistent.
final class TabWindowCoordinator {
    static let shared = TabWindowCoordinator()
    private var installed = false

    func activate() {
        guard !installed else { return }
        installed = true
        let nc = NotificationCenter.default
        for name in [NSWindow.didBecomeMainNotification,
                     NSWindow.didBecomeKeyNotification,
                     NSWindow.didUpdateNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { note in
                guard let window = note.object as? NSWindow,
                      window.tabbingIdentifier == WindowAccessor.sharedTabbingIdentifier
                else { return }
                window.titlebarSeparatorStyle = .none
            }
        }
    }

    static func applySeparatorToAllDocumentWindows() {
        for window in NSApp.windows
        where window.tabbingIdentifier == WindowAccessor.sharedTabbingIdentifier {
            window.titlebarSeparatorStyle = .none
        }
    }
}
