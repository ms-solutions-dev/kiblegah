import SwiftUI
import WidgetKit
import WidgetBridge

/// Watch complications.
/// They only read the snapshots that the watch app gets from the iPhone and stores in the App Group;
/// traffic light and Karahat come from `PrayerStatus`, as with the iPhone widget.
@main
struct WatchWidgets: WidgetBundle {
    var body: some Widget {
        PrayerTimeComplication()
        DaySchedule()
        QiblaComplication()
        ReadingComplication()
    }
}

// MARK: Timeline prayer time

/// One entry at every boundary (prayer, Karahat, traffic-light level) for 24 h; the day bar (D) needs
/// one every 10 minutes so that the "now" dot moves.
struct WatchProvider: TimelineProvider {
    var step: TimeInterval?

    func placeholder(in context: Context) -> WatchEntry { WatchEntry(date: .now, snapshot: nil, status: nil) }

    func getSnapshot(in context: Context, completion: @escaping (WatchEntry) -> Void) {
        let a = PrayerTimesSnapshot.load()
        completion(WatchEntry(date: .now, snapshot: a, status: a.flatMap { PrayerStatus.status($0, now: .now) }))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchEntry>) -> Void) {
        let now = Date.now
        guard let a = PrayerTimesSnapshot.load() else {
            completion(
                Timeline(
                    entries: [WatchEntry(date: now, snapshot: nil, status: nil)], policy: .after(now + 1800)))
            return
        }
        var instants = [now] + PrayerStatus.changes(a, after: now).filter { $0 < now + 24 * 3600 }
        if let step { instants += stride(from: now + step, to: now + 24 * 3600, by: step).map { $0 } }
        instants = Array(Set(instants)).sorted()
        completion(
            Timeline(
                entries: instants.map { WatchEntry(date: $0, snapshot: a, status: PrayerStatus.status(a, now: $0)) },
                policy: .after((instants.last ?? now) + 60)))
    }
}

// MARK: A · B · C - next prayer

struct PrayerTimeComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "saat-vakit", provider: WatchProvider()) { g in
            PrayerTimeComplicationView(g: g).containerBackground(.clear, for: .widget)
                .widgetURL(URL(string: "kiblegah://vakit"))
        }
        .configurationDisplayName(Text("widget.vakit.ad"))
        .description(Text("widget.vakit.aciklama"))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryCorner])
    }
}

// MARK: D - Day bar

struct DaySchedule: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "saat-gun", provider: WatchProvider(step: 600)) { g in
            DayScheduleView(g: g).containerBackground(.clear, for: .widget)
                .widgetURL(URL(string: "kiblegah://vakit"))
        }
        .configurationDisplayName(Text("saat.widget.gun.ad"))
        .description(Text("saat.widget.gun.aciklama"))
        .supportedFamilies([.accessoryRectangular])
    }
}

// MARK: E - Qibla

struct QiblaComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "saat-kible", provider: WatchProvider()) { g in
            QiblaComplicationView(snapshot: g.snapshot).containerBackground(.clear, for: .widget)
                .widgetURL(URL(string: "kiblegah://kible"))
        }
        .configurationDisplayName(Text("saat.widget.kible.ad"))
        .description(Text("saat.widget.kible.aciklama"))
        .supportedFamilies([.accessoryCircular])
    }
}

// MARK: F - Quran daily goal

struct ReadingEntry: TimelineEntry {
    let date: Date
    let reading: ReadingSnapshot?
}

struct ReadingProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReadingEntry { ReadingEntry(date: .now, reading: nil) }

    func getSnapshot(in context: Context, completion: @escaping (ReadingEntry) -> Void) {
        completion(ReadingEntry(date: .now, reading: ReadingSnapshot.load()?.valid(time: .now)))
    }

    /// Until midnight as written, afterwards with „heute = 0“ (gecerli).
    func getTimeline(in context: Context, completion: @escaping (Timeline<ReadingEntry>) -> Void) {
        let o = ReadingSnapshot.load()
        let now = Date.now
        let tomorrow = Calendar.current.startOfDay(for: now).addingTimeInterval(86400)
        completion(
            Timeline(
                entries: [
                    ReadingEntry(date: now, reading: o?.valid(time: now)),
                    ReadingEntry(date: tomorrow, reading: o?.valid(time: tomorrow)),
                ], policy: .after(tomorrow + 60)))
    }
}

struct ReadingComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "saat-okuma", provider: ReadingProvider()) { g in
            ReadingComplicationView(o: g.reading).containerBackground(.clear, for: .widget)
                .widgetURL(g.reading?.link ?? URL(string: "kiblegah://kuran"))
        }
        .configurationDisplayName(Text("saat.widget.okuma.ad"))
        .description(Text("saat.widget.okuma.aciklama"))
        .supportedFamilies([.accessoryCircular])
    }
}
