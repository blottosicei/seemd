import SwiftUI
import SeemdCore

@main
struct SeemdApp: App {
    @State private var themeOverride: ThemeOverride = ThemePreferences.override()
    @StateObject private var updater = UpdaterViewModel()

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownFileDocument()) { config in
            RootView(document: config.$document, fileURL: config.fileURL)
        }
        .windowToolbarStyle(.unified)
        .commands {
            // Application menu — adds "Check for Updates…" under "About seemd".
            CommandGroup(after: .appInfo) {
                CheckForUpdatesCommand(updater: updater)
            }

            // View menu.
            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") {
                    NotificationCenter.default.post(
                        name: .seemdToggleSidebar, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command, .option])

                Button("Toggle Edit") {
                    NotificationCenter.default.post(
                        name: .seemdToggleEdit, object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)

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

        Settings {
            SettingsView()
        }
    }

    private func post(_ command: SeemdCommand) {
        NotificationCenter.default.post(name: .seemdCommand, object: command)
    }
}
