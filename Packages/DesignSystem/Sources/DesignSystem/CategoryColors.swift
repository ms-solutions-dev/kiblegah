import SwiftUI

/// A color swatch behind an area or category icon.
///
/// Light: soft surface, dark icon in the same tone; dark the other way round. Icon against surface
/// at least 3:1 (WCAG 1.4.11), checked in `ThemeTests`.
public struct CategoryColor: Sendable, Equatable {
    public let background: Color
    public let icon: Color
}

/// The tones of the area colors. An area keeps its tone everywhere: Keşfet, Hadis, Takvim.
///
/// `notr` takes the theme's own surfaces, for rows without an area of their own (Ayarlar).
public enum CategoryTone: String, Sendable, CaseIterable {
    case clay = "kil", saffron = "safran", sage = "adacayi", turquoise = "turkuaz", sea = "deniz", purple =
        "mor", rose = "gul", olive = "zeytin", neutral = "notr"
}

extension ColorTokens {
    /// The color swatch of a tone in this theme. All light themes share the light row, all
    /// dark themes the dark one; the tones are muted enough to sit next to Seher, Gökyüzü, Nakış and
    /// Sakin without overriding their Vurgu.
    public func category(_ tone: CategoryTone) -> CategoryColor {
        if tone == .neutral { return CategoryColor(background: surface2, icon: text2) }
        let (background, icon): (UInt32, UInt32) =
            switch (dark, tone) {
            case (false, .clay): (0xF6DDD3, 0x8A3A22)
            case (false, .saffron): (0xF5E6C4, 0x6B4C0E)
            case (false, .sage): (0xDCE9DE, 0x2F5A3A)
            case (false, .turquoise): (0xD4ECEA, 0x1F5F5A)
            case (false, .sea): (0xD9E6F4, 0x24507F)
            case (false, .purple): (0xE8DDF0, 0x5A3A7A)
            case (false, .rose): (0xF4DCE4, 0x7F2F4C)
            case (false, _): (0xE6E8D0, 0x4A5320)
            case (true, .clay): (0x4A2A20, 0xF4B8A0)
            case (true, .saffron): (0x3E3418, 0xEED39A)
            case (true, .sage): (0x23382A, 0xA9D4B2)
            case (true, .turquoise): (0x1C3A38, 0x9ED8D0)
            case (true, .sea): (0x1F3350, 0xA8C8EE)
            case (true, .purple): (0x36294A, 0xD4BEEE)
            case (true, .rose): (0x45222F, 0xF0B4C8)
            case (true, _): (0x33361C, 0xD4DBA4)
            }
        return CategoryColor(background: Color(hex: background), icon: Color(hex: icon))
    }
}

/// Icon on its color swatch, as the icon of a list row. Grows with the font (Dynamic Type)
/// and is invisible to VoiceOver because the row carries its own text.
public struct IconTile: View {
    @Environment(\.theme) private var theme
    @ScaledMetric(relativeTo: .body) private var border: CGFloat = 32
    let icon: String
    let tone: CategoryTone

    public init(_ icon: String, tone: CategoryTone) {
        self.icon = icon
        self.tone = tone
    }

    public var body: some View {
        let r = theme.colors.category(tone)
        Image(systemName: icon)
            .font(.system(size: border * 0.5, weight: .semibold))
            .foregroundStyle(r.icon)
            .frame(width: border, height: border)
            .background(r.background, in: .rect(cornerRadius: border * 0.28))
            .accessibilityHidden(true)
    }
}
