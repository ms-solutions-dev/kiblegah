import AppIntents
import Core
import DesignSystem
import SwiftUI
import WidgetBridge
import WidgetKit

// The large and extra large widgets for the iPad (canvas boards G22 and G23). The file is also compiled into
// the app, where the debug gallery `-widgetGaleri` shows the views next to the boards.
//
// The system keeps a margin of 16 pt around the content; `inset` adds what the boards have on top of it.

extension PrayerStatus.Signal {
    var color: Color {
        switch self {
        case .green: WidgetColor.green
        case .orange: WidgetColor.orange
        case .red: WidgetColor.red
        }
    }
}

extension PrayerStatus {
    var widgetTitle: Text {
        switch (kind, karahatKind) {
        case (.prayerTime, _): Text(app: "widget.sayac.vakti \(name)")
        case (_, .sunrise?): Text(app: "widget.sayac.ker.gunes")
        case (_, .zawal?): Text(app: "widget.sayac.ker.zeval")
        case (_, .maghrib?): Text(app: "widget.sayac.ker.aksam")
        case (_, .other?): Text(app: "widget.sayac.ker")
        default: Text(verbatim: name)
        }
    }

    /// „18:25“, during Karahat „18:25'e kadar“, during the 45 seconds of „vakti“ nothing.
    func widgetClockLine(_ clock: (Date) -> String) -> Text? {
        guard let time else { return nil }
        return kind == .karahat
            ? Text(app: "widget.sayac.kadar \(clock(time))") : Text(verbatim: clock(time))
    }
}

private func padLabel(_ t: Text, size: CGFloat = 11) -> some View {
    t.font(WidgetColor.font(size, .bold)).tracking(1).textCase(.uppercase).foregroundStyle(WidgetColor.label)
}

// MARK: - Prayer times

struct PadPrayerWidget: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let date: Date
    let status: PrayerStatus
    let snapshot: PrayerTimesSnapshot
    let extraLarge: Bool

    var body: some View {
        if extraLarge {
            HStack(spacing: 26) {
                VStack(alignment: .leading, spacing: 0) {
                    label
                    Spacer(minLength: 0)
                    name(34)
                    countdown(68).padding(.vertical, -9).padding(.top, 8).padding(.bottom, 14)
                    bar
                    place(14).padding(.top, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                times(size: 18, horizontal: 12, vertical: 9).frame(width: 290)
            }
            .padding(6)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                label
                name(26).padding(.vertical, -2).padding(.top, 10)
                countdown(44).padding(.vertical, -6).padding(.top, 6).padding(.bottom, 8)
                bar
                place(13).padding(.top, 6).padding(.bottom, 8)
                times(size: 15, horizontal: 10, vertical: 4)
            }
            .padding(2)
        }
    }

    private var accent: Color { renderingMode == .fullColor ? status.signal.color : .primary }

    private var label: some View {
        padLabel(
            status.kind == .karahat
                ? Text(app: "widget.sayac.marka.kerahat") : Text(app: "widget.vakit.etiket"))
    }

    private func name(_ size: CGFloat) -> some View {
        status.widgetTitle.font(WidgetColor.font(size, .bold)).foregroundStyle(WidgetColor.text)
            .lineLimit(1).minimumScaleFactor(0.6)
    }

    private func countdown(_ size: CGFloat) -> some View {
        Text(status.target, style: .timer)
            .font(WidgetColor.serif(size)).monospacedDigit()
            .multilineTextAlignment(.leading)
            .foregroundStyle(accent).lineLimit(1).minimumScaleFactor(0.6)
            .widgetAccentable()
    }

    private var bar: some View {
        ProgressView(timerInterval: status.start...max(status.start, status.end), countsDown: false) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.linear)
        .tint(accent)
        .scaleEffect(x: 1, y: 1.5)
    }

    private func clock(_ t: Date) -> String {
        t.clockText(
            in: TimeZone(identifier: snapshot.timeZoneIdentifier) ?? .current, locale: AppLanguage.clockLocale
        )
    }

    private func place(_ size: CGFloat) -> some View {
        HStack(spacing: 4) {
            if let line = status.widgetClockLine(clock) {
                line
                Text(verbatim: "·")
            }
            Text(verbatim: snapshot.location)
        }
        .font(WidgetColor.font(size, .medium)).foregroundStyle(WidgetColor.text2).lineLimit(1)
    }

    /// The six times of the day the next prayer falls on: after Yatsı that is already tomorrow.
    private func dayTimes(next: PrayerTimesSnapshot.PrayerTime?) -> [PrayerTimesSnapshot.PrayerTime] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: snapshot.timeZoneIdentifier) ?? .current
        let day = calendar.startOfDay(for: next?.time ?? date)
        return Array(snapshot.prayerTimes.filter { calendar.startOfDay(for: $0.time) == day }.prefix(6))
    }

    private func times(size: CGFloat, horizontal: CGFloat, vertical: CGFloat) -> some View {
        let next = snapshot.entry(time: date)?.next
        let rows = dayTimes(next: next)
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, v in
                if i > 0 { Spacer(minLength: 0) }
                let active = v.time == next?.time
                HStack {
                    Text(verbatim: v.name).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 6)
                    Text(verbatim: clock(v.time)).monospacedDigit()
                }
                .font(WidgetColor.font(size, active ? .bold : .medium))
                .foregroundStyle(v.time < date ? WidgetColor.text2 : WidgetColor.text)
                .padding(.horizontal, horizontal).padding(.vertical, vertical)
                .background(active ? WidgetColor.surface2 : .clear, in: .rect(cornerRadius: 10))
            }
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Quran

struct PadQuranGoal {
    let surah: Int
    let verse: Int
    let title: String
    /// Reciter if something was listened to last.
    let bottom: String?
    let isPlaying: Bool
}

struct PadQuranWidget: View {
    let date: Date
    let goal: PadQuranGoal?
    let reading: ReadingSnapshot?
    let extraLarge: Bool

    private static let totalVerses = 6236

    var body: some View {
        if extraLarge {
            HStack(spacing: 30) {
                VStack(alignment: .leading, spacing: 0) {
                    padLabel(Text(app: "widget.kuran.etiket"))
                    title(32, subtitle: 14, gap: 6).padding(.top, 14)
                    Spacer(minLength: 0)
                    HStack(alignment: .bottom, spacing: 16) {
                        if let goal { listen(goal) }
                        VStack(alignment: .leading, spacing: 3) {
                            percent
                            Text(app: "ipad.widget.hatimVerse \(number(khatm)) \(number(Self.totalVerses))")
                                .font(WidgetColor.font(12, .medium)).foregroundStyle(WidgetColor.text2)
                                .lineLimit(2)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 16) {
                    stats {
                        value(
                            Text(verbatim: "\(reading?.todayMinutes ?? 0)"), Text(app: "ipad.widget.minHeute")
                        )
                        value(
                            Text(verbatim: "\(reading?.weekVerses ?? 0)"), Text(app: "ipad.widget.versWoche"))
                        value(Text(verbatim: "\(reading?.streak ?? 0)"), Text(app: "ipad.widget.tageSerie"))
                    }
                    bars(tallest: 190)
                }
                .frame(width: 300)
            }
            .padding(8)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                padLabel(Text(app: "widget.kuran.etiket"))
                HStack(spacing: 12) {
                    title(22, subtitle: 13, gap: 4).frame(maxWidth: .infinity, alignment: .leading)
                    if let goal { listen(goal) }
                }
                .padding(.top, 12)
                stats {
                    value(Text(verbatim: "\(reading?.todayMinutes ?? 0)"), Text(app: "ipad.widget.minHeute"))
                    value(Text(verbatim: "\(reading?.streak ?? 0)"), Text(app: "ipad.widget.tageSerie"))
                    VStack(alignment: .leading, spacing: 3) {
                        percent
                        statCaption(Text(app: "ipad.widget.hatim"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 18).padding(.bottom, 14)
                bars(tallest: 90)
            }
            .padding(2)
        }
    }

    private var khatm: Int { reading?.khatmVerses ?? 0 }

    private func number(_ n: Int) -> String { n.formatted(.number.locale(AppLanguage.clockLocale)) }

    @ViewBuilder private func title(_ size: CGFloat, subtitle: CGFloat, gap: CGFloat) -> some View {
        if let goal {
            VStack(alignment: .leading, spacing: gap) {
                Text(verbatim: goal.title).font(WidgetColor.font(size, .bold)).foregroundStyle(
                    WidgetColor.text
                )
                .lineLimit(1).minimumScaleFactor(0.7)
                Group {
                    if let bottom = goal.bottom {
                        Text(app: "widget.kuran.dinle \(bottom)")
                    } else {
                        Text(app: "ipad.widget.weiterlesen")
                    }
                }
                .font(WidgetColor.font(subtitle, .medium)).foregroundStyle(WidgetColor.text2).lineLimit(1)
            }
        } else {
            Text(app: "widget.okuma.bos").font(WidgetColor.font(subtitle, .medium))
                .foregroundStyle(WidgetColor.text2)
        }
    }

    /// Play/pause as in the small widgets: runs in the app, does not bring it to the foreground.
    private func listen(_ goal: PadQuranGoal) -> some View {
        Button(intent: KuranDinleNiyeti(surah: goal.surah, verse: goal.verse)) {
            Image(systemName: goal.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(WidgetColor.onAccent)
                .frame(width: 56, height: 56)
                .background(WidgetColor.accent, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(app: goal.isPlaying ? "widget.dinle.duraklat" : "widget.dinle.cal"))
    }

    private var percent: some View {
        statValue(
            Text(
                app:
                    "ipad.widget.prozent \(Int((Double(khatm) / Double(Self.totalVerses) * 100).rounded(.down)))"
            ))
    }

    private func stats<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 8) { content() }
    }

    private func value(_ number: Text, _ caption: Text) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            statValue(number)
            statCaption(caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statValue(_ t: Text) -> some View {
        t.font(WidgetColor.serif(24)).monospacedDigit().foregroundStyle(WidgetColor.text).lineLimit(1)
    }

    private func statCaption(_ t: Text) -> some View {
        t.font(WidgetColor.font(12, .medium)).foregroundStyle(WidgetColor.text2).lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private var todayIndex: Int {
        guard let reading else { return -1 }
        return Calendar.current.dateComponents([.day], from: reading.weekStart, to: date).day ?? -1
    }

    private func bars(tallest: CGFloat) -> some View {
        PadWeekBars(
            tallest: tallest, minutes: reading?.weekMinutes ?? Array(repeating: 0, count: 7),
            today: todayIndex,
            weekStart: reading?.weekStart ?? Calendar.current.dateInterval(of: .weekOfYear, for: date)?.start
                ?? date
        )
    }
}

/// Seven bars with the initials of the weekdays; the highest day reaches `tallest`, today in the accent color.
struct PadWeekBars: View {
    let tallest: CGFloat
    let minutes: [Int]
    let today: Int
    let weekStart: Date

    private func initial(_ i: Int) -> String {
        var calendar = Calendar.current
        calendar.locale = AppLanguage.clockLocale
        guard let day = calendar.date(byAdding: .day, value: i, to: weekStart) else { return "" }
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return symbols[calendar.component(.weekday, from: day) - 1]
    }

    private func height(_ share: CGFloat, in available: CGFloat) -> CGFloat {
        let top = min(tallest, available)
        return max(top * 0.07, top * share)
    }

    var body: some View {
        let most = CGFloat(max(minutes.max() ?? 0, 1))
        HStack(alignment: .bottom, spacing: 7) {
            ForEach(Array(minutes.enumerated()), id: \.offset) { i, d in
                VStack(spacing: 5) {
                    GeometryReader { g in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(i == today ? WidgetColor.accent : WidgetColor.bar)
                            .frame(height: height(CGFloat(d) / most, in: g.size.height))
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                    Text(verbatim: initial(i))
                        .font(WidgetColor.font(11, .semibold)).foregroundStyle(WidgetColor.text2)
                }
            }
        }
    }
}

// MARK: - Verse of the day

/// A verse is never cut off: long verses move down the steps, the last one scales with the available space.
struct PadVerseWidget: View {
    let verse: VerseSnapshot.DailyEntry
    let extraLarge: Bool

    private var reference: String { verse.link?.lastPathComponent ?? "" }

    /// „Al-Baqara 2“ from the snapshot becomes „Al-Baqara 2:2“.
    private var fullReference: String {
        guard !reference.isEmpty else { return verse.title }
        let name = verse.title.split(separator: " ").dropLast().joined(separator: " ")
        return name.isEmpty ? reference : "\(name) \(reference)"
    }

    var body: some View {
        if extraLarge {
            VStack(spacing: 0) {
                header(fullReference)
                ViewThatFits(in: .vertical) {
                    content(40, 18, gap: 12)
                    content(34, 16, gap: 10)
                    content(28, 15, gap: 8)
                    content(22, 13, gap: 6)
                    content(18, 12, gap: 4, scales: true)
                }
                .padding(.top, 6)
                .frame(maxHeight: .infinity)
            }
            .padding(8)
        } else {
            VStack(spacing: 0) {
                header(reference)
                ViewThatFits(in: .vertical) {
                    content(30, 15, gap: 12)
                    content(26, 14, gap: 10)
                    content(22, 13, gap: 8)
                    content(18, 12, gap: 6)
                    content(15, 11, gap: 4, scales: true)
                }
                .padding(.top, 18)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(2)
        }
    }

    private func header(_ reference: String) -> some View {
        HStack {
            padLabel(Text(app: "widget.ayet.ad"))
            Spacer(minLength: 8)
            padLabel(Text(verbatim: reference)).lineLimit(1)
        }
    }

    private func content(_ arabic: CGFloat, _ meal: CGFloat, gap: CGFloat, scales: Bool = false) -> some View
    {
        VStack(alignment: .leading, spacing: gap) {
            Text(verbatim: verse.arabic)
                .font(.custom(Typography.arabicFontName, fixedSize: arabic))
                .lineSpacing(arabic * 0.2)
                .foregroundStyle(WidgetColor.text)
                .multilineTextAlignment(.leading)
                .environment(\.layoutDirection, .rightToLeft)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .fixedSize(horizontal: false, vertical: !scales)
                .minimumScaleFactor(scales ? 0.5 : 1)
            Text(verbatim: verse.translation)
                .font(WidgetColor.font(meal, .medium)).lineSpacing(meal * 0.2)
                .foregroundStyle(WidgetColor.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: !scales)
                .minimumScaleFactor(scales ? 0.5 : 1)
        }
    }
}
