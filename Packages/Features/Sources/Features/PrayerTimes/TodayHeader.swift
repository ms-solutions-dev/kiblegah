import Core
import DesignSystem
import PrayerTimes
import SwiftUI

/// The next prayer time as a colored card (variant 01 C): name and time, large countdown,
/// below it the progress from the current to the next prayer time.
///
/// Countdown centered. The color follows the deadline of the current prayer: until the next
/// prayer time or until the karahat before it (`Urgency`); the bar shows karahat hatched.
struct NextPrayerCard: View {
    @Environment(\.theme) private var theme
    let status: PrayerTimeStatus
    let time: Date
    let tz: TimeZone
    let friday: Bool
    let ramadan: Bool
    let timeline: DayTimeline
    var openKarahat: () -> Void = {}

    var body: some View {
        let s = Counter(remaining: status.nextTime.timeIntervalSince(time))
        let r = Urgency.calculate(status, timeline: timeline, time: time)
        let (background, parent) = colors(r.level)
        let fridayNext = status.next == .dhuhr && friday
        let title = status.next.targetTitle(friday: fridayNext, ramadan: ramadan)
        let nameAndTime =
            "\(status.current.name(friday: status.current == .dhuhr && friday)) \(status.currentStart.timeText(tz))"
        // After midnight Isha began yesterday; without „Dün“ 19:55 next to the row with 19:53 looks wrong ().
        let previous =
            Self.isYesterday(status.currentStart, time: time, tz: tz)
            ? localized("bugun.dun \(nameAndTime)") : nameAndTime
        let percent = ratio.formatted(.percent.precision(.fractionLength(0)).locale(AppLanguage.locale))
        let note = noteText(r)
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(app: "bugun.siradaki \(name(fridayNext))")
                Spacer(minLength: 8)
                Text(verbatim: status.nextTime.timeText(tz)).monospacedDigit()
            }
            .typography(.emphasized)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: s.text).typography(.accent).monospacedDigit()
                Text(verbatim: s.secondsText).typography(.title2).monospacedDigit().opacity(0.8)
            }
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            if let note {
                let row = HStack(spacing: 4) {
                    Text(verbatim: note)
                    if r.karahat != nil { Image(systemName: "info.circle").accessibilityHidden(true) }
                }
                .typography(.footnote)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                if r.karahat != nil {
                    Button(action: openKarahat) { row }.buttonStyle(.plain)
                } else {
                    row
                }
            }
            strip(parent: parent)
                .frame(height: 6)
                .padding(.top, 4)
            HStack {
                Text(verbatim: previous)
                Spacer(minLength: 8)
                Text(verbatim: percent).monospacedDigit()
            }
            .typography(.footnote)
            .opacity(0.9)
        }
        .foregroundStyle(parent)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: .rect(cornerRadius: 24))
        .animation(.easeInOut(duration: 0.6), value: r.level)
        .padding(.top, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(s.spoken)")
        .accessibilityValue(
            [note, localized("bugun.ilerleme \(previous) \(percent)")].compactMap { $0 }.joined(
                separator: ", ")
        )
        .accessibilityActions {
            if r.karahat != nil { Button(localized("kerahat.nedir"), action: openKarahat) }
        }
    }

    /// Calm on `accent`; tight (≤ 30 min for the current prayer) on `uyari`; in the karahat on
    /// `failed`. All three pairs are checked for contrast in both schemes.
    private func colors(_ level: Urgency.Level) -> (Color, Color) {
        switch level {
        case .relaxed: (theme.colors.accent, theme.colors.onAccent)
        case .az: (theme.colors.warningBackground, theme.colors.warningText)
        case .karahat: (theme.colors.errorBackground, theme.colors.errorText)
        }
    }

    /// The line below the countdown: karahat now, tight deadline, or the start of a karahat
    /// that lies before the next prayer time. Otherwise nothing - the card stays calm.
    private func noteText(_ r: Urgency) -> String? {
        // During the İmsak prayer time the Sabah prayer is performed; „İmsak için“ would be misleading.
        let name =
            status.current == .imsak
            ? localized("vakit.sabah_namazi")
            : status.current.name(friday: status.current == .dhuhr && friday)
        switch r.level {
        case .karahat:
            return r.karahat.map { localized("bugun.kerahat.simdi \($0.end.timeText(tz))") }
        case .az:
            guard let end = r.lastDate else { return nil }
            let remaining = Counter(remaining: end.timeIntervalSince(time)).text
            return r.karahat == nil
                ? localized("bugun.az \(name) \(remaining)")
                : localized("bugun.az.kerahat \(name) \(remaining) \(end.timeText(tz))")
        case .relaxed:
            return r.karahat.map { localized("bugun.kerahat.baslar \($0.start.timeText(tz))") }
        }
    }

    /// Progress from the current to the next prayer time; karahat sections within it hatched.
    private func strip(parent: Color) -> some View {
        let start = status.currentStart
        let total = max(1, status.nextTime.timeIntervalSince(start))
        let parts = timeline.karahatWindows.compactMap { k -> (Double, Double)? in
            let x0 = max(0, k.start.timeIntervalSince(start) / total)
            let x1 = min(1, k.end.timeIntervalSince(start) / total)
            return x1 > x0 ? (x0, x1) : nil
        }
        return Canvas { c, size in
            let tam = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2)
            c.clip(to: tam)
            c.fill(tam, with: .color(parent.opacity(0.3)))
            for (x0, x1) in parts {
                let r = CGRect(
                    x: x0 * size.width, y: 0, width: (x1 - x0) * size.width, height: size.height)
                var tickLines = Path()
                var x = r.minX - size.height
                while x < r.maxX {
                    tickLines.move(to: CGPoint(x: x, y: size.height))
                    tickLines.addLine(to: CGPoint(x: x + size.height, y: 0))
                    x += 4
                }
                c.drawLayer { k in
                    k.clip(to: Path(r))
                    k.stroke(tickLines, with: .color(parent.opacity(0.75)), lineWidth: 1.5)
                }
            }
            c.fill(
                Path(
                    roundedRect: CGRect(
                        x: 0, y: 0, width: max(size.height, size.width * ratio), height: size.height),
                    cornerRadius: size.height / 2),
                with: .color(parent))
        }
        .accessibilityHidden(true)
    }

    /// Does the start of the current prayer time lie on an earlier calendar day at the place?
    static func isYesterday(_ start: Date, time: Date, tz: TimeZone) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        return !calendar.isDate(start, inSameDayAs: time)
    }

    /// Fraction of the time from the start of the current to the next prayer time.
    private var ratio: Double {
        let total = status.nextTime.timeIntervalSince(status.currentStart)
        guard total > 0 else { return 0 }
        return min(1, max(0, time.timeIntervalSince(status.currentStart) / total))
    }

    /// In Ramadan, „İftar“ is added at Maghrib and „Sahur“ at İmsak.
    private func name(_ fridayNext: Bool) -> String {
        let name = status.next.name(friday: fridayNext)
        guard ramadan else { return name }
        switch status.next {
        case .maghrib: return "\(name) · \(localized("ramazan.iftar"))"
        case .imsak: return "\(name) · \(localized("ramazan.sahur"))"
        default: return name
        }
    }
}

/// The remaining five times in one row; the next prayer time is already in the card.
///
/// If the row no longer fits at large font size, it wraps into a grid instead of cutting off
/// numbers.
struct OtherTimes: View {
    @Environment(\.theme) private var theme
    let day: DailyPrayerTimes
    let status: PrayerTimeStatus
    let tz: TimeZone
    let friday: Bool
    let tomorrow: Bool

    var body: some View {
        // All six times, including the next one, always 3 × 2 - equally
        // symmetric on every iPhone instead of one or two rows depending on width.
        VStack(alignment: .leading, spacing: 6) {
            if tomorrow {
                Text(app: "vakit.yarin.baslik").typography(.footnote).foregroundStyle(theme.colors.text2)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(Prayer.allCases, id: \.self) { n in
                    cell(n).frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    /// A time cell; long names shrink instead of running into the
    /// neighboring cell, and İmsak carries the short name there („Morgengebet“ instead of „İmsak (Morgengebet)“, Fable W5).
    private func cell(_ n: Prayer) -> some View {
        let now = !tomorrow && status.current == n && status.currentStart == day[n]
        let next = status.next == n && status.nextTime == day[n]
        return VStack(spacing: 2) {
            HStack(spacing: 4) {
                if now {
                    Circle().fill(theme.colors.sage).frame(width: 6, height: 6).accessibilityHidden(true)
                }
                Text(verbatim: n == .imsak ? localized("vakit.imsak.kisa") : n.name(friday: friday))
                    .foregroundStyle(theme.colors.text2)
            }
            .typography(.footnote)
            Text(verbatim: day[n].timeText(tz)).typography(.emphasized).monospacedDigit()
                .foregroundStyle(n == .sunrise ? theme.colors.text2 : theme.colors.text)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(next ? theme.colors.surface2 : .clear, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityValue(now ? localized("vakit.simdi") : next ? localized("vakit.siradaki") : "")
    }
}
