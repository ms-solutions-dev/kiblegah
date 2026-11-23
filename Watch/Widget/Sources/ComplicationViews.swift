import SwiftUI
import WidgetKit
import WidgetBridge

// The views of the watch complications. Shared by the widget extension and, for the README
// screenshots, by the watch app (DEBUG `-saatEkran komplikasyon`, see ComplicationGallery.swift),
// so that the screenshots show exactly these views with the real snapshot.

struct WatchEntry: TimelineEntry {
    let date: Date
    let snapshot: PrayerTimesSnapshot?
    let status: PrayerStatus?
}

extension PrayerStatus.Signal {
    /// System colors: on the watch the watch face usually tints by itself (accent mode).
    var color: Color {
        switch self {
        case .green: .green
        case .orange: .orange
        case .red: .red
        }
    }
}

extension PrayerStatus {
    /// „Yatsı“ or, during Karahat, „Kerahat“.
    var shortName: String { kind == .karahat ? String(localized: "widget.sayac.marka.kerahat") : name }
}

func timeText(_ t: Date, _ a: PrayerTimesSnapshot?) -> String {
    t.clockText(in: a.flatMap { TimeZone(identifier: $0.timeZoneIdentifier) } ?? .current)
}

struct PrayerTimeComplicationView: View {
    @Environment(\.widgetFamily) private var widgetFamily
    let g: WatchEntry
    /// Outside a watch face (screenshot gallery of the watch app) the size class is passed in here.
    var family: WidgetFamily?

    var body: some View {
        if let d = g.status {
            switch family ?? widgetFamily {
            case .accessoryCircular: ringView(d)
            case .accessoryCorner: corner(d)
            default: rectangular(d)
            }
        } else {
            Image(systemName: "iphone.and.arrow.forward").widgetAccentable()
        }
    }

    /// A: ring up to the next prayer, name and remaining time inside.
    private func ringView(_ d: PrayerStatus) -> some View {
        Gauge(value: g.date.timeIntervalSince(d.start), in: 0...max(1, d.end.timeIntervalSince(d.start))) {
            Text(verbatim: "")
        } currentValueLabel: {
            VStack(spacing: -1) {
                Text(verbatim: d.shortName).font(.system(size: 9, weight: .bold)).textCase(.uppercase)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(d.target, style: .timer).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.5)
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(d.signal.color)
        .widgetAccentable()
    }

    /// B: name · time of day, countdown, bar.
    private func rectangular(_ d: PrayerStatus) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Circle().fill(d.signal.color).frame(width: 6, height: 6)
                Text(verbatim: d.shortName).font(.headline).lineLimit(1)
                if let s = d.time {
                    Text(verbatim: "· " + timeText(s, g.snapshot)).font(.headline).foregroundStyle(.secondary)
                }
            }
            Text(d.target, style: .timer).font(.title3.weight(.semibold)).monospacedDigit()
            ProgressView(timerInterval: d.start...max(d.start, d.end), countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(d.signal.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetAccentable()
    }

    /// C: arc in the corner, name and time of day next to it.
    private func corner(_ d: PrayerStatus) -> some View {
        Text(verbatim: d.shortName)
            .font(.system(size: 13, weight: .semibold))
            .widgetCurvesContent()
            .widgetLabel {
                Gauge(value: g.date.timeIntervalSince(d.start), in: 0...max(1, d.end.timeIntervalSince(d.start)))
                {
                    Text(verbatim: "")
                } currentValueLabel: {
                    EmptyView()
                } minimumValueLabel: {
                    Text(verbatim: "")
                } maximumValueLabel: {
                    Text(verbatim: d.time.map { timeText($0, g.snapshot) } ?? "")
                }
                .tint(d.signal.color)
            }
    }
}

struct DayScheduleView: View {
    let g: WatchEntry

    var body: some View {
        if let a = g.snapshot, let d = g.status, let day = Self.day(a, time: g.date) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    // With a 12-hour clock „Dhuhr 12:21 PM“ and the countdown do not fit side by side:
                    // then the name alone, never a cut-off time.
                    ViewThatFits(in: .horizontal) {
                        Text(verbatim: d.shortName + (d.time.map { " " + timeText($0, a) } ?? ""))
                        Text(verbatim: d.shortName)
                    }
                    .font(.headline).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(d.target, style: .timer).font(.headline).monospacedDigit().foregroundStyle(
                        d.signal.color
                    )
                    .lineLimit(1).frame(maxWidth: 64, alignment: .trailing)
                }
                line(a, day)
            }
            .widgetAccentable()
        } else {
            Text("widget.ac").font(.footnote)
        }
    }

    /// The day from İmsak to the next İmsak (or 24 h).
    static func day(_ a: PrayerTimesSnapshot, time: Date) -> ClosedRange<Date>? {
        let imsakTimes = a.prayerTimes.filter { $0.identifier == "imsak" }.map(\.time)
        guard let start = imsakTimes.last(where: { $0 <= time }) ?? imsakTimes.first else { return nil }
        let end = imsakTimes.first(where: { $0 > start }) ?? start + 24 * 3600
        return start...end
    }

    private func line(_ a: PrayerTimesSnapshot, _ day: ClosedRange<Date>) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let total = day.upperBound.timeIntervalSince(day.lowerBound)
            let x = { (t: Date) -> CGFloat in CGFloat(t.timeIntervalSince(day.lowerBound) / total) * w }
            ZStack(alignment: .leading) {
                Capsule().fill(.secondary.opacity(0.35)).frame(height: 3)
                Capsule().fill(.secondary).frame(width: max(0, min(w, x(g.date))), height: 3)
                ForEach(a.karahatWindows.filter { $0.end > day.lowerBound && $0.start < day.upperBound }, id: \.start)
                { k in
                    Rectangle().fill(.red.opacity(0.75))
                        .frame(
                            width: max(3, x(min(k.end, day.upperBound)) - x(max(k.start, day.lowerBound))),
                            height: 7
                        )
                        .offset(x: x(max(k.start, day.lowerBound)))
                }
                ForEach(a.prayerTimes.filter { day.contains($0.time) }, id: \.time) { v in
                    Circle().fill(.primary).frame(width: 5, height: 5).offset(x: x(v.time) - 2.5)
                }
                Circle().fill(g.status?.signal.color ?? .green).frame(width: 9, height: 9)
                    .overlay(Circle().stroke(.black, lineWidth: 1.5))
                    .offset(x: min(w, x(g.date)) - 4.5)
            }
            .frame(height: 12)
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }
}

/// Fixed direction from north: watch faces do not redraw continuously, the rotating
/// compass stays in the app - a tap opens it.
struct QiblaComplicationView: View {
    let snapshot: PrayerTimesSnapshot?

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let k = snapshot?.qiblaAngle {
                Text(verbatim: "N").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                    .offset(y: -18)
                Image(systemName: "location.north.fill").font(.system(size: 15))
                    .rotationEffect(.degrees(k)).widgetAccentable()
                Text(verbatim: "\(Int(k.rounded()))°").font(.system(size: 10, weight: .semibold))
                    .offset(y: 16)
            } else {
                Image(systemName: "location.north.line").widgetAccentable()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("saat.kible"))
        .accessibilityValue(
            snapshot?.qiblaAngle.map { Text(verbatim: "\(Int($0.rounded()))°") } ?? Text(verbatim: ""))
    }
}

/// Read today against the daily goal; without a goal, today's verses with a full ring from the first one.
struct ReadingComplicationView: View {
    let o: ReadingSnapshot?

    var body: some View {
        let actual = o?.goal?.actual ?? o?.todayVerses ?? 0
        let target = max(1, o?.goal?.target ?? max(1, actual))
        Gauge(value: Double(min(actual, target)), in: 0...Double(target)) {
            Image(systemName: "book.closed")
        } currentValueLabel: {
            VStack(spacing: -1) {
                Image(systemName: actual >= target && o?.goal != nil ? "checkmark" : "book.closed")
                    .font(.system(size: 10, weight: .semibold))
                Text(verbatim: o?.goal == nil ? "\(actual)" : "\(actual)/\(target)")
                    .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.5)
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(.orange)
        .widgetAccentable()
    }
}
