import Core
import SwiftUI

/// The resolved theme of a view: colors, font, density.
///
/// „Büyük ve sade“ is deliberately **one** switch: it selects Sakin,
/// raises the font size and hides side matters. There is no separate theme choice.
public struct Theme: Sendable, Equatable {
    public let colors: ColorTokens
    public let largeAndSimple: Bool
    /// Whether the color scheme is forced. Not with „Sistem“ – otherwise the app would stay stuck in the
    /// forced scheme after switching from „Açık“ back to „Sistem“.
    public let force: Bool

    public init(colors: ColorTokens, largeAndSimple: Bool, force: Bool = true) {
        self.colors = colors
        self.largeAndSimple = largeAndSimple
        self.force = force
    }

    /// Selects the colors from the setting, the system color scheme and the time of day.
    ///
    /// - Parameter geceMi: whether it is currently between Yatsı and İmsak – comes from the prayer time service.
    /// - Parameter palet: color world; „Büyük ve sade“ takes precedence and always selects Sakin.
    public static func parse(
        appearance: Appearance, largeAndSimple: Bool, systemDark: Bool, isNight: Bool,
        palette: Palette = .dawn
    ) -> Theme {
        let dark: Bool =
            switch appearance {
            case .system: systemDark
            case .light: false
            case .dark: true
            case .byPrayerTime: isNight
            }
        let colors: ColorTokens =
            switch (largeAndSimple, palette, dark) {
            case (true, _, false): .calmLight
            case (true, _, true): .calmDark
            case (false, .dawn, false): .dawnLight
            case (false, .dawn, true): .dawnDark
            case (false, .sky, false): .skyLight
            case (false, .sky, true): .skyDark
            case (false, .ornament, false): .ornamentLight
            case (false, .ornament, true): .ornamentDark
            case (false, .emerald, false): .emeraldLight
            case (false, .emerald, true): .emeraldDark
            case (false, .night, false): .nightLight
            case (false, .night, true): .nightDark
            case (false, .rose, false): .roseLight
            case (false, .rose, true): .roseDark
            }
        return Theme(colors: colors, largeAndSimple: largeAndSimple, force: appearance != .system)
    }

    public var colorScheme: ColorScheme { colors.dark ? .dark : .light }

    public static let standard = Theme(colors: .dawnLight, largeAndSimple: false, force: false)
}

extension EnvironmentValues {
    @Entry public var theme: Theme = .standard
}

extension View {
    /// Applies theme, color scheme and – with „Büyük ve sade“ – a larger base font.
    public func theme(_ theme: Theme) -> some View {
        self
            .environment(\.theme, theme)
            .preferredColorScheme(theme.force ? theme.colorScheme : nil)
            .tint(theme.colors.accent)
            .dynamicTypeSize(
                theme.largeAndSimple ? .xxLarge ... .accessibility5 : .xSmall ... .accessibility5)
    }
}
