import Core
import Foundation

/// The six times of the Diyanet table in their order.
public enum Prayer: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable, Hashable {
    case imsak, sunrise = "gunes", dhuhr = "ogle", asr = "ikindi", maghrib = "aksam", isha = "yatsi"

    /// Güneş is a time marker, not a prayer.
    public var isPrayer: Bool { self != .sunrise }
}

/// A calendar day without time of day, stored as `2026-10-18`.
public struct Day: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init?(text: String) {
        let p = text.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, (1...12).contains(p[1]), (1...31).contains(p[2]) else { return nil }
        self.init(year: p[0], month: p[1], day: p[2])
    }

    /// The day in which `time` lies in `timeZoneIdentifier`.
    public init(_ time: Date, timeZoneIdentifier: TimeZone) {
        var t = Calendar(identifier: .gregorian)
        t.timeZone = timeZoneIdentifier
        let c = t.dateComponents([.year, .month, .day], from: time)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    /// Midnight of this day in `timeZoneIdentifier`.
    public func start(_ timeZoneIdentifier: TimeZone) -> Date {
        var t = Calendar(identifier: .gregorian)
        t.timeZone = timeZoneIdentifier
        return t.date(from: DateComponents(year: year, month: month, day: day))!
    }

    public func added(_ dayCount: Int) -> Day {
        var t = Calendar(identifier: .gregorian)
        t.timeZone = .gmt
        let d = t.date(byAdding: .day, value: dayCount, to: start(.gmt))!
        return Day(d, timeZoneIdentifier: .gmt)
    }

    /// 1 = Sunday … 7 = Saturday (like `Calendar`).
    public var weekday: Int {
        var t = Calendar(identifier: .gregorian)
        t.timeZone = .gmt
        return t.component(.weekday, from: start(.gmt))
    }

    public static func < (a: Day, b: Day) -> Bool { (a.year, a.month, a.day) < (b.year, b.month, b.day) }

    public init(from decoder: Decoder) throws {
        let k = try decoder.singleValueContainer()
        let m = try k.decode(String.self)
        guard let g = Day(text: m) else {
            throw DecodingError.dataCorruptedError(in: k, debugDescription: "Kein Tag: \(m)")
        }
        self = g
    }

    public func encode(to encoder: Encoder) throws {
        var k = encoder.singleValueContainer()
        try k.encode(description)
    }
}

/// Where a table comes from. The home screen shows it.
public enum PrayerTimeSourceKind: String, Codable, Sendable {
    /// Diyanet via our own server - „wie in der Moschee“.
    case diyanet
    /// Computed on the device (fallback, when traveling): „hesaplanan“.
    case calculated = "hesaplanan"
}

/// A day of the table.
public struct DailyPrayerTimes: Codable, Sendable, Hashable {
    enum CodingKeys: String, CodingKey {
        case day = "gun"
        case times = "saatler"
        case hijri = "hicri"
        case source = "kaynak"
    }

    public let day: Day
    public let times: [Prayer: Date]
    /// Hijri date as delivered by Diyanet („7 Cemaziyelevvel 1448“), otherwise computed.
    public let hijri: HijriDate?
    /// Per day, because a stock can mix Diyanet days and computed follow-on days.
    public let source: PrayerTimeSourceKind

    public init(day: Day, times: [Prayer: Date], hijri: HijriDate?, source: PrayerTimeSourceKind) {
        self.day = day
        self.times = times
        self.hijri = hijri
        self.source = source
    }

    public subscript(_ n: Prayer) -> Date { times[n] ?? .distantPast }
}

/// The table of a place: a stock of days including source and state.
public struct PrayerTimeTable: Codable, Sendable, Hashable {
    enum CodingKeys: String, CodingKey {
        case location = "konum"
        case fetchedAt = "alinma"
        case days = "gunler"
    }

    public let location: Location
    /// When the table was last fetched or computed.
    public let fetchedAt: Date
    public let days: [DailyPrayerTimes]

    public init(location: Location, fetchedAt: Date, days: [DailyPrayerTimes]) {
        self.location = location
        self.fetchedAt = fetchedAt
        self.days = days.sorted { $0.day < $1.day }
    }

    /// The source of the most recent fetch: Diyanet as soon as a day comes from there.
    public var source: PrayerTimeSourceKind {
        days.contains { $0.source == .diyanet } ? .diyanet : .calculated
    }

    /// Appends computed days where the Diyanet days end - a computed
    /// day never replaces a Diyanet day.
    public func complete(_ yeni: PrayerTimeTable, today: Day) -> PrayerTimeTable {
        let old = days.filter { $0.day >= today.added(-1) }
        let end = old.last?.day
        let ek = yeni.days.filter { g in end.map { g.day > $0 } ?? true }
        return PrayerTimeTable(location: location, fetchedAt: yeni.fetchedAt, days: old + ek)
    }

    public func day(_ g: Day) -> DailyPrayerTimes? { days.first { $0.day == g } }

    /// The last day in the stock.
    public var lastDay: Day? { days.last?.day }

    /// How many days from `today` are still covered (today included).
    public func daysRemaining(today: Day) -> Int { days.filter { $0.day >= today }.count }
}
