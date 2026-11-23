import Core
import DesignSystem
import Qibla
import SwiftUI

/// Dial according to the chosen ``CompassStyle``.
///
/// Both rotate the ring continuously so that the north crossing does not animate a whole turn (K3);
/// the cardinal directions stand upright and are localized (K13).
struct Dial: View {
    let style: CompassStyle
    let direction: Double?
    let qibla: Double
    let done: Bool
    let sade: Bool
    @State private var angle: Double?

    var body: some View {
        Group {
            switch style {
            case .degreeRing:
                DegreeRing(
                    angle: angle ?? direction ?? 0, hasHeading: direction != nil, qibla: qibla, done: done,
                    sade: sade)
            case .largeNeedle:
                LargeNeedle(
                    angle: angle ?? direction ?? 0, hasHeading: direction != nil, qibla: qibla, done: done)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(.easeOut(duration: 0.15), value: angle)
        .onChange(of: direction, initial: true) { _, y in
            angle = y.map { QiblaCalculation.continuous(angle, $0) }
        }
    }
}

/// The four cardinal directions on the ring, offset upright via ``CompassLetter``.
struct DirectionLetters: View {
    @Environment(\.theme) private var theme
    let direction: Double
    let r: CGFloat

    var body: some View {
        ForEach(0..<4, id: \.self) { i in
            let p = CompassLetter.location(i, direction: direction, r: r)
            Text(verbatim: localized(key: CompassLetter.key(i)))
                .typography(.emphasized)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(i == 0 ? theme.colors.accent : theme.colors.text)
                .offset(x: p.x, y: p.y)
        }
    }
}

/// Variant C „Degree ring like the model“: fine ring, Kaaba on the ring, pointer from the center to the
/// Kaaba; the fixed mark at the top is the viewing direction of the phone.
///
/// In „Büyük ve sade“ the degree numbers are omitted so that the ring is not overloaded with lines.
struct DegreeRing: View {
    @Environment(\.theme) private var theme
    let angle: Double
    let hasHeading: Bool
    let qibla: Double
    let done: Bool
    let sade: Bool

    var body: some View {
        GeometryReader { g in
            let r = min(g.size.width, g.size.height) / 2 - 14
            let markerColor = done ? theme.colors.sage : theme.colors.kaaba
            ZStack {
                ZStack {
                    ForEach(0..<72, id: \.self) { i in
                        let large = i % 6 == 0
                        Rectangle().fill(i % 18 == 0 ? theme.colors.text : theme.colors.text2)
                            .frame(width: i % 18 == 0 ? 3 : 1, height: large ? 14 : 7)
                            .offset(y: -r + (large ? 7 : 3.5))
                            .rotationEffect(.degrees(Double(i) * 5))
                    }
                    Capsule().fill(markerColor)
                        .frame(width: 5, height: r * 0.72)
                        .offset(y: -r * 0.36)
                        .rotationEffect(.degrees(qibla))
                    Image(systemName: "cube.fill").font(.system(size: 22))
                        .foregroundStyle(.white).padding(6)
                        .background(markerColor, in: .rect(cornerRadius: 8))
                        .rotationEffect(.degrees(-(qibla - angle)))
                        .offset(y: -r)
                        .rotationEffect(.degrees(qibla))
                }
                .rotationEffect(.degrees(-angle))
                .opacity(hasHeading ? 1 : 0.35)
                if !sade {
                    ForEach([30, 60, 120, 150, 210, 240, 300, 330], id: \.self) { d in
                        let p = CompassLetter.point(angle: Double(d) - angle, r: r - 34)
                        Text(verbatim: "\(d)").font(.caption2.monospacedDigit())
                            .dynamicTypeSize(...DynamicTypeSize.large)
                            .foregroundStyle(theme.colors.text2)
                            .offset(x: p.x, y: p.y)
                    }
                }
                DirectionLetters(direction: angle, r: r - (sade ? 34 : 56))
                Circle().fill(markerColor).frame(width: 14, height: 14)
                Image(systemName: "arrowtriangle.down.fill").font(.system(size: 16))
                    .foregroundStyle(done ? theme.colors.sage : theme.colors.text)
                    .offset(y: -r - 12)
            }
            .frame(width: g.size.width, height: g.size.height)
        }
        .padding(.top, 12)
    }
}

/// Variant A „Large needle“: Kaaba and needle large; on a hit golden glow and green needle.
struct LargeNeedle: View {
    @Environment(\.theme) private var theme
    let angle: Double
    let hasHeading: Bool
    let qibla: Double
    let done: Bool

    var body: some View {
        GeometryReader { g in
            let r = min(g.size.width, g.size.height) / 2 - 24
            ZStack {
                Circle().fill(theme.colors.qiblaYellow.opacity(done ? 0.28 : 0))
                    .blur(radius: 24)
                    .scaleEffect(done ? 1.05 : 0.8)
                ZStack {
                    Circle().stroke(
                        done ? theme.colors.qiblaYellow : theme.colors.control, lineWidth: done ? 4 : 2)
                    ForEach(0..<36, id: \.self) { i in
                        Rectangle().fill(theme.colors.text2)
                            .frame(width: i % 9 == 0 ? 3 : 1, height: i % 9 == 0 ? 14 : 7)
                            .offset(y: -r + 10)
                            .rotationEffect(.degrees(Double(i) * 10))
                    }
                    Image(systemName: "cube.fill").font(.system(size: 34))
                        .foregroundStyle(.white).padding(8)
                        .background(theme.colors.kaaba, in: .rect(cornerRadius: 10))
                        .shadow(color: theme.colors.qiblaYellow.opacity(done ? 0.9 : 0), radius: 14)
                        .rotationEffect(.degrees(-(qibla - angle)))
                        .offset(y: -r)
                        .rotationEffect(.degrees(qibla))
                }
                .rotationEffect(.degrees(-angle))
                DirectionLetters(direction: angle, r: r - 40)
                Image(systemName: "location.north.fill")
                    .font(.system(size: r * 0.55))
                    .foregroundStyle(done ? theme.colors.sage : theme.colors.text)
                    .shadow(color: theme.colors.qiblaYellow.opacity(done ? 0.8 : 0), radius: 12)
                    .opacity(hasHeading ? 1 : 0.3)
            }
            .frame(width: g.size.width, height: g.size.height)
            .animation(.easeOut(duration: 0.3), value: done)
        }
    }
}
