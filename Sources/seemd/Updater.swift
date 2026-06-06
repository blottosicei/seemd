import SwiftUI
import Combine
import Sparkle

/// Owns Sparkle's standard updater and surfaces update state to the UI.
///
/// Updates are verified by EdDSA signature (`SUPublicEDKey` in Info.plist),
/// not Apple notarization — this is what lets auto-update work without an
/// Apple Developer account. Feed and binaries are hosted on GitHub.
///
/// Acts as the Sparkle *user-driver delegate* to implement "gentle reminders":
/// when a scheduled background check finds an update we suppress Sparkle's own
/// pop-up and instead publish `updateAvailableVersion`, which drives the
/// unobtrusive indicator pinned to the bottom of the sidebar. Clicking that
/// indicator (or the menu item) runs `checkForUpdates()`, which brings the
/// found update forward in Sparkle's standard install flow.
final class UpdaterViewModel: NSObject, ObservableObject, SPUStandardUserDriverDelegate {
    /// Whether a manual check is currently permitted (drives menu enablement).
    @Published var canCheckForUpdates = false
    /// Non-nil display version (e.g. "0.3.0") when an update is waiting; the
    /// sidebar badge observes this.
    @Published var updateAvailableVersion: String?

    private var controller: SPUStandardUpdaterController!

    override init() {
        super.init()
        // startingUpdater: true begins scheduled background checks immediately
        // (cadence governed by SUScheduledCheckInterval in Info.plist). The
        // controller weakly references this delegate, but SeemdApp retains the
        // view model for the app's lifetime, so it stays alive.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self)
        controller.updater
            .publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)

        // Force a background check right after launch so an available update
        // surfaces in the sidebar badge without the user opening the menu.
        // Sparkle recommends calling this immediately after starting the
        // updater; it routes through the gentle-reminder path (no pop-up),
        // respects the user's auto-check setting, and ignores the daily
        // interval throttle for this one launch-time check.
        if controller.updater.automaticallyChecksForUpdates {
            controller.updater.checkForUpdatesInBackground()
        }
    }

    /// Begin (or bring forward) the standard update flow. Used by both the
    /// menu item and the sidebar badge.
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }

    // MARK: - SPUStandardUserDriverDelegate (gentle reminders)

    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Return false so Sparkle never auto-presents a scheduled update; we show
    /// our own sidebar indicator instead and let the user act on it.
    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    /// Called when Sparkle decides whether it will present the update. On our
    /// gentle path it passes handleShowingUpdate == false, so we record the
    /// version and the badge appears.
    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        if !handleShowingUpdate {
            updateAvailableVersion = update.displayVersionString
        }
    }

    /// The user engaged the update (e.g. via our badge) — clear the indicator.
    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        updateAvailableVersion = nil
    }

    /// The update session ended (installed, dismissed, or failed) — clear it.
    func standardUserDriverWillFinishUpdateSession() {
        updateAvailableVersion = nil
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

/// Unobtrusive "Update available" pill pinned to the bottom of the sidebar.
/// Renders nothing until a background check finds a newer version.
struct UpdateAvailableBadge: View {
    @EnvironmentObject private var updater: UpdaterViewModel

    var body: some View {
        if let version = updater.updateAvailableVersion {
            Button {
                updater.checkForUpdates()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Update available: \(version)")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color.accentColor, in: Capsule())
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .help("A new version is available — click to update")
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
