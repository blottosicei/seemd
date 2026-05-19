import SwiftUI

extension Color {
    /// Creates a color from a `#RRGGBB` or `#RRGGBBAA` hex string.
    /// Returns `nil` for malformed input.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }

        guard s.count == 6 || s.count == 8,
              let value = UInt64(s, radix: 16) else { return nil }

        let r, g, b, a: Double
        if s.count == 6 {
            r = Double((value & 0xFF0000) >> 16) / 255.0
            g = Double((value & 0x00FF00) >> 8) / 255.0
            b = Double(value & 0x0000FF) / 255.0
            a = 1.0
        } else {
            r = Double((value & 0xFF000000) >> 24) / 255.0
            g = Double((value & 0x00FF0000) >> 16) / 255.0
            b = Double((value & 0x0000FF00) >> 8) / 255.0
            a = Double(value & 0x000000FF) / 255.0
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// Hex initializer with a guaranteed fallback color.
    init(hex: String, fallback: Color) {
        self = Color(hex: hex) ?? fallback
    }
}
