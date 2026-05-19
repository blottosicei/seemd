import Foundation

// MARK: - ThemeOverride

/// User-facing preference stored in UserDefaults.
public enum ThemeOverride: String, CaseIterable {
    case system, light, dark
}

// MARK: - EffectiveTheme

/// The resolved theme used for rendering.
public enum EffectiveTheme {
    case light, dark
}

// MARK: - ThemeResolver

public enum ThemeResolver {
    /// Resolves the effective theme from a user override and the current system appearance.
    /// - Parameters:
    ///   - override: The user-chosen override (.system follows the OS).
    ///   - systemIsDark: Whether the OS is currently in dark mode.
    /// - Returns: The effective theme to use for rendering.
    public static func resolve(override: ThemeOverride, systemIsDark: Bool) -> EffectiveTheme {
        switch override {
        case .system: return systemIsDark ? .dark : .light
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

// MARK: - ThemePalette

/// Semantic color palette expressed as CSS-style HEX strings.
public struct ThemePalette {
    public let windowBackground: String
    public let bodyText: String
    public let secondaryText: String
    public let accentLink: String
    public let codeBackground: String
    public let separator: String

    public init(
        windowBackground: String,
        bodyText: String,
        secondaryText: String,
        accentLink: String,
        codeBackground: String,
        separator: String
    ) {
        self.windowBackground = windowBackground
        self.bodyText = bodyText
        self.secondaryText = secondaryText
        self.accentLink = accentLink
        self.codeBackground = codeBackground
        self.separator = separator
    }

    /// Returns the canonical palette for the given effective theme.
    public static func palette(for theme: EffectiveTheme) -> ThemePalette {
        switch theme {
        case .light:
            return ThemePalette(
                windowBackground: "#FFFFFF",
                bodyText: "#24292F",
                secondaryText: "#57606A",
                accentLink: "#0969DA",
                codeBackground: "#F6F8FA",
                separator: "#D0D7DE"
            )
        case .dark:
            return ThemePalette(
                windowBackground: "#1E1E1E",
                bodyText: "#E6EDF3",
                secondaryText: "#8B949E",
                accentLink: "#58A6FF",
                codeBackground: "#1E1E1E",
                separator: "#30363D"
            )
        }
    }
}

// MARK: - ThemePreferences

/// UserDefaults-backed storage for the user's theme override.
public enum ThemePreferences {
    static let key = "seemd.themeOverride"

    /// Reads the stored override from the given defaults store, falling back to `.system`.
    public static func override(from defaults: UserDefaults = .standard) -> ThemeOverride {
        guard let raw = defaults.string(forKey: key),
              let value = ThemeOverride(rawValue: raw) else {
            return .system
        }
        return value
    }

    /// Writes the override to the given defaults store.
    public static func setOverride(_ override: ThemeOverride, in defaults: UserDefaults = .standard) {
        defaults.set(override.rawValue, forKey: key)
    }
}
