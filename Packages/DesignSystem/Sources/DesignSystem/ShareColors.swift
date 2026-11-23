import SwiftUI

/// The skies of the six prayer times (variants 01 A, 07 B): top to bottom.
///
/// Independent of the theme, because the background shows the time of day, not the color world. Lives here
/// because Gestaltung is the only place with color values; the mapping prayer → `SkyPhase` is done by
/// the UI, Gestaltung does not know the prayer time package.
public enum SkyPhase: String, CaseIterable, Sendable {
    case imsak, sunrise = "gunes", dhuhr = "ogle", asr = "ikindi", maghrib = "aksam", isha = "yatsi"

    /// Four steps, dark at the top. Öğle deliberately stays a rich blue so that white text on the
    /// veil ``SkyPhase/scrim`` reaches at least 4.5:1.
    public var colors: [Color] {
        switch self {
        case .imsak: [Color(hex: 0x0E1A3A), Color(hex: 0x23305E), Color(hex: 0x4B4A7C), Color(hex: 0x8A6A8E)]
        case .sunrise:
            [Color(hex: 0x2E3D6E), Color(hex: 0x6E6A98), Color(hex: 0xD08F78), Color(hex: 0xF0C08A)]
        case .dhuhr: [Color(hex: 0x123A6B), Color(hex: 0x225A92), Color(hex: 0x3E7BB5), Color(hex: 0x76A6D3)]
        case .asr:
            [Color(hex: 0x23466F), Color(hex: 0x4D7398), Color(hex: 0xB08A64), Color(hex: 0xDDAE72)]
        case .maghrib:
            [Color(hex: 0x1B2A55), Color(hex: 0x4E4A80), Color(hex: 0xB86C72), Color(hex: 0xE9A06E)]
        case .isha: [Color(hex: 0x070D1F), Color(hex: 0x111C3A), Color(hex: 0x1E2B52), Color(hex: 0x34406B)]
        }
    }

    public var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    /// Text on every sky.
    public static var text: Color { Color(hex: 0xFFFFFF) }

    /// Dark glass veil under the text so that bright evening streaks do not break the contrast.
    public static var scrim: Color { Color(hex: 0x0B1226).opacity(0.32) }
}

/// The three base colors of the share card „Renk“ (variant 07 A): background, text, secondary text.
///
/// Every combination holds ≥ 4.5:1 for text and secondary text; the secondary text is not a
/// translucent white, because story apps recompress images and halftones drown.
public enum CardColor: String, CaseIterable, Sendable {
    case green = "yesil", terracotta = "kiremit", cream = "krem"

    public var background: Color {
        switch self {
        case .green: Color(hex: 0x1E3A2A)
        case .terracotta: Color(hex: 0xB0452E)
        case .cream: Color(hex: 0xF7F3EC)
        }
    }

    public var text: Color {
        switch self {
        case .green, .terracotta: Color(hex: 0xFFFFFF)
        case .cream: Color(hex: 0x1F2421)
        }
    }

    public var secondary: Color {
        switch self {
        case .green: Color(hex: 0xCFE0D4)
        case .terracotta: Color(hex: 0xFBEAE4)
        case .cream: Color(hex: 0x6B4A2E)
        }
    }
}
