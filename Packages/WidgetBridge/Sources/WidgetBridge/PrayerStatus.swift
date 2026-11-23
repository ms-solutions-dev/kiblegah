import Foundation

public struct PrayerStatus: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// Countdown to the next prayer or, in warning mode, to the start of the next Karahat window.
        case target
        /// Now is inside a Karahat window; it counts to the end.
        case karahat
        /// The first 45 seconds after a prayer time.
        case prayerTime
    }

    public enum Signal: Hashable, Sendable {
        case green, orange, red
    }

    /// Which Karahat window: after sunrise, before Öğle, before Akşam.
    public enum KarahatKind: String, Hashable, Sendable {
        case sunrise = "gunes", zawal = "zeval", maghrib = "aksam", other = "diger"
    }

    public let kind: Kind
    /// The name of the prayer (`target`, `prayerTime`); empty for Karahat, then `karahatKind` applies.
    public let name: String
    public let karahatKind: KarahatKind?
    /// The time of day after the title; for `.karahat` the end, for `.prayerTime` none.
    public let time: Date?
    /// The countdown runs until here.
    public let target: Date
    /// The bar runs from `start` to `end`.
    public let start: Date
    public let end: Date
    public let signal: Signal

    public init(
        kind: Kind, name: String, karahatKind: KarahatKind?, time: Date?, target: Date, start: Date,
        end: Date,
        signal: Signal
    ) {
        self.kind = kind
        self.name = name
        self.karahatKind = karahatKind
        self.time = time
        self.target = target
        self.start = start
        self.end = end
        self.signal = signal
    }

    // MARK: Values

    /// If a Karahat window begins in at most this much time and before the next prayer,
    /// the countdown counts to its start.
    public static let warnBefore: TimeInterval = 30 * 60
    /// Traffic light: more than 30 whole minutes green, up to 15 orange, below that red.
    public static let orangeMinutes = 30
    public static let redMinutes = 15
    /// For this long after a prayer time „... vakti“ is shown.
    public static let prayerDuration: TimeInterval = 45

    struct TimeWindow {
        let kind: KarahatKind
        let start: Date
        let end: Date
    }

    /// The Karahat windows of the snapshot with their kind, recognized by the adjacent time.
    static func windows(_ a: PrayerTimesSnapshot) -> [TimeWindow] {
        func yakin(_ d: Date, _ identifier: String) -> Bool {
            a.prayerTimes.contains { $0.identifier == identifier && abs($0.time.timeIntervalSince(d)) < 120 }
        }
        return a.karahatWindows.map { k in
            let kind: KarahatKind =
                yakin(k.start, "gunes")
                ? .sunrise : yakin(k.end, "ogle") ? .zawal : yakin(k.end, "aksam") ? .maghrib : .other
            return TimeWindow(kind: kind, start: k.start, end: k.end)
        }
        .sorted { $0.start < $1.start }
    }

    private static func boundaries(_ a: PrayerTimesSnapshot, _ p: [TimeWindow]) -> [Date] {
        (a.prayerTimes.map(\.time) + p.map(\.start) + p.map(\.end)).sorted()
    }

    /// The situation at `now`, or `nil` if no prayer is upcoming anymore: then the
    /// snapshot is used up, and guessing would be worse than showing nothing.
    public static func status(_ a: PrayerTimesSnapshot, now: Date) -> PrayerStatus? {
        let prayerTimes = a.prayerTimes
        guard let next = prayerTimes.first(where: { $0.time > now }) else { return nil }
        let p = windows(a)
        let axis = boundaries(a, p)
        let once = axis.last { $0 <= now } ?? now
        let after = axis.first { $0 > now } ?? next.time

        var d: PrayerStatus
        if let ic = p.first(where: { $0.start <= now && now < $0.end }) {
            d = PrayerStatus(
                kind: .karahat, name: "", karahatKind: ic.kind, time: ic.end, target: ic.end, start: ic.start,
                end: ic.end,
                signal: .red)
        } else {
            let nextKarahat = p.first { $0.start > now }
            var name = next.name
            var karahatKind: KarahatKind?
            var target = next.time
            if let k = nextKarahat, k.start.timeIntervalSince(now) <= warnBefore, k.start <= next.time {
                name = ""
                karahatKind = k.kind
                target = k.start
            }
            let critical = min(target, nextKarahat?.start ?? target)
            d = PrayerStatus(
                kind: .target, name: name, karahatKind: karahatKind, time: target, target: target,
                start: once,
                end: after,
                signal: signal(target: critical, now: now))
        }

        if let az = prayerTimes.last(where: { $0.time <= now && now < $0.time + prayerDuration }) {
            d = PrayerStatus(
                kind: .prayerTime, name: az.name, karahatKind: nil, time: nil, target: d.target,
                start: d.start, end: d.end,
                signal: .red)
        }
        return d
    }

    /// Whole minutes, truncated - like `crit` of the Windows widget.
    public static func signal(target: Date, now: Date) -> Signal {
        let minutes = Int(target.timeIntervalSince(now) / 60)
        if minutes > orangeMinutes { return .green }
        if minutes > redMinutes { return .orange }
        return .red
    }

    /// The points in time after `now` at which the situation can change; in between the
    /// countdown and bar count by themselves. The traffic light flips 30:59 or 15:59 before the target.
    public static func changes(_ a: PrayerTimesSnapshot, after now: Date) -> [Date] {
        let p = windows(a)
        let targets = a.prayerTimes.map(\.time) + p.map(\.start)
        var points = boundaries(a, p)
        points += a.prayerTimes.map { $0.time + prayerDuration }
        points += p.map { $0.start - warnBefore }
        points += targets.flatMap { h in
            [
                h - TimeInterval((orangeMinutes + 1) * 60 - 1),
                h - TimeInterval((redMinutes + 1) * 60 - 1),
            ]
        }
        return Set(points.filter { $0 > now }).sorted()
    }
}
