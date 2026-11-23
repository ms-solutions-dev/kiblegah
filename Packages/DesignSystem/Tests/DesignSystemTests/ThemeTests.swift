import SwiftUI
import Testing

@testable import DesignSystem

@Suite struct ThemeTests {
    @Test func byPrayerTimeNightDark() {
        let t = Theme.parse(
            appearance: .byPrayerTime, largeAndSimple: false, systemDark: false, isNight: true)
        #expect(t.colors == .dawnDark)
        let g = Theme.parse(
            appearance: .byPrayerTime, largeAndSimple: false, systemDark: true, isNight: false)
        #expect(g.colors == .dawnLight)
    }

    @Test func largeAndSimplePicksCalm() {
        #expect(
            Theme.parse(appearance: .light, largeAndSimple: true, systemDark: true, isNight: true).colors
                == .calmLight
        )
        #expect(
            Theme.parse(appearance: .system, largeAndSimple: true, systemDark: true, isNight: false).colors
                == .calmDark)
    }

    @Test func paletteSelection() {
        #expect(
            Theme.parse(
                appearance: .dark, largeAndSimple: false, systemDark: false, isNight: false,
                palette: .ornament
            )
            .colors == .ornamentDark)
        #expect(
            Theme.parse(
                appearance: .light, largeAndSimple: false, systemDark: true, isNight: false, palette: .sky
            )
            .colors == .skyLight)
        // „Büyük ve sade“ always wins
        #expect(
            Theme.parse(
                appearance: .light, largeAndSimple: true, systemDark: false, isNight: false,
                palette: .ornament
            )
            .colors == .calmLight)
    }

    /// Text on background at least 4.5:1 (WCAG AA), in all palettes.
    @Test func contrastSufficient() {
        let palettes: [ColorTokens] = [
            .dawnLight, .dawnDark, .calmLight, .calmDark, .skyLight, .skyDark, .ornamentLight,
            .ornamentDark,
        ]
        for r in palettes {
            for background in [r.background, r.surface] {
                for text in [r.text, r.text2, r.accent, r.label] {
                    #expect(
                        Self.contrast(text, background) >= 4.5,
                        "\(text) auf \(background): \(Self.contrast(text, background))")
                }
            }
        }
    }

    /// Graphics (Kaaba mark, compass ring) need 3:1 against the ground.
    @Test func graphicContrastSufficient() {
        let palettes: [ColorTokens] = [
            .dawnLight, .dawnDark, .calmLight, .calmDark, .skyLight, .skyDark, .ornamentLight,
            .ornamentDark,
        ]
        for r in palettes {
            for graphic in [r.kaaba, r.control] {
                #expect(Self.contrast(graphic, r.background) >= 3, "\(graphic) auf \(r.background)")
            }
        }
    }

    /// Symbol on its category color field at least 3:1 (WCAG 1.4.11), in all themes.
    @Test func categoryIconTileContrast() {
        let palettes: [ColorTokens] = [
            .dawnLight, .dawnDark, .calmLight, .calmDark, .skyLight, .skyDark, .ornamentLight,
            .ornamentDark,
        ]
        for r in palettes {
            for ton in CategoryTone.allCases {
                let k = r.category(ton)
                #expect(Self.contrast(k.icon, k.background) >= 3, "\(ton) in \(r.dark ? "koyu" : "acik")")
            }
        }
    }

    static func contrast(_ a: Color, _ b: Color) -> Double {
        func l(_ c: Color) -> Double {
            let r = c.resolve(in: EnvironmentValues())
            return 0.2126 * Double(r.linearRed) + 0.7152 * Double(r.linearGreen) + 0.0722
                * Double(r.linearBlue)
        }
        let (x, y) = (l(a), l(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    @Test func calmSageDiffersFromAccent() {
        #expect(ColorTokens.calmLight.sage != ColorTokens.calmLight.accent)
        #expect(ColorTokens.calmDark.sage != ColorTokens.calmDark.accent)
    }
}
