import SwiftUI
import UniformTypeIdentifiers
import SeemdCore

@main
struct SeemdApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var themeOverride: ThemeOverride = ThemePreferences.override()

    var body: some Scene {
        WindowGroup {
            RootView(pendingURL: AppDelegate.launchURL)
                .onAppear { AppDelegate.launchURL = nil }
        }
        .windowToolbarStyle(.unified)
        .commands {
            // File menu.
            CommandGroup(replacing: .newItem) {
                Button("New Window") {
                    NSWorkspace.shared.open(Bundle.main.bundleURL)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("Open…") { Self.openPanel() }
                    .keyboardShortcut("o", modifiers: .command)

                Menu("Open Recent") {
                    let recents = NSDocumentController.shared.recentDocumentURLs
                    if recents.isEmpty {
                        Text("No Recent Documents").disabled(true)
                    } else {
                        ForEach(recents, id: \.self) { url in
                            Button(url.lastPathComponent) {
                                NotificationCenter.default.post(
                                    name: .seemdOpenURL, object: url)
                            }
                        }
                        Divider()
                        Button("Clear Menu") {
                            NSDocumentController.shared.clearRecentDocuments(nil)
                        }
                    }
                }
            }

            // View menu.
            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") {
                    NotificationCenter.default.post(
                        name: .seemdToggleSidebar, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command, .option])

                Divider()

                Button("Zoom In") { post(.zoomIn) }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Zoom Out") { post(.zoomOut) }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Actual Size") { post(.zoomReset) }
                    .keyboardShortcut("0", modifiers: .command)

                Divider()

                Button("Find") { post(.find) }
                    .keyboardShortcut("f", modifiers: .command)
            }

            // Theme menu.
            CommandMenu("Theme") {
                Picker("Appearance", selection: $themeOverride) {
                    Text("System").tag(ThemeOverride.system)
                    Text("Light").tag(ThemeOverride.light)
                    Text("Dark").tag(ThemeOverride.dark)
                }
                .pickerStyle(.inline)
                .onChange(of: themeOverride) {
                    ThemePreferences.setOverride(themeOverride)
                    NotificationCenter.default.post(
                        name: .seemdCommand,
                        object: SeemdCommand.setTheme(themeOverride))
                }
            }
        }
    }

    private func post(_ command: SeemdCommand) {
        NotificationCenter.default.post(name: .seemdCommand, object: command)
    }

    static func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        var types: [UTType] = [.plainText]
        if let md = UTType("net.daringfireball.markdown") { types.append(md) }
        panel.allowedContentTypes = types
        if panel.runModal() == .OK, let url = panel.url {
            NotificationCenter.default.post(name: .seemdOpenURL, object: url)
        }
    }
}
