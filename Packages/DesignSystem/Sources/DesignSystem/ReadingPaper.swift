import SwiftUI

/// The paper a text is read on: its own level, separate from the color palette of the app.
/// Only reading surfaces (reader, book) use it; „auto“ follows the theme.
public enum ReadingPaper: String, CaseIterable, Sendable {
    case auto, paper = "papier", sepia, dark = "dunkel", night = "nacht"

    public init(setting: String) { self = ReadingPaper(rawValue: setting) ?? .auto }

    /// The roles of the theme, on this paper.
    public func tokens(base c: ColorTokens) -> ColorTokens {
        switch self {
        case .auto: c
        case .paper:
            Self.tokens(base: c, paper: ReadingColors.lightPaper, ink: ReadingColors.lightInk, dark: false)
        case .sepia:
            Self.tokens(base: c, paper: ReadingColors.sepiaPaper, ink: ReadingColors.sepiaInk, dark: false)
        case .dark:
            Self.tokens(base: c, paper: ReadingColors.darkPaper, ink: ReadingColors.darkInk, dark: true)
        case .night:
            Self.tokens(base: c, paper: ReadingColors.nightPaper, ink: ReadingColors.nightInk, dark: true)
        }
    }

    private static func tokens(base c: ColorTokens, paper: UInt32, ink: UInt32, dark: Bool) -> ColorTokens {
        let p = Color(hex: paper)
        let i = Color(hex: ink)
        // The accent of the palette of the fitting brightness keeps its contrast on the paper.
        let accent = dark ? ColorTokens.dawnDark.accent : ColorTokens.dawnLight.accent
        let label = dark ? ColorTokens.dawnDark.label : ColorTokens.dawnLight.label
        return ColorTokens(
            background: p, surface: p, surface2: i.opacity(0.08),
            text: i, text2: i.opacity(0.75), accent: accent,
            onAccent: dark ? ColorTokens.dawnDark.onAccent : ColorTokens.dawnLight.onAccent,
            sage: dark ? ColorTokens.dawnDark.sage : ColorTokens.dawnLight.sage, label: label,
            warningBackground: c.warningBackground, warningText: c.warningText,
            errorBackground: c.errorBackground, errorText: c.errorText,
            successBackground: c.successBackground, successText: c.successText,
            kaaba: c.kaaba, line: i.opacity(0.11), control: i.opacity(0.5), scrim: c.scrim, dark: dark)
    }
}
