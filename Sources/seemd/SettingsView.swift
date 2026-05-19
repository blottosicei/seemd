import SwiftUI
import SeemdCore

/// The ⌘, Settings window. Minimal per PRD §5.6: preview content width and a
/// fill-window-width toggle, plus the existing theme override for consistency.
/// All values persist to UserDefaults; open documents observe the same keys via
/// `@AppStorage` so changes apply live.
struct SettingsView: View {
    @AppStorage(ContentWidthPreferences.widthKey)
    private var contentWidth: Double = ContentWidthPreferences.defaultWidth

    @AppStorage(ContentWidthPreferences.fillKey)
    private var fillWindowWidth: Bool = false

    @State private var themeOverride: ThemeOverride = ThemePreferences.override()

    var body: some View {
        Form {
            Section("Preview") {
                Toggle("Fill window width", isOn: $fillWindowWidth)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Content width")
                        Spacer()
                        Text("\(Int(displayWidth)) pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(
                        value: $contentWidth,
                        in: ContentWidthPreferences.minWidth...ContentWidthPreferences.maxWidth,
                        step: 20
                    )
                    .disabled(fillWindowWidth)
                }
            }

            Section("Appearance") {
                Picker("Theme", selection: $themeOverride) {
                    Text("System").tag(ThemeOverride.system)
                    Text("Light").tag(ThemeOverride.light)
                    Text("Dark").tag(ThemeOverride.dark)
                }
                .onChange(of: themeOverride) {
                    ThemePreferences.setOverride(themeOverride)
                    NotificationCenter.default.post(
                        name: .seemdCommand,
                        object: SeemdCommand.setTheme(themeOverride))
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .navigationTitle("Settings")
    }

    /// Slider value clamped to the allowed range for display.
    private var displayWidth: Double {
        min(max(contentWidth, ContentWidthPreferences.minWidth),
            ContentWidthPreferences.maxWidth)
    }
}
