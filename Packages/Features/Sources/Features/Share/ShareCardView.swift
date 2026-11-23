import DesignSystem
import PrayerTimes
import SwiftUI

/// The card itself, 360 × 640 points; rendered at factor 3 this gives 1080 × 1920 for stories.
///
/// Font sizes are fixed instead of Dynamic Type: the image should look the same on every device,
/// regardless of the text size the sharer reads with. Long texts shrink down to half.
struct ShareCardView: View {
    static let size = CGSize(width: 360, height: 640)
    static let scale: CGFloat = 3

    let card: ShareCard
    let selection: ShareOptions
    let prayerTimes: SkyPhase

    private var textColor: Color { selection.style == .sky ? SkyPhase.text : selection.color.text }
    private var secondaryColor: Color { selection.style == .sky ? SkyPhase.text : selection.color.secondary }

    var body: some View {
        VStack(spacing: 14) {
            Text(verbatim: bridge)
                .font(.custom("Plus Jakarta Sans", fixedSize: 11).weight(.bold))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(secondaryColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
            if card.kind == .qibla {
                QiblaRoute(
                    card: card, showPlace: selection.showPlace, text: textColor, secondary: secondaryColor)
            } else {
                Spacer(minLength: 8)
                cardBody
                    .padding(selection.style == .sky ? 18 : 0)
                    .background(
                        selection.style == .sky ? SkyPhase.scrim : .clear, in: .rect(cornerRadius: 18))
                Spacer(minLength: 8)
            }
            HStack(spacing: 6) {
                KaabaMarker(size: 14)
                Text(verbatim: "Kıblegâh").font(.custom("Fraunces", fixedSize: 14).weight(.semibold))
            }
            .foregroundStyle(secondaryColor)
            // On a light Sunrise/Asr sky the mark got lost (): own scrim as with the text.
            .padding(.horizontal, selection.style == .sky ? 12 : 0)
            .padding(.vertical, selection.style == .sky ? 6 : 0)
            .background(selection.style == .sky ? SkyPhase.scrim : .clear, in: .capsule)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(textColor)
        .padding(.horizontal, 28)
        .padding(.vertical, 30)
        .frame(width: Self.size.width, height: Self.size.height)
        .background { background }
        .environment(\.layoutDirection, .leftToRight)
    }

    private var bridge: String {
        guard selection.style == .sky else { return card.parent }
        let prayerName = Prayer(rawValue: prayerTimes.rawValue)?.name() ?? ""
        if selection.showPlace, let place = card.place ?? placeName, !place.isEmpty {
            return "\(prayerName) · \(place)"
        }
        return prayerName
    }

    /// In the sky style the user's place is at the top; the Qibla card brings it along itself.
    var placeName: String?

    @ViewBuilder private var background: some View {
        switch selection.style {
        case .color: selection.color.background
        case .sky: prayerTimes.gradient
        }
    }

    private var cardBody: some View {
        let hasMeaning = selection.showMeaning || !card.meaningHideable
        return VStack(spacing: 14) {
            if !card.arabic.isEmpty {
                Text(verbatim: card.arabic)
                    .font(.custom(Typography.arabicFontName, fixedSize: card.kind == .divineName ? 64 : 30))
                    .lineSpacing(6)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.45)
                    .lineLimit(card.kind == .divineName ? 2 : 9)
                    .environment(\.layoutDirection, .rightToLeft)
            }
            if !card.title.isEmpty {
                Text(verbatim: card.title).font(.custom("Fraunces", fixedSize: 24).weight(.semibold))
                    .multilineTextAlignment(.center)
            }
            if hasMeaning && !card.meaning.isEmpty {
                Text(verbatim: card.meaning)
                    .font(.custom("Plus Jakarta Sans", fixedSize: 16).weight(.semibold))
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .lineLimit(14)
            }
            Text(verbatim: card.source)
                .font(.custom("Plus Jakarta Sans", fixedSize: 12))
                .foregroundStyle(secondaryColor)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Qibla card (variant 07 C): route with a heart to the Kaaba, above it distance and direction.
///
/// Deliberately no map tile: a map section would reveal the home area. The line is
/// symbolic, only the number and the degree value are accurate.
private struct QiblaRoute: View {
    let card: ShareCard
    let showPlace: Bool
    let text: Color
    let secondary: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "\(card.kmText) km").font(.custom("Fraunces", fixedSize: 48).weight(.semibold))
            Text(verbatim: row).font(.custom("Plus Jakarta Sans", fixedSize: 15).weight(.semibold))
                .foregroundStyle(secondary)
            GeometryReader { g in
                let start = CGPoint(x: g.size.width * 0.18, y: g.size.height * 0.86)
                let end = CGPoint(x: g.size.width * 0.80, y: g.size.height * 0.16)
                let review = CGPoint(x: g.size.width * 0.22, y: g.size.height * 0.30)
                ZStack {
                    Path { p in
                        p.move(to: start)
                        p.addQuadCurve(to: end, control: review)
                    }
                    .stroke(.black.opacity(0.55), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    Path { p in
                        p.move(to: start)
                        p.addQuadCurve(to: end, control: review)
                    }
                    .stroke(
                        ColorTokens.dawnLight.qiblaYellow, style: StrokeStyle(lineWidth: 5.5, lineCap: .round)
                    )
                    ForEach([0.22, 0.42, 0.62, 0.8], id: \.self) { t in
                        Image(systemName: "heart.fill").font(.system(size: 18))
                            .foregroundStyle(ColorTokens.dawnLight.qiblaYellow)
                            .shadow(color: .black.opacity(0.5), radius: 1.5)
                            .position(Self.point(start, review, end, t))
                    }
                    Circle().fill(ColorTokens.dawnLight.sage).frame(width: 16, height: 16)
                        .overlay(Circle().stroke(text, lineWidth: 3))
                        .position(start)
                    KaabaMarker(size: 34).position(end)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 12)
    }

    private var row: String {
        if showPlace, let place = card.place, !place.isEmpty {
            return localized("paylas.kible.rota \(place) \(card.angleText)")
        }
        return localized("paylas.kible.rota_yersiz \(card.angleText)")
    }

    static func point(_ a: CGPoint, _ k: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u * u * a.x + 2 * u * t * k.x + t * t * b.x, y: u * u * a.y + 2 * u * t * k.y + t * t * b.y)
    }
}

/// The Kaaba as a small symbol: black cube with a golden band.
struct KaabaMarker: View {
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.18)
            .fill(.black)
            .overlay(alignment: .top) {
                Rectangle().fill(ColorTokens.dawnDark.kaaba).frame(height: size * 0.16).padding(
                    .top, size * 0.24)
            }
            .clipShape(.rect(cornerRadius: size * 0.18))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

extension ShareCardView {
    /// The finished image at 1080 × 1920; `nil` if the renderer returns nothing.
    @MainActor static func render(
        _ card: ShareCard, selection: ShareOptions, prayerTimes: SkyPhase, placeName: String? = nil
    ) -> CGImage? {
        var g = ShareCardView(card: card, selection: selection, prayerTimes: prayerTimes)
        g.placeName = placeName
        let r = ImageRenderer(content: g)
        r.scale = scale
        r.proposedSize = ProposedViewSize(size)
        return r.cgImage
    }
}
