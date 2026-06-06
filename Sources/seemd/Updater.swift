import SwiftUI
import Combine
import Sparkle

/// Owns Sparkle's standard updater and exposes whether a manual check is
/// currently allowed, so the menu item can disable itself while a check or
/// install is already in flight.
///
/// Updates are verified by EdDSA signature (`SUPublicEDKey` in Info.plist),
/// not Apple notarization — this is what lets auto-update work without an
/// Apple Developer account. The feed and binaries are hosted on GitHub.
final class UpdaterViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    private let controller: SPUStandardUpdaterController

    init() {
        // startingUpdater: true begins scheduled background checks immediately
        // (cadence governed by SUScheduledCheckInterval in Info.plist).
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil)
        controller.updater
            .publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}

/// "Check for Updates…" menu item, wired under the application menu.
struct CheckForUpdatesCommand: View {
    @ObservedObject var updater: UpdaterViewModel

    var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
    }
}
