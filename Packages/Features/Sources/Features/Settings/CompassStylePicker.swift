import Core
import DesignSystem
import SwiftUI

/// Compass style as two image tiles like the icon picker (package 3, variant A).
///
/// The preview is the real ``Dial``, fixed to „almost hit“, so that needle and
/// Kaaba look as in the Qibla tab; it does not rotate and accepts no gestures.
struct CompassStylePicker: View {
    @Environment(\.theme) private var theme
    @Binding var style: CompassStyle
    let sade: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(app: "ayar.pusula_stili")
            HStack(spacing: 12) {
                ForEach(CompassStyle.allCases, id: \.self) { s in
                    Button {
                        style = s
                    } label: {
                        tile(s)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(app: s.nameKey))
                    .accessibilityAddTraits(style == s ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// The dials have fixed font and stroke sizes; drawn small, numbers and
    /// Kaaba run into each other, so draw at Qibla size and scale down.
    private static let drawingSize: CGFloat = 340

    private func tile(_ s: CompassStyle) -> some View {
        let selected = style == s
        return VStack(spacing: 6) {
            GeometryReader { g in
                Dial(style: s, direction: 100, qibla: 120, done: false, sade: sade)
                    .frame(width: Self.drawingSize, height: Self.drawingSize)
                    .scaleEffect(g.size.width / Self.drawingSize)
                    .frame(width: g.size.width, height: g.size.height)
            }
            .aspectRatio(1, contentMode: .fit)
            .padding(6)
            .allowsHitTesting(false)
            .background(theme.colors.background, in: .rect(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? theme.colors.accent : Color.clear, lineWidth: 2.5)
                    .padding(-3)
            }
            Text(app: s.nameKey).typography(.footnote)
                .foregroundStyle(selected ? theme.colors.text : theme.colors.text2)
        }
        .frame(maxWidth: .infinity)
    }
}

extension CompassStyle {
    fileprivate var nameKey: LocalizedStringKey {
        switch self {
        case .degreeRing: "ayar.pusula_stili.halka"
        case .largeNeedle: "ayar.pusula_stili.igne"
        }
    }
}
