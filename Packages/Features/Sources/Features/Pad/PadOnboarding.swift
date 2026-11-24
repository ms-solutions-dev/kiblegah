import Core
import DesignSystem
import PrayerTimes
import SwiftUI
import UserData

/// The living half of the first start on the iPad (boards G19, G20): a sky with the sun gliding from step to
/// step, and the real clock. As soon as there is a location the countdown to the next prayer runs, before that the
/// time of day; nothing here is an example value. With „reduce motion“ the sun stays where it is.
struct PadOnboardingSky: View {
    @Environment(PrayerTimeModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0…1: how far the setup is.
    let progress: CGFloat
    @State private var drift = false

    private static let top = PadColor.skyTop
    private static let middle = PadColor.skyMiddle
    private static let low = PadColor.skyLow
    private static let sun = PadColor.sun
    private static let sunEdge = PadColor.sunEdge

    var body: some View {
        GeometryReader { g in
            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: Self.top, location: 0), .init(color: Self.middle, location: 0.42),
                        .init(color: Self.low, location: 0.75), .init(color: Self.low, location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Self.sun, Self.sunEdge], center: .center, startRadius: 0, endRadius: 75)
                    )
                    .frame(width: 150, height: 150)
                    .shadow(color: Self.sunEdge.opacity(0.8), radius: 12)
                    .position(
                        x: g.size.width * 0.5 + (reduceMotion ? 0 : (drift ? 16 : -16)),
                        y: g.size.height * (0.28 + 0.1 * progress)
                    )
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 18).repeatForever(autoreverses: true),
                        value: drift
                    )
                    .animation(
                        reduceMotion ? nil : .timingCurve(0.3, 0.9, 0.3, 1, duration: 0.8), value: progress)
                clock.position(x: g.size.width / 2, y: g.size.height * 0.81)
            }
        }
        .onAppear { drift = true }
        .accessibilityElement(children: .combine)
    }

    private var clock: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 8) {
                if let table = model.table, let status = PrayerTimeStatus(table: table, time: context.date) {
                    Text(app: "ipad.heute.naechstes \(status.next.name())")
                        .typography(.label(size: 18)).textCase(.uppercase).tracking(1.8)
                    Text(verbatim: countdown(status.nextTime.timeIntervalSince(context.date)))
                        .typography(.display(size: 78)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                    Text(verbatim: table.location.name).typography(.secondary)
                } else {
                    Text(app: "ipad.start.jetzt").typography(.label(size: 18)).textCase(.uppercase).tracking(
                        1.8)
                    Text(context.date, format: .dateTime.hour().minute().second())
                        .typography(.display(size: 78)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                    Text(app: "ipad.start.ohne_ort").typography(.secondary)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
        }
    }

    private func countdown(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60)
    }
}
