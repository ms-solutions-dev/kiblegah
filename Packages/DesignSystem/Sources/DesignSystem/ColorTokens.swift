import SwiftUI

/// The color roles of a theme.
///
/// This is the only place with hex values.
/// If a view lacks a color, a new role is added here, not a value in the view.
public struct ColorTokens: Sendable, Equatable {
    public let background: Color
    public let surface: Color
    public let surface2: Color
    public let text: Color
    public let text2: Color
    public let accent: Color
    /// Text on a `accent` surface.
    public let onAccent: Color
    /// Calm secondary color: „şimdi“ dot, switched-on toggles.
    public let sage: Color
    public let label: Color
    public let warningBackground: Color
    public let warningText: Color
    public let errorBackground: Color
    public let errorText: Color
    public let successBackground: Color
    public let successText: Color
    public let kaaba: Color
    public let line: Color
    /// Borders and controls, at least 3:1 against `background`.
    public let control: Color
    public let scrim: Color
    public let dark: Bool
}

extension Color {
    /// `0xRRGGBB` – only inside Gestaltung.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

extension ColorTokens {
    public static let dawnLight = ColorTokens(
        background: Color(hex: 0xF7F3EC), surface: Color(hex: 0xFFFFFF), surface2: Color(hex: 0xEFE8DC),
        text: Color(hex: 0x1F2421), text2: Color(hex: 0x4A4F4B), accent: Color(hex: 0xB0452E),
        onAccent: Color(hex: 0xFFFFFF), sage: Color(hex: 0x4F7357), label: Color(hex: 0x6B4A2E),
        warningBackground: Color(hex: 0xF5E8D3), warningText: Color(hex: 0x5E3D0B),
        errorBackground: Color(hex: 0xF6DCD4), errorText: Color(hex: 0x6E2414),
        successBackground: Color(hex: 0xDCE8DF), successText: Color(hex: 0x1E4A2C),
        kaaba: Color(hex: 0x947032), line: Color(hex: 0xE6DED2), control: Color(hex: 0x8E8676),
        scrim: Color(hex: 0x5C5A55), dark: false)

    public static let dawnDark = ColorTokens(
        background: Color(hex: 0x141816), surface: Color(hex: 0x1E2320), surface2: Color(hex: 0x262B27),
        text: Color(hex: 0xF2EEE6), text2: Color(hex: 0xB4BAB5), accent: Color(hex: 0xE9876D),
        onAccent: Color(hex: 0x141816), sage: Color(hex: 0x8FB596), label: Color(hex: 0xE9B58C),
        warningBackground: Color(hex: 0x2E2614), warningText: Color(hex: 0xF3D9A6),
        errorBackground: Color(hex: 0x3A1C16), errorText: Color(hex: 0xF4B8A8),
        successBackground: Color(hex: 0x17301F), successText: Color(hex: 0xA9DDB8),
        kaaba: Color(hex: 0xC9A86A), line: Color(hex: 0x2E3430), control: Color(hex: 0x6F7771),
        scrim: Color(hex: 0x000000), dark: true)

    /// Gökyüzü: sky blue with warm evening light.
    public static let skyLight = ColorTokens(
        background: Color(hex: 0xEEF3FA), surface: Color(hex: 0xFFFFFF), surface2: Color(hex: 0xDDE7F4),
        text: Color(hex: 0x12233F), text2: Color(hex: 0x3E4F6E), accent: Color(hex: 0xA84A24),
        onAccent: Color(hex: 0xFFFFFF), sage: Color(hex: 0x2F5E9E), label: Color(hex: 0x7A4A22),
        warningBackground: Color(hex: 0xF7E9D2), warningText: Color(hex: 0x5E3D0B),
        errorBackground: Color(hex: 0xF6DCD4), errorText: Color(hex: 0x6E2414),
        successBackground: Color(hex: 0xDCE8DF), successText: Color(hex: 0x1E4A2C),
        kaaba: Color(hex: 0x947032), line: Color(hex: 0xD3DEEC), control: Color(hex: 0x7F8CA3),
        scrim: Color(hex: 0x3B4A63), dark: false)

    public static let skyDark = ColorTokens(
        background: Color(hex: 0x0B1830), surface: Color(hex: 0x12233F), surface2: Color(hex: 0x20365C),
        text: Color(hex: 0xFFF4EC), text2: Color(hex: 0xA9C3E3), accent: Color(hex: 0xF4B98E),
        onAccent: Color(hex: 0x0B1830), sage: Color(hex: 0x8DB4E6), label: Color(hex: 0xFFE3A3),
        warningBackground: Color(hex: 0x2E2614), warningText: Color(hex: 0xF3D9A6),
        errorBackground: Color(hex: 0x3A1C16), errorText: Color(hex: 0xF4B8A8),
        successBackground: Color(hex: 0x17301F), successText: Color(hex: 0xA9DDB8),
        kaaba: Color(hex: 0xC9A86A), line: Color(hex: 0x24395E), control: Color(hex: 0x6F86A8),
        scrim: Color(hex: 0x000000), dark: true)

    /// Nakış: gold and wine red on ivory or night blue, like ornamentation.
    public static let ornamentLight = ColorTokens(
        background: Color(hex: 0xF6F0E2), surface: Color(hex: 0xFFFDF7), surface2: Color(hex: 0xEDE6D6),
        text: Color(hex: 0x1B1810), text2: Color(hex: 0x4A4334), accent: Color(hex: 0x7A3329),
        onAccent: Color(hex: 0xFFFFFF), sage: Color(hex: 0x2F5E52), label: Color(hex: 0x7A5A1E),
        warningBackground: Color(hex: 0xF3E4BF), warningText: Color(hex: 0x5E3D0B),
        errorBackground: Color(hex: 0xF6DCD4), errorText: Color(hex: 0x6E2414),
        successBackground: Color(hex: 0xDCE8DF), successText: Color(hex: 0x1E4A2C),
        kaaba: Color(hex: 0x947032), line: Color(hex: 0xE2D8C2), control: Color(hex: 0x8E8471),
        scrim: Color(hex: 0x3A3324), dark: false)

    public static let ornamentDark = ColorTokens(
        background: Color(hex: 0x0E1116), surface: Color(hex: 0x141821), surface2: Color(hex: 0x2A2F3A),
        text: Color(hex: 0xEDE6D6), text2: Color(hex: 0xB3AEA2), accent: Color(hex: 0xD4AF6A),
        onAccent: Color(hex: 0x0E1116), sage: Color(hex: 0x9CC4B4), label: Color(hex: 0xF3E4BF),
        warningBackground: Color(hex: 0x2E2614), warningText: Color(hex: 0xF3D9A6),
        errorBackground: Color(hex: 0x3A1C16), errorText: Color(hex: 0xF4B8A8),
        successBackground: Color(hex: 0x17301F), successText: Color(hex: 0xA9DDB8),
        kaaba: Color(hex: 0xD4AF6A), line: Color(hex: 0x262B36), control: Color(hex: 0x6E6A60),
        scrim: Color(hex: 0x000000), dark: true)

    /// Zümrüt: emerald green with brass gold, fresh like a garden.
    public static let emeraldLight = ColorTokens(
        background: Color(hex: 0xEEF3EE), surface: Color(hex: 0xFFFFFF), surface2: Color(hex: 0xDFE9E1),
        text: Color(hex: 0x11201A), text2: Color(hex: 0x3F5249), accent: Color(hex: 0x156646),
        onAccent: Color(hex: 0xFFFFFF), sage: Color(hex: 0x8A6420), label: Color(hex: 0x6A5222),
        warningBackground: Color(hex: 0xF5E8D3), warningText: Color(hex: 0x5E3D0B),
        errorBackground: Color(hex: 0xF6DCD4),
        errorText: Color(hex: 0x6E2414), successBackground: Color(hex: 0xDCE8DF),
        successText: Color(hex: 0x1E4A2C),
        kaaba: Color(hex: 0x8F6B2E), line: Color(hex: 0xD6E1D8), control: Color(hex: 0x7A897F),
        scrim: Color(hex: 0x3A4A42),
        dark: false)

    public static let emeraldDark = ColorTokens(
        background: Color(hex: 0x0C1612), surface: Color(hex: 0x13201A), surface2: Color(hex: 0x1D2D25),
        text: Color(hex: 0xEAF2EC), text2: Color(hex: 0xA6BCB0), accent: Color(hex: 0x6DCB9C),
        onAccent: Color(hex: 0x0C1612), sage: Color(hex: 0xE2C17A), label: Color(hex: 0xE9D3A2),
        warningBackground: Color(hex: 0x2E2614), warningText: Color(hex: 0xF3D9A6),
        errorBackground: Color(hex: 0x3A1C16),
        errorText: Color(hex: 0xF4B8A8), successBackground: Color(hex: 0x17301F),
        successText: Color(hex: 0xA9DDB8),
        kaaba: Color(hex: 0xC9A86A), line: Color(hex: 0x20302A), control: Color(hex: 0x64786D),
        scrim: Color(hex: 0x000000),
        dark: true)

    /// Gece: indigo, dark with lavender and moon-yellow labels.
    public static let nightLight = ColorTokens(
        background: Color(hex: 0xEFEFF7), surface: Color(hex: 0xFFFFFF), surface2: Color(hex: 0xE0E0F0),
        text: Color(hex: 0x16172F), text2: Color(hex: 0x45476A), accent: Color(hex: 0x3B3897),
        onAccent: Color(hex: 0xFFFFFF), sage: Color(hex: 0x21706B), label: Color(hex: 0x5B4A86),
        warningBackground: Color(hex: 0xF5E8D3), warningText: Color(hex: 0x5E3D0B),
        errorBackground: Color(hex: 0xF6DCD4),
        errorText: Color(hex: 0x6E2414), successBackground: Color(hex: 0xDCE8DF),
        successText: Color(hex: 0x1E4A2C),
        kaaba: Color(hex: 0x8F6B2E), line: Color(hex: 0xDADAEA), control: Color(hex: 0x80829F),
        scrim: Color(hex: 0x2C2E4C),
        dark: false)

    public static let nightDark = ColorTokens(
        background: Color(hex: 0x0C0D1C), surface: Color(hex: 0x15172E), surface2: Color(hex: 0x222449),
        text: Color(hex: 0xEEEDF9), text2: Color(hex: 0xB0B1D2), accent: Color(hex: 0xABA8F6),
        onAccent: Color(hex: 0x0C0D1C), sage: Color(hex: 0x8ED4C8), label: Color(hex: 0xE9D59C),
        warningBackground: Color(hex: 0x2E2614), warningText: Color(hex: 0xF3D9A6),
        errorBackground: Color(hex: 0x3A1C16),
        errorText: Color(hex: 0xF4B8A8), successBackground: Color(hex: 0x17301F),
        successText: Color(hex: 0xA9DDB8),
        kaaba: Color(hex: 0xD4B76E), line: Color(hex: 0x23254A), control: Color(hex: 0x6C6F9A),
        scrim: Color(hex: 0x000000),
        dark: true)

    /// Gül: muted plum rosé with sage green, warm and not sweet.
    public static let roseLight = ColorTokens(
        background: Color(hex: 0xF8F1F1), surface: Color(hex: 0xFFFFFF), surface2: Color(hex: 0xF0E2E3),
        text: Color(hex: 0x2A181D), text2: Color(hex: 0x5C4449), accent: Color(hex: 0x8E3A5A),
        onAccent: Color(hex: 0xFFFFFF), sage: Color(hex: 0x4F7366), label: Color(hex: 0x7A4E3A),
        warningBackground: Color(hex: 0xF5E8D3), warningText: Color(hex: 0x5E3D0B),
        errorBackground: Color(hex: 0xF6DCD4),
        errorText: Color(hex: 0x6E2414), successBackground: Color(hex: 0xDCE8DF),
        successText: Color(hex: 0x1E4A2C),
        kaaba: Color(hex: 0x8F6B2E), line: Color(hex: 0xEBDCDD), control: Color(hex: 0x968085),
        scrim: Color(hex: 0x4A3439),
        dark: false)

    public static let roseDark = ColorTokens(
        background: Color(hex: 0x181013), surface: Color(hex: 0x22181C), surface2: Color(hex: 0x322329),
        text: Color(hex: 0xF7ECEF), text2: Color(hex: 0xC9B2B9), accent: Color(hex: 0xEFA5BD),
        onAccent: Color(hex: 0x181013), sage: Color(hex: 0x9CC8B4), label: Color(hex: 0xF1C9A6),
        warningBackground: Color(hex: 0x2E2614), warningText: Color(hex: 0xF3D9A6),
        errorBackground: Color(hex: 0x3A1C16),
        errorText: Color(hex: 0xF4B8A8), successBackground: Color(hex: 0x17301F),
        successText: Color(hex: 0xA9DDB8),
        kaaba: Color(hex: 0xD2AE72), line: Color(hex: 0x33252A), control: Color(hex: 0x7E696F),
        scrim: Color(hex: 0x000000),
        dark: true)

    /// Sakin: for „Büyük ve sade“. `sage` is a tone of its own so that „şimdi“ and
    /// „Sıradaki“ do not differ by text alone.
    public static let calmLight = ColorTokens(
        background: Color(hex: 0xF6F3EC), surface: Color(hex: 0xFFFFFF), surface2: Color(hex: 0xECE7DB),
        text: Color(hex: 0x16223A), text2: Color(hex: 0x4B556A), accent: Color(hex: 0x1F6F63),
        onAccent: Color(hex: 0xFFFFFF), sage: Color(hex: 0x3D5A8C), label: Color(hex: 0x5A4A2A),
        warningBackground: Color(hex: 0xF1E6D2), warningText: Color(hex: 0x5A4114),
        errorBackground: Color(hex: 0xF6DCD4), errorText: Color(hex: 0x6E2414),
        successBackground: Color(hex: 0xDCE8DF), successText: Color(hex: 0x1E4A2C),
        kaaba: Color(hex: 0x947032), line: Color(hex: 0xE4DFD3), control: Color(hex: 0x8C8578),
        scrim: Color(hex: 0x5C5A55), dark: false)

    public static let calmDark = ColorTokens(
        background: Color(hex: 0x10151F), surface: Color(hex: 0x1A2130), surface2: Color(hex: 0x232B3C),
        text: Color(hex: 0xECEFF4), text2: Color(hex: 0xAEB6C4), accent: Color(hex: 0x5FC1AE),
        onAccent: Color(hex: 0x10151F), sage: Color(hex: 0x9DB8E8), label: Color(hex: 0xE0C9A0),
        warningBackground: Color(hex: 0x2B2617), warningText: Color(hex: 0xF0D7A8),
        errorBackground: Color(hex: 0x3A1C16), errorText: Color(hex: 0xF4B8A8),
        successBackground: Color(hex: 0x17301F), successText: Color(hex: 0xA9DDB8),
        kaaba: Color(hex: 0xC9A86A), line: Color(hex: 0x283041), control: Color(hex: 0x6B7487),
        scrim: Color(hex: 0x000000), dark: true)
}

extension ColorTokens {
    /// Qibla yellow for the line and hearts on the map (as in the model „Kıble Bul“); the same in all
    /// palettes, because the background is the map tile, not the theme. Legible thanks to the
    /// dark outline that the map draws along with it.
    public var qiblaYellow: Color { Color(hex: 0xFACC1A) }
}

extension ColorTokens {
    /// The same roles with the surface as the ground: pages inside a card (iPad columns).
    public var onSurface: ColorTokens {
        ColorTokens(
            background: surface, surface: surface2, surface2: surface2, text: text, text2: text2,
            accent: accent, onAccent: onAccent, sage: sage, label: label,
            warningBackground: warningBackground, warningText: warningText,
            errorBackground: errorBackground, errorText: errorText,
            successBackground: successBackground, successText: successText,
            kaaba: kaaba, line: line, control: control, scrim: scrim, dark: dark)
    }
}
