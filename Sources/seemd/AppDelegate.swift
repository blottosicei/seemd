import AppKit
import SeemdCore

/// Handles Finder "Open With" / double-click and dock-drop document opens.
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// The URL passed before any window exists; consumed by the first window.
    static var launchURL: URL?

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { open(url) }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        open(URL(fileURLWithPath: filename))
        return true
    }

    private func open(_ url: URL) {
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        try? BookmarkStore().save(url)

        if NSApp.windows.contains(where: { $0.isVisible }) {
            NotificationCenter.default.post(name: .seemdOpenURL, object: url)
        } else {
            // No window yet — stash for the first RootView.
            AppDelegate.launchURL = url
        }
    }
}
