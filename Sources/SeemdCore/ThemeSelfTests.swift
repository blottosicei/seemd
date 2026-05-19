import Foundation

/// Self-test cases for US-007 Theme resolution.
public func themeCases() -> [TestCase] {
    [
        // MARK: ThemeResolver — all 6 combinations (3 overrides × 2 system states)

        TestCase("theme/resolve-system-light") { t in
            let result = ThemeResolver.resolve(override: .system, systemIsDark: false)
            t.expect(result == .light, "system override + light OS should resolve to .light")
        },
        TestCase("theme/resolve-system-dark") { t in
            let result = ThemeResolver.resolve(override: .system, systemIsDark: true)
            t.expect(result == .dark, "system override + dark OS should resolve to .dark")
        },
        TestCase("theme/resolve-light-os-light") { t in
            let result = ThemeResolver.resolve(override: .light, systemIsDark: false)
            t.expect(result == .light, "forced light override + light OS should resolve to .light")
        },
        TestCase("theme/resolve-light-os-dark") { t in
            let result = ThemeResolver.resolve(override: .light, systemIsDark: true)
            t.expect(result == .light, "forced light override + dark OS should still resolve to .light")
        },
        TestCase("theme/resolve-dark-os-light") { t in
            let result = ThemeResolver.resolve(override: .dark, systemIsDark: false)
            t.expect(result == .dark, "forced dark override + light OS should resolve to .dark")
        },
        TestCase("theme/resolve-dark-os-dark") { t in
            let result = ThemeResolver.resolve(override: .dark, systemIsDark: true)
            t.expect(result == .dark, "forced dark override + dark OS should resolve to .dark")
        },

        // MARK: ThemePalette — dark codeBackground

        TestCase("theme/dark-codeBackground-not-pure-black") { t in
            let dark = ThemePalette.palette(for: .dark)
            t.expect(dark.codeBackground != "#000000", "dark codeBackground must not be pure #000000")
        },
        TestCase("theme/dark-codeBackground-is-1E1E1E") { t in
            let dark = ThemePalette.palette(for: .dark)
            t.expectEqual(dark.codeBackground, "#1E1E1E", "dark codeBackground should be #1E1E1E")
        },
        TestCase("theme/light-codeBackground-is-F6F8FA") { t in
            let light = ThemePalette.palette(for: .light)
            t.expectEqual(light.codeBackground, "#F6F8FA", "light codeBackground should be #F6F8FA")
        },

        // MARK: ThemePreferences — round-trip via injected in-memory UserDefaults

        TestCase("theme/preferences-roundtrip-light") { t in
            let suite = "seemd.test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            ThemePreferences.setOverride(.light, in: defaults)
            t.expectEqual(ThemePreferences.override(from: defaults), .light, "round-trip .light")
            defaults.removePersistentDomain(forName: suite)
        },
        TestCase("theme/preferences-roundtrip-dark") { t in
            let suite = "seemd.test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            ThemePreferences.setOverride(.dark, in: defaults)
            t.expectEqual(ThemePreferences.override(from: defaults), .dark, "round-trip .dark")
            defaults.removePersistentDomain(forName: suite)
        },
        TestCase("theme/preferences-roundtrip-system") { t in
            let suite = "seemd.test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            ThemePreferences.setOverride(.system, in: defaults)
            t.expectEqual(ThemePreferences.override(from: defaults), .system, "round-trip .system")
            defaults.removePersistentDomain(forName: suite)
        },
        TestCase("theme/preferences-default-is-system") { t in
            let suite = "seemd.test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            // Nothing written — should fall back to .system
            t.expectEqual(ThemePreferences.override(from: defaults), .system, "missing key should default to .system")
            defaults.removePersistentDomain(forName: suite)
        },
    ]
}
