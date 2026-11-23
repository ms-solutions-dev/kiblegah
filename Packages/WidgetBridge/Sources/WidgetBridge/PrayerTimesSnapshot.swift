import Foundation

/// The snapshot that the app writes for widgets, Live Activity and control.
///
/// Deliberately only Foundation types: the widget should work without the domain packages and load
/// quickly. Names of the prayers are already included translated, so the widget does not have to
/// look up a catalog.
public struct PrayerTimesSnapshot: Codable, Sendable, Equatable {
    enum CodingKeys: String, CodingKey {
        case location = "konum"
        case timeZoneIdentifier = "saatDilimi"
        case calculated = "hesaplanan"
        case prayerTimes = "vakitler"
        case karahatWindows = "kerahatler"
        case qiblaAngle = "kibleAcisi"
        case created = "olusturma"
        case latitude = "enlem"
        case longitude = "boylam"
    }

    public struct PrayerTime: Codable, Sendable, Equatable {
        enum CodingKeys: String, CodingKey {
            case identifier = "kimlik"
            case name = "ad"
            case time = "an"
            case prayer = "namaz"
        }

        public let identifier: String  // imsak, gunes, ogle, ikindi, aksam, yatsi
        public let name: String
        public let time: Date
        public let prayer: Bool

        public init(identifier: String, name: String, time: Date, prayer: Bool) {
            self.identifier = identifier
            self.name = name
            self.time = time
            self.prayer = prayer
        }
    }

    public struct Karahat: Codable, Sendable, Equatable {
        enum CodingKeys: String, CodingKey {
            case start = "bas"
            case end = "son"
        }

        public let start: Date
        public let end: Date

        public init(start: Date, end: Date) {
            self.start = start
            self.end = end
        }
    }

    public let location: String
    public let timeZoneIdentifier: String
    public let calculated: Bool
    /// All times of the next days, ascending.
    public let prayerTimes: [PrayerTime]
    public let karahatWindows: [Karahat]
    public let qiblaAngle: Double?
    public let created: Date
    /// Location for the sun position in the widget „Güneşe göre Kıble“; missing in old snapshots.
    public let latitude: Double?
    public let longitude: Double?

    public init(
        location: String, timeZoneIdentifier: String, calculated: Bool, prayerTimes: [PrayerTime],
        karahatWindows: [Karahat],
        qiblaAngle: Double?, created: Date, latitude: Double? = nil, longitude: Double? = nil
    ) {
        self.location = location
        self.timeZoneIdentifier = timeZoneIdentifier
        self.calculated = calculated
        self.prayerTimes = prayerTimes.sorted { $0.time < $1.time }
        self.karahatWindows = karahatWindows
        self.qiblaAngle = qiblaAngle
        self.created = created
        self.latitude = latitude
        self.longitude = longitude
    }

    public static let appGroup = "group.dev.ms-solutions.kiblegah"
    public static let fileName = "anlik.json"

    public static func file() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?.appending(
            path: fileName)
    }

    public func save(_ url: URL? = PrayerTimesSnapshot.file()) {
        guard let url, let veri = try? JSONEncoder().encode(self) else { return }
        try? veri.write(to: url, options: .atomic)
    }

    public static func load(_ url: URL? = PrayerTimesSnapshot.file()) -> PrayerTimesSnapshot? {
        guard let url, let veri = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PrayerTimesSnapshot.self, from: veri)
    }
}

/// A point in time of the widget timeline with everything the widget displays.
public struct WidgetEntry: Sendable, Equatable {
    public let date: Date
    /// The next prayer.
    public let next: PrayerTimesSnapshot.PrayerTime
    public let current: PrayerTimesSnapshot.PrayerTime?
    /// Current Karahat and its end.
    public let karahatEnd: Date?
    /// The next times from `next` (for the medium widget).
    public let upcoming: [PrayerTimesSnapshot.PrayerTime]
}

extension PrayerTimesSnapshot {
    /// The timeline from `now`: one entry at every boundary (prayer, Karahat start and end),
    /// precomputed instead of every 15 minutes. `nil` situation = stock used up.
    public func timeline(now: Date, time: TimeInterval = 36 * 3600) -> [WidgetEntry] {
        let end = now.addingTimeInterval(time)
        var boundaries = Set([now])
        for v in prayerTimes where v.time > now && v.time < end { boundaries.insert(v.time) }
        for k in karahatWindows {
            if k.start > now && k.start < end { boundaries.insert(k.start) }
            if k.end > now && k.end < end { boundaries.insert(k.end) }
        }
        return boundaries.sorted().compactMap { entry(time: $0) }
    }

    public func entry(time: Date) -> WidgetEntry? {
        guard let i = prayerTimes.firstIndex(where: { $0.time > time }) else { return nil }
        let current = i > 0 ? prayerTimes[i - 1] : nil
        let karahat = karahatWindows.first { $0.start <= time && time < $0.end }
        return WidgetEntry(
            date: time, next: prayerTimes[i], current: current, karahatEnd: karahat?.end,
            upcoming: Array(prayerTimes[i...].prefix(5)))
    }
}
