import ContentPacks
import Core
import DesignSystem
import SwiftUI

/// Arabic verse text with tajweed colors. Only the color changes, not the font -
/// so CoreText keeps shaping the words as a whole and the connections do not break.
func tajweedText(_ text: String, spans: [TajweedSpan], dark: Bool, ek: String = "") -> AttributedString {
    var a = AttributedString(text + ek)
    let total = text.unicodeScalars.count
    for s in spans where s.interval.upperBound <= total && !s.interval.isEmpty {
        let b = a.unicodeScalars.index(a.startIndex, offsetBy: s.interval.lowerBound)
        let e = a.unicodeScalars.index(a.startIndex, offsetBy: s.interval.upperBound)
        a[b..<e].foregroundColor = TajweedColors.color(s.rule, dark: dark)
    }
    return a
}

/// Legend of the rules in one verse (or all), tappable with a short explanation.
struct TajweedLegend: View {
    @Environment(\.theme) private var theme
    let rules: [String]
    @State private var light: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rules, id: \.self) { k in
                Button {
                    light = light == k ? nil : k
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 10) {
                            Circle().fill(TajweedColors.color(k, dark: theme.colors.dark)).frame(
                                width: 14, height: 14
                            )
                            .accessibilityHidden(true)
                            Text(
                                verbatim: AppLanguage.bundle.localizedString(
                                    forKey: "tecvid.\(k)", value: k, table: nil)
                            )
                            .typography(.emphasized).foregroundStyle(theme.colors.text)
                            Spacer()
                            Image(systemName: light == k ? "chevron.up" : "chevron.down").accessibilityHidden(
                                true
                            )
                            .foregroundStyle(theme.colors.text2)
                        }
                        if light == k {
                            Text(
                                verbatim: AppLanguage.bundle.localizedString(
                                    forKey: "tecvid.\(k).aciklama", value: "", table: nil)
                            )
                            .typography(.secondary).foregroundStyle(theme.colors.text2)
                            .multilineTextAlignment(.leading)
                        }
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(light == k ? .isSelected : [])
            }
            Text(app: "tecvid.not").typography(.footnote).foregroundStyle(theme.colors.text2)
            Text(app: "tecvid.kaynak").typography(.footnote).foregroundStyle(theme.colors.text2)
        }
    }
}
