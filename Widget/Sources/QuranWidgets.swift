import DesignSystem
import SwiftUI
import WidgetBridge
import WidgetKit

// MARK: - Quran: continue reading/listening and reading statistics in one

struct QuranEntry: TimelineEntry {
    let date: Date
    let reading: ReadingSnapshot?
    let listen: ListenSnapshot?
}

/// One entry now and one at midnight: there "today" falls to 0 and the week advances
/// without the app running. Play/pause and reading write anew and reload.
struct QuranProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuranEntry {
        QuranEntry(date: .now, reading: .sample, listen: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuranEntry) -> Void) {
        let o = ReadingSnapshot.load()?.valid(time: .now)
        completion(
            QuranEntry(
                date: .now, reading: o ?? (context.isPreview ? .sample : nil), listen: ListenSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuranEntry>) -> Void) {
        let now = Date.now
        let o = ReadingSnapshot.load()
        let d = ListenSnapshot.load()
        let night = Calendar.current.date(
            byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
        completion(
            Timeline(
                entries: [
                    QuranEntry(date: now, reading: o?.valid(time: now), listen: d),
                    QuranEntry(date: night, reading: o?.valid(time: night), listen: d),
                ], policy: .after(night + 60)))
    }
}

extension ReadingSnapshot {
    static let sample = ReadingSnapshot(
        day: Calendar.current.startOfDay(for: .now), todayVerses: 24, todayMinutes: 7,
        weekStart: Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now,
        weekMinutes: [4, 9, 0, 6, 7, 0, 0], weekVerses: 96, streak: 2, khatmVerses: 1450,
        lastPosition: "Kehf 10",
        link: nil)
}

struct QuranWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: ReadingSnapshot.kind, provider: QuranProvider()) { g in
            QuranView(g: g)
                .containerBackground(for: .widget) { WidgetColor.background }
                .widgetURL(QuranView.goal(g)?.link ?? URL(string: "kiblegah://kuran"))
        }
        .configurationDisplayName(Text(app: "widget.kuran.ad"))
        .description(Text(app: "widget.kuran.aciklama"))
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge, .accessoryRectangular,
            .accessoryCircular,
        ])
    }
}

struct QuranView: View {
    let g: QuranEntry
    @Environment(\.widgetFamily) private var family

    struct Goal {
        let surah: Int
        let verse: Int
        let title: String
        /// Reciter if something was listened to last; otherwise „Kaldığın yer“.
        let bottom: String?
        let isPlaying: Bool
        var link: URL? { URL(string: "kiblegah://kuran/\(surah):\(verse)") }
    }

    /// Where to continue: what was listened to last, if newer than the reading position, otherwise the reading spot.
    static func goal(_ g: QuranEntry) -> Goal? {
        let reading: Goal? = g.reading.flatMap { o in
            guard let y = o.lastPosition, let l = o.link else { return nil }
            let p = l.lastPathComponent.split(separator: ":").compactMap { Int($0) }
            return p.count == 2
                ? Goal(surah: p[0], verse: p[1], title: y, bottom: nil, isPlaying: false) : nil
        }
        if let d = g.listen, d.isPlaying || reading == nil || d.date > (g.reading?.day ?? .distantPast) {
            return Goal(
                surah: d.surah, verse: d.verse, title: "\(d.surahName) \(d.verse)", bottom: d.reciter,
                isPlaying: d.isPlaying)
        }
        return reading
    }

    var body: some View {
        let h = Self.goal(g)
        let o = g.reading
        switch family {
        case .accessoryRectangular: rows(h, o)
        case .accessoryCircular: ringView(o)
        case .systemLarge, .systemExtraLarge:
            PadQuranWidget(
                date: g.date,
                goal: h.map {
                    PadQuranGoal(
                        surah: $0.surah, verse: $0.verse, title: $0.title, bottom: $0.bottom,
                        isPlaying: $0.isPlaying)
                }, reading: o, extraLarge: family == .systemExtraLarge)
        case .systemMedium:
            HStack(spacing: 14) {
                sol(h, o, intermediate: true)
                VStack(alignment: .leading, spacing: 4) {
                    Spacer(minLength: 0)
                    WeekBars(minutes: o?.weekMinutes ?? Array(repeating: 0, count: 7), today: today(o))
                        .frame(height: 60)
                    Text(app: "widget.kuran.hafta \(o?.weekVerses ?? 0) \(o?.streak ?? 0)")
                        .font(WidgetColor.font(11)).foregroundStyle(WidgetColor.text2).lineLimit(1)
                }
                .frame(width: 150)
            }
        default: sol(h, o, intermediate: false)
        }
    }

    private func label() -> some View {
        Text(app: "widget.kuran.etiket").font(WidgetColor.font(10, .bold)).tracking(0.8).textCase(.uppercase)
            .foregroundStyle(WidgetColor.label)
    }

    @ViewBuilder private func sol(_ h: Goal?, _ o: ReadingSnapshot?, intermediate: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            label()
            if let h {
                Text(verbatim: h.title).font(WidgetColor.font(17, .bold)).foregroundStyle(WidgetColor.text)
                    .lineLimit(1).minimumScaleFactor(0.7).padding(.top, 4)
                Group {
                    if let bottom = h.bottom {
                        Text(app: "widget.kuran.dinle \(bottom)")
                    } else {
                        Text(app: "widget.kuran.kaldigin")
                    }
                }
                .font(WidgetColor.font(11)).foregroundStyle(WidgetColor.text2).lineLimit(1)
                Spacer(minLength: 0)
                HStack(alignment: .bottom) {
                    if intermediate {
                        listenButton(h, 36)
                        Text(
                            app:
                                "widget.kuran.hatim \(Int((Double(o?.khatmVerses ?? 0) / 6236 * 100).rounded(.down)))"
                        )
                        .font(WidgetColor.font(12)).foregroundStyle(WidgetColor.text2)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(app: "widget.okuma.dakika \(o?.todayMinutes ?? 0)").font(
                                WidgetColor.font(20, .semibold)
                            )
                            .foregroundStyle(WidgetColor.text)
                            Text(app: "widget.kuran.bugun_seri \(o?.streak ?? 0)").font(WidgetColor.font(11))
                                .foregroundStyle(WidgetColor.text2)
                        }
                        Spacer(minLength: 4)
                        listenButton(h, 36)
                    }
                }
            } else {
                Spacer(minLength: 0)
                Text(app: "widget.okuma.bos").font(WidgetColor.font(13)).foregroundStyle(WidgetColor.text2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Play/pause as `AudioPlaybackIntent`: runs in the app, does not bring it to the foreground.
    private func listenButton(_ h: Goal, _ size: CGFloat) -> some View {
        Button(intent: KuranDinleNiyeti(surah: h.surah, verse: h.verse)) {
            Image(systemName: h.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(WidgetColor.onAccent)
                .frame(width: size, height: size)
                .background(WidgetColor.accent, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(app: h.isPlaying ? "widget.dinle.duraklat" : "widget.dinle.cal"))
    }

    private func today(_ o: ReadingSnapshot?) -> Int {
        guard let o else { return -1 }
        return Calendar.current.dateComponents([.day], from: o.weekStart, to: g.date).day ?? 0
    }

    private func rows(_ h: Goal?, _ o: ReadingSnapshot?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label {
                if let h { Text(verbatim: h.title) } else { Text(app: "widget.kuran.etiket") }
            } icon: {
                Image(systemName: h?.isPlaying == true ? "headphones" : "book")
            }
            .font(.headline).lineLimit(1)
            Text(app: "widget.okuma.dakika \(o?.todayMinutes ?? 0)").font(.caption)
            Text(app: "widget.okuma.seri \(o?.streak ?? 0)").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetAccentable()
    }

    /// The ring: khatm progress, the percentage in the middle.
    private func ringView(_ o: ReadingSnapshot?) -> some View {
        Gauge(value: Double(o?.khatmVerses ?? 0), in: 0...6236) {
            Image(systemName: "book")
        } currentValueLabel: {
            Text(verbatim: "\(Int((Double(o?.khatmVerses ?? 0) / 6236 * 100).rounded(.down)))")
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
    }
}

/// Seven bars for the minutes per weekday; the highest day fills the height, today in the accent color.
struct WeekBars: View {
    let minutes: [Int]
    let today: Int

    var body: some View {
        let maxCount = max(minutes.max() ?? 0, 1)
        GeometryReader { g in
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Array(minutes.enumerated()), id: \.offset) { i, d in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(i == today ? WidgetColor.accent : d > 0 ? WidgetColor.bar : WidgetColor.track)
                        .frame(height: max(4, g.size.height * CGFloat(d) / CGFloat(maxCount)))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

// MARK: - Günün ayeti: verse in Arabic and the translation

struct VerseEntry: TimelineEntry {
    let date: Date
    let verse: VerseSnapshot.DailyEntry?
}

/// One entry per day from the app's stock (two weeks).
struct VerseProvider: TimelineProvider {
    func placeholder(in context: Context) -> VerseEntry { VerseEntry(date: .now, verse: nil) }

    func getSnapshot(in context: Context, completion: @escaping (VerseEntry) -> Void) {
        completion(VerseEntry(date: .now, verse: VerseSnapshot.load()?.valid(time: .now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VerseEntry>) -> Void) {
        let now = Date.now
        let a = VerseSnapshot.load()
        let entries =
            [VerseEntry(date: now, verse: a?.valid(time: now))]
            + (a?.days.filter { $0.day > now }.map { VerseEntry(date: $0.day, verse: $0) } ?? [])
        completion(
            Timeline(entries: entries, policy: .after(entries.last.map { $0.date + 86400 } ?? now + 3600))
        )
    }
}

struct VerseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: VerseSnapshot.kind, provider: VerseProvider()) { g in
            VerseView(g: g)
                .containerBackground(for: .widget) { WidgetColor.background }
                .widgetURL(g.verse?.link ?? URL(string: "kiblegah://vakit"))
        }
        .configurationDisplayName(Text(app: "widget.ayet.ad"))
        .description(Text(app: "widget.ayet.aciklama"))
        .supportedFamilies([.systemMedium, .systemLarge, .systemExtraLarge, .accessoryRectangular])
    }
}

struct VerseView: View {
    let g: VerseEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let a = g.verse {
            if family == .systemLarge || family == .systemExtraLarge {
                PadVerseWidget(verse: a, extraLarge: family == .systemExtraLarge)
            } else if family == .accessoryRectangular {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: a.title).font(.caption.weight(.semibold))
                    Text(verbatim: a.translation).font(.caption).lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(app: "widget.ayet.ad")
                        Spacer()
                        Text(verbatim: a.title)
                    }
                    .font(WidgetColor.font(10, .bold)).tracking(0.8).textCase(.uppercase)
                    .foregroundStyle(WidgetColor.label)
                    Text(verbatim: a.arabic)
                        .font(.custom(Typography.arabicFontName, fixedSize: 21))
                        .foregroundStyle(WidgetColor.text)
                        .multilineTextAlignment(.trailing)
                        .environment(\.layoutDirection, .rightToLeft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(2).minimumScaleFactor(0.7)
                    Text(verbatim: a.translation)
                        .font(WidgetColor.font(13)).foregroundStyle(WidgetColor.text)
                        .lineLimit(3).minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(app: "widget.ayet.ad").font(WidgetColor.font(10, .bold)).textCase(.uppercase)
                    .foregroundStyle(WidgetColor.label)
                Text(app: "widget.ac").font(WidgetColor.font(13)).foregroundStyle(WidgetColor.text2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
