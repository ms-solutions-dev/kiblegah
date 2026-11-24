import Core
import DesignSystem
import PrayerTimes
import SwiftUI
import UserData

/// The next prayer as a band (board G04): one component, three sizes, five states.
///
/// Time is information, no alarm: nothing pulses, nothing sounds. It updates once a minute and only
/// counts seconds in the last quarter of an hour. Tapping opens all times of the day.
struct PrayerBand: View {
    enum Style {
        /// Sidebar: stacked, with a thin line.
        case card
        /// Foot bars and player: symbol, label and value next to each other.
        case capsule
        /// Narrow windows and reading bars: one line.
        case chip
    }

    /// From this many minutes before the prayer the band changes color and counts seconds.
    nonisolated static let soonMinutes = 15.0
    /// How long the band shows „now“ after a prayer time began.
    nonisolated static let nowMinutes = 5.0

    @Environment(PrayerTimeModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let style: Style
    /// Text at the end of the capsule (portrait foot: „Zeiten ansehen“).
    var trailing: String? = nil
    @State private var timesOpen = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let state = BandState(
                table: settings.location == nil ? nil : model.table,
                time: context.date + TodayScreen.timeShift,
                karahatMinutes: settings.karahatMinutes)
            Button {
                timesOpen = true
            } label: {
                content(state)
            }
            .buttonStyle(.plain)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: state.level)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(state.spoken)
            .accessibilityHint(localized("ipad.band.ipucu"))
        }
        .popover(isPresented: $timesOpen) {
            PrayerDayPopover()
        }
    }

    @ViewBuilder
    private func content(_ s: BandState) -> some View {
        let colors = palette(s.level)
        Group {
            switch style {
            case .card:
                VStack(alignment: .leading, spacing: 5) {
                    Text(verbatim: s.overline).font(.custom("Plus Jakarta Sans", size: 11).weight(.bold))
                        .tracking(0.9).textCase(.uppercase).opacity(0.85)
                    Text(verbatim: s.value).font(.custom("Fraunces", size: 22).weight(.semibold))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                        .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
                    if let progress = s.progress {
                        Capsule().fill(colors.foreground.opacity(0.2)).frame(height: 5)
                            .overlay(alignment: .leading) {
                                GeometryReader { g in
                                    Capsule().fill(colors.line)
                                        .frame(width: max(5, g.size.width * progress))
                                }
                            }
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            case .capsule:
                HStack(spacing: 12) {
                    Image(systemName: s.symbol).font(.system(size: 22)).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(verbatim: s.overline).font(.custom("Plus Jakarta Sans", size: 11).weight(.bold))
                            .tracking(0.9).textCase(.uppercase).opacity(0.85)
                        Text(verbatim: s.value).font(.custom("Fraunces", size: 20).weight(.semibold))
                            .monospacedDigit()
                            .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
                    }
                    Spacer(minLength: 8)
                    if let trailing {
                        Text(verbatim: trailing).typography(.label(size: 14)).opacity(0.9)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            case .chip:
                HStack(spacing: 8) {
                    Image(systemName: s.symbol).font(.system(size: 17)).accessibilityHidden(true)
                    Text(verbatim: s.short).font(.custom("Fraunces", size: 16).weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 14).frame(minHeight: 44)
            }
        }
        .foregroundStyle(colors.foreground)
        .background(colors.background, in: .rect(cornerRadius: style == .chip ? 22 : 24))
        .overlay {
            if let border = colors.border {
                RoundedRectangle(cornerRadius: style == .chip ? 22 : 24).strokeBorder(border, lineWidth: 1.5)
            }
        }
        .contentShape(.rect(cornerRadius: 24))
    }

    private struct Colors {
        let background: Color
        let foreground: Color
        let line: Color
        let border: Color?
    }

    /// In dark themes a tint and an outline instead of a filled area: at night the band must not be the
    /// brightest thing on the screen.
    private func palette(_ level: BandState.Level) -> Colors {
        let c = theme.colors
        switch level {
        case .calm:
            return Colors(background: c.surface2, foreground: c.text, line: c.accent, border: nil)
        case .soon:
            return c.dark
                ? Colors(
                    background: c.accent.opacity(0.22), foreground: c.text, line: c.accent, border: c.accent)
                : Colors(background: c.accent, foreground: c.onAccent, line: c.onAccent, border: nil)
        case .now:
            return c.dark
                ? Colors(background: c.sage.opacity(0.22), foreground: c.text, line: c.sage, border: c.sage)
                : Colors(background: c.sage, foreground: .white, line: .white, border: nil)
        case .karahat:
            return Colors(
                background: c.warningBackground, foreground: c.warningText, line: c.warningText,
                border: c.warningText)
        case .noLocation:
            return Colors(background: .clear, foreground: c.text, line: c.text, border: c.control)
        }
    }
}

/// The chip of the band for other packages (Sohbet in portrait, board G14).
public struct PadPrayerChip: View {
    public init() {}
    public var body: some View { PrayerBand(style: .chip) }
}

/// What the band says at a moment. Pure, so that the states can be tested without a screen.
struct BandState: Equatable {
    enum Level: Equatable { case calm, soon, now, karahat, noLocation }

    let level: Level
    let overline: String
    let value: String
    let short: String
    let symbol: String
    let progress: Double?
    let spoken: String

    init(table: PrayerTimeTable?, time: Date, karahatMinutes: Int) {
        guard let table, let status = PrayerTimeStatus(table: table, time: time) else {
            let chooser = localized("ipad.band.standort")
            level = .noLocation
            overline = localized("ipad.band.zeiten")
            value = chooser
            short = chooser
            symbol = "mappin.and.ellipse"
            progress = nil
            spoken = chooser
            return
        }
        let tz = table.location.timeZone
        let today = Day(time, timeZoneIdentifier: tz)
        let timeline = table.day(today).map {
            DayTimeline(today: $0, tomorrow: table.day(today.added(1)), karahatMinutes: karahatMinutes)
        }
        let friday = timeline?.isFriday ?? false
        let name = status.next.name(friday: status.next == .dhuhr && friday)
        let clock = status.nextTime.timeText(tz)
        let remaining = status.nextTime.timeIntervalSince(time)
        let counter = Counter(remaining: remaining)
        let total = max(1, status.nextTime.timeIntervalSince(status.currentStart))
        let done = min(1, max(0, time.timeIntervalSince(status.currentStart) / total))
        // Rounded up to the minute as on the iPhone, so that „0 min“ never appears.
        let minutes = Counter(remaining: (remaining / 60).rounded(.up) * 60)

        if let k = timeline?.karahat(time) {
            level = .karahat
            overline = localized("ipad.band.kerahat")
            value = localized("ipad.band.bis \(k.end.timeText(tz))")
            short = localized("ipad.band.kerahat")
            symbol = "bell"
            progress = nil
            spoken = localized("kerahat.bant \(k.end.timeText(tz))")
            return
        }
        let sinceStart = time.timeIntervalSince(status.currentStart)
        if status.current.isPrayer, sinceStart >= 0, sinceStart < PrayerBand.nowMinutes * 60 {
            let current = status.current.name(friday: status.current == .dhuhr && friday)
            let started = status.currentStart.timeText(tz)
            level = .now
            overline = localized("ipad.band.jetzt")
            value = "\(current) · \(started)"
            short = localized("ipad.band.jetzt.kurz \(current)")
            symbol = "sun.max"
            progress = nil
            spoken = localized("ipad.band.jetzt.gesprochen \(current) \(started)")
            return
        }
        let soon = remaining <= PrayerBand.soonMinutes * 60
        level = soon ? .soon : .calm
        overline = "\(name) · \(clock)"
        let text = soon ? counter.text + " " + counter.secondsText : minutes.text
        value = localized("ipad.band.in \(text)")
        short = localized("ipad.band.kurz \(name) \(text)")
        symbol = "sun.horizon"
        progress = done
        spoken = localized("ipad.band.gesprochen \(name) \(clock) \(minutes.spoken)")
    }
}

/// Switches the notification at the time of one prayer, the same setting as in Bildirimler.
struct PrayerBell: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PrayerTimeModel.self) private var prayerTimes
    @Environment(NotificationManager.self) private var notification
    @Environment(\.theme) private var theme
    let prayer: Prayer

    var body: some View {
        let on = (NotificationManager.settings(settings)[prayer] ?? .standard(prayer)).atTime
        Button {
            var all = NotificationManager.settings(settings)
            var one = all[prayer] ?? .standard(prayer)
            one.atTime.toggle()
            all[prayer] = one
            NotificationManager.save(all, settings)
            Task {
                if notification.allowed == .notDetermined { await notification.requestPermission() }
                await notification.schedule(table: prayerTimes.table, settings: settings)
            }
        } label: {
            Image(systemName: "bell")
                .font(.system(size: 19))
                .foregroundStyle(on ? theme.colors.accent : theme.colors.text2)
                .frame(width: 44, height: 44)
                .background(on ? theme.colors.accent.opacity(0.12) : .clear, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localized("ipad.glocke \(prayer.name())"))
        .accessibilityValue(on ? localized("ipad.an") : localized("ipad.aus"))
    }
}

/// All times of the day with their bell, from the band or the hero: look without leaving the page.
struct PrayerDayPopover: View {
    @Environment(PrayerTimeModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 2) {
                if let table = model.table,
                    let day = table.day(Day(context.date, timeZoneIdentifier: table.location.timeZone))
                {
                    let tz = table.location.timeZone
                    let status = PrayerTimeStatus(table: table, time: context.date)
                    ForEach(Prayer.allCases, id: \.self) { n in
                        let next = status?.next == n && status?.nextTime == day[n]
                        HStack {
                            Text(verbatim: n.name())
                                .foregroundStyle(next ? theme.colors.accent : theme.colors.text2)
                            Spacer(minLength: 24)
                            Text(verbatim: day[n].timeText(tz)).monospacedDigit()
                                .font(.custom("Fraunces", size: 20).weight(.semibold))
                                .foregroundStyle(next ? theme.colors.accent : theme.colors.text)
                            PrayerBell(prayer: n)
                        }
                        .padding(.leading, 14)
                        .padding(.vertical, 2)
                        .background(next ? theme.colors.surface2 : .clear, in: .rect(cornerRadius: 14))
                    }
                } else {
                    Text(app: "ipad.band.standort").padding()
                }
            }
            .padding(10)
            .frame(minWidth: 300)
        }
        .presentationCompactAdaptation(.popover)
    }
}
