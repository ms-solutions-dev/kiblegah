import Core
import DesignSystem
import SwiftUI
import WidgetBridge
import WidgetKit

/// Widgets, Live Activity and Qibla control. Since Oct 19 three widgets:
/// Namaz vakti, Kur'an, Günün ayeti - plus Live Activity and the Qibla control.
@main
struct KiblegahWidgets: WidgetBundle {
    init() {
        Typography.save()
    }

    var body: some Widget {
        PrayerTimeWidget()
        QuranWidget()
        VerseWidget()
        PrayerTimeLiveActivity()
        QiblaControl()
    }
}

// MARK: Timeline

struct PrayerTimeEntry: TimelineEntry {
    let date: Date
    let status: PrayerStatus?
    let snapshot: PrayerTimesSnapshot?
}

/// One entry per change (prayer, Karahat, traffic-light level, „vakti“) from the app's snapshot, 36 h
/// ahead; in between countdown and bar run by themselves. Used up: open the app, do not guess.
struct PrayerTimeProvider: TimelineProvider {
    func placeholder(in context: Context) -> PrayerTimeEntry {
        PrayerTimeEntry(date: .now, status: Self.sample, snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (PrayerTimeEntry) -> Void) {
        let a = PrayerTimesSnapshot.load()
        let d = a.flatMap { PrayerStatus.status($0, now: .now) } ?? (context.isPreview ? Self.sample : nil)
        completion(PrayerTimeEntry(date: .now, status: d, snapshot: a))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PrayerTimeEntry>) -> Void) {
        let now = Date.now
        guard let a = PrayerTimesSnapshot.load() else {
            completion(
                Timeline(
                    entries: [PrayerTimeEntry(date: now, status: nil, snapshot: nil)],
                    policy: .after(now + 1800))
            )
            return
        }
        let instants = [now] + PrayerStatus.changes(a, after: now).filter { $0 < now + 36 * 3600 }
        completion(
            Timeline(
                entries: instants.map {
                    PrayerTimeEntry(date: $0, status: PrayerStatus.status(a, now: $0), snapshot: a)
                },
                policy: .after((instants.last ?? now) + 60)))
    }

    static var sample: PrayerStatus {
        let goal = Date.now.addingTimeInterval(93 * 60)
        return PrayerStatus(
            kind: .target, name: "Akşam", karahatKind: nil, time: goal, target: goal,
            start: .now.addingTimeInterval(-150 * 60), end: goal, signal: .green)
    }
}

// MARK: Widget

/// Namaz vakti: the countdown with the traffic light from Nabız (green above 30, orange up to 15 minutes,
/// below that, in Karahat and „vakti“ red), in the style of the app. Medium also shows the times.
struct PrayerTimeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "vakit", provider: PrayerTimeProvider()) { g in
            PrayerTimeWidgetView(g: g)
                .containerBackground(for: .widget) { WidgetColor.background }
                .widgetURL(URL(string: "kiblegah://vakit"))
        }
        .configurationDisplayName(Text(app: "widget.vakit.ad"))
        .description(Text(app: "widget.vakit.aciklama"))
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge, .accessoryRectangular,
            .accessoryCircular, .accessoryInline,
        ])
    }
}

struct PrayerTimeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    /// Traffic-light color only where the system shows colors; the lock screen tints by itself.
    @Environment(\.widgetRenderingMode) private var renderingMode
    let g: PrayerTimeEntry

    var body: some View {
        if let d = g.status, let a = g.snapshot {
            switch family {
            case .accessoryInline: row(d)
            case .accessoryCircular: circular(d)
            case .accessoryRectangular: rectangular(d)
            case .systemLarge, .systemExtraLarge:
                PadPrayerWidget(date: g.date, status: d, snapshot: a, extraLarge: family == .systemExtraLarge)
            case .systemMedium:
                HStack(alignment: .top, spacing: 16) {
                    counter(d, a, wide: false).frame(width: 132)
                    list(a)
                }
            default: counter(d, a, wide: true)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                label(Text(app: "widget.vakit.etiket"))
                Spacer(minLength: 0)
                Text(app: "widget.ac").font(WidgetColor.font(13)).foregroundStyle(WidgetColor.text2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func accent(_ d: PrayerStatus) -> Color {
        renderingMode == .fullColor ? d.signal.color : .primary
    }

    private func label(_ t: Text) -> some View {
        t.font(WidgetColor.font(10, .bold)).tracking(0.8).textCase(.uppercase).foregroundStyle(
            WidgetColor.label)
    }

    private func title(_ d: PrayerStatus) -> Text { d.widgetTitle }

    private func timeText(_ t: Date) -> String {
        t.clockText(
            in: g.snapshot.flatMap { TimeZone(identifier: $0.timeZoneIdentifier) } ?? .current,
            locale: AppLanguage.clockLocale)
    }

    private func clockLine(_ d: PrayerStatus) -> Text? { d.widgetClockLine(timeText) }

    private func bar(_ d: PrayerStatus, color: Color) -> some View {
        ProgressView(timerInterval: d.start...max(d.start, d.end), countsDown: false) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.linear)
        .tint(color)
    }

    /// Small (and left in the medium): label, name, countdown in the traffic-light color, bar, time of day.
    private func counter(_ d: PrayerStatus, _ a: PrayerTimesSnapshot, wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            label(
                d.kind == .karahat
                    ? Text(app: "widget.sayac.marka.kerahat") : Text(app: "widget.vakit.etiket")
            )
            Spacer(minLength: 0)
            title(d).font(WidgetColor.font(20, .bold)).foregroundStyle(WidgetColor.text).lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(d.target, style: .timer)
                .font(WidgetColor.font(27, .semibold)).monospacedDigit()
                .foregroundStyle(accent(d)).lineLimit(1).minimumScaleFactor(0.6)
                .widgetAccentable()
            bar(d, color: accent(d)).padding(.top, 4)
            HStack(spacing: 4) {
                clockLine(d)
                if wide { Text(verbatim: "· \(a.location)").lineLimit(1) }
            }
            .font(WidgetColor.font(11)).foregroundStyle(WidgetColor.text2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Right in the medium: the next five times, the current one highlighted.
    private func list(_ a: PrayerTimesSnapshot) -> some View {
        let received = a.entry(time: g.date)
        let next = received?.next
        let times = Array(([received?.current].compactMap { $0 } + (received?.upcoming ?? [])).prefix(5))
        return VStack(alignment: .leading, spacing: 3) {
            // For which location it is calculated.
            Label {
                Text(verbatim: a.location)
            } icon: {
                Image(systemName: "location.fill")
            }
            .labelStyle(.titleAndIcon)
            .font(WidgetColor.font(10, .bold)).tracking(0.6).textCase(.uppercase)
            .foregroundStyle(WidgetColor.label).lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .trailing)
            ForEach(Array(times.enumerated()), id: \.offset) { _, v in
                let active = v.time == next?.time
                HStack {
                    Text(verbatim: v.name)
                    Spacer()
                    Text(verbatim: timeText(v.time)).monospacedDigit()
                }
                .font(WidgetColor.font(13, active ? .bold : .regular))
                .foregroundStyle(v.time < g.date ? WidgetColor.text2 : WidgetColor.text)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(active ? WidgetColor.surface2 : .clear, in: .rect(cornerRadius: 8))
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Lock screen

    private func rectangular(_ d: PrayerStatus) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Circle().fill(accent(d)).frame(width: 6, height: 6)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
                title(d).font(.headline).lineLimit(1)
                clockLine(d)?.font(.caption).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
            }
            Text(d.target, style: .timer).font(.title2.weight(.medium)).monospacedDigit()
            bar(d, color: .primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetAccentable()
    }

    private func circular(_ d: PrayerStatus) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                title(d).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.5)
                clockLine(d)?.font(.system(size: 13, weight: .medium)).monospacedDigit().lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(4)
        }
        .widgetAccentable()
    }

    /// One line above the clock, without countdown (the line truncated it to minutes).
    @ViewBuilder private func row(_ d: PrayerStatus) -> some View {
        if let s = clockLine(d) {
            HStack(spacing: 4) {
                title(d)
                s
            }
        } else {
            title(d)
        }
    }
}
