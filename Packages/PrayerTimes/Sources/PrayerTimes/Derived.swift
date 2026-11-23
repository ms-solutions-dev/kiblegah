import Core
import Foundation

/// A time window in which no prayer is performed.
public struct KarahatWindow: Hashable, Sendable {
    public enum Kind: String, Sendable {
        case atSunrise = "gunesDogarken", zawal = "zeval", atSunset = "gunesBatarken"
    }
    public let kind: Kind
    public let start: Date
    public let end: Date

    public func within(_ time: Date) -> Bool { time >= start && time < end }
}

/// What is derived from a table: Karahat, İşrak/Kuşluk, night thirds,
/// Cuma, Ramadan.
///
/// Karahat per the Diyanet fatwa, measured against the real sun position: Diyanet's
/// Güneş is 7 minutes before sunrise, Akşam 7 minutes after sunset (Temkin). So the window
/// in the morning only ends 7 + duration minutes after Güneş (default 45, adjustable)
/// and in the evening begins 7 + 45 minutes before Akşam; Zeval 10 minutes before Öğle - Din İşleri Yüksek
/// Kurulu, „Mekruh vakitler hangileridir?“: „Öğle vaktinin girmesine yaklaşık 10 dakika kalmasından
/// öğle vaktinin girmesine kadar“.
public struct DayTimeline: Sendable {
    public static let zawalMinutes = 10
    public static let maghribKarahatMinutes = 45
    /// Diyanet's Temkin for Güneş and Akşam.
    public static let temkinMinutes = 7

    public let today: DailyPrayerTimes
    public let tomorrow: DailyPrayerTimes?
    public let karahatMinutes: Int

    public init(today: DailyPrayerTimes, tomorrow: DailyPrayerTimes?, karahatMinutes: Int = 45) {
        self.today = today
        self.tomorrow = tomorrow
        self.karahatMinutes = karahatMinutes
    }

    public var karahatWindows: [KarahatWindow] {
        var l: [KarahatWindow] = []
        if karahatMinutes > 0 {
            l.append(
                .init(
                    kind: .atSunrise, start: today[.sunrise],
                    end: today[.sunrise] + dk(Self.temkinMinutes + karahatMinutes)))
        }
        l.append(.init(kind: .zawal, start: today[.dhuhr] - dk(Self.zawalMinutes), end: today[.dhuhr]))
        l.append(
            .init(
                kind: .atSunset, start: today[.maghrib] - dk(Self.temkinMinutes + Self.maghribKarahatMinutes),
                end: today[.maghrib]))
        return l
    }

    /// İşrak begins when the Karahat after sunrise ends.
    public var ishraq: Date { today[.sunrise] + dk(Self.temkinMinutes + max(karahatMinutes, 0)) }

    /// Kuşluk (Duhâ) extends until the start of the Zeval Karahat.
    public var duha: ClosedRange<Date> { ishraq...(today[.dhuhr] - dk(Self.zawalMinutes)) }

    /// Şer'î night: from Akşam until İmsak of the next day.
    public var midnight: Date? {
        night.map { $0.lowerBound + $0.upperBound.timeIntervalSince($0.lowerBound) / 2 }
    }

    /// Start of the last third of the night.
    public var lastThird: Date? {
        night.map { $0.lowerBound + $0.upperBound.timeIntervalSince($0.lowerBound) * 2 / 3 }
    }

    var night: Range<Date>? {
        guard let tomorrow else { return nil }
        return today[.maghrib]..<tomorrow[.imsak]
    }

    /// Friday: Öğle is called Cuma.
    public var isFriday: Bool { today.day.weekday == 6 }

    /// In Ramadan the home screen highlights İmsak and İftar.
    public var isRamadan: Bool { today.hijri?.month == 9 }

    /// The window that contains `time`, or `nil`.
    public func karahat(_ time: Date) -> KarahatWindow? { karahatWindows.first { $0.within(time) } }

    private func dk(_ n: Int) -> TimeInterval { TimeInterval(n * 60) }
}

/// Where we are in the day: the current and the next prayer time for the countdown.
public struct PrayerTimeStatus: Sendable, Hashable {
    /// The current prayer time (after Yatsı until midnight it is Yatsı, and after that until İmsak too).
    public let current: Prayer
    public let currentStart: Date
    public let next: Prayer
    public let nextTime: Date

    /// The situation at `time`, or `nil` if the table does not cover `time`.
    public init?(table: PrayerTimeTable, time: Date) {
        let tz = table.location.timeZone
        let today = Day(time, timeZoneIdentifier: tz)
        guard let g = table.day(today) else { return nil }
        let index = Prayer.allCases
        if let i = index.firstIndex(where: { g[$0] > time }) {
            next = index[i]
            nextTime = g[index[i]]
            if i > 0 {
                current = index[i - 1]
                currentStart = g[index[i - 1]]
            } else if let dun = table.day(today.added(-1)) {
                current = .isha
                currentStart = dun[.isha]
            } else {
                current = .isha
                currentStart = today.start(tz)
            }
        } else {
            guard let tomorrow = table.day(today.added(1)) else { return nil }
            current = .isha
            currentStart = g[.isha]
            next = .imsak
            nextTime = tomorrow[.imsak]
        }
    }

    /// Fraction of the current prayer time that has already elapsed (0...1), for the progress ring.
    public func progress(_ time: Date) -> Double {
        let total = nextTime.timeIntervalSince(currentStart)
        guard total > 0 else { return 0 }
        return min(1, max(0, time.timeIntervalSince(currentStart) / total))
    }
}

/// How urgent the current prayer is: The deadline ends at the next prayer time
/// or earlier if a Karahat begins before it (İkindi effectively ends 52 minutes before
/// Akşam). The home screen colors the card accordingly: rahat, az (≤ 30 minutes), kerahat.
public struct Urgency: Sendable, Equatable {
    public enum Level: Sendable, Equatable { case relaxed, az, karahat }

    public let level: Level
    /// Until when the current prayer stays free of Karahat; `nil` without a current prayer (after Güneş).
    public let lastDate: Date?
    /// The Karahat that sets the deadline or that we are currently in.
    public let karahat: KarahatWindow?

    public static let threshold: TimeInterval = 30 * 60

    public static func calculate(_ status: PrayerTimeStatus, timeline: DayTimeline, time: Date) -> Urgency {
        if let k = timeline.karahat(time) {
            return Urgency(level: .karahat, lastDate: nil, karahat: k)
        }
        guard status.current.isPrayer else { return Urgency(level: .relaxed, lastDate: nil, karahat: nil) }
        let k = timeline.karahatWindows.filter { $0.start > time && $0.start < status.nextTime }.min {
            $0.start < $1.start
        }
        let end = k?.start ?? status.nextTime
        return Urgency(
            level: end.timeIntervalSince(time) <= threshold ? .az : .relaxed, lastDate: end, karahat: k)
    }
}
