import Foundation

/// The verses of the day for the widget „Günün ayeti“ (): two weeks ahead, so that the
/// widget shows the right verse every day even without an app launch. Arabic and translation come
/// unchanged from the app's packages.
public struct VerseSnapshot: Codable, Sendable, Equatable {
    enum CodingKeys: String, CodingKey {
        case days = "gunler"
    }

    public struct DailyEntry: Codable, Sendable, Equatable {
        enum CodingKeys: String, CodingKey {
            case day = "gun"
            case title = "baslik"
            case arabic = "arapca"
            case translation = "meal"
            case source = "kaynak"
            case link
        }

        /// Start of the day from which this verse applies.
        public let day: Date
        /// „İnşirâh 6“
        public let title: String
        public let arabic: String
        public let translation: String
        /// Source of the translation, e.g. „Diyanet İşleri“.
        public let source: String
        public let link: URL?

        public init(day: Date, title: String, arabic: String, translation: String, source: String, link: URL?)
        {
            self.day = day
            self.title = title
            self.arabic = arabic
            self.translation = translation
            self.source = source
            self.link = link
        }
    }

    public let days: [DailyEntry]

    public init(days: [DailyEntry]) { self.days = days.sorted { $0.day < $1.day } }

    public static let fileName = "ayet.json"
    public static let kind = "gunun-ayeti"

    public static func file() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: PrayerTimesSnapshot.appGroup)?
            .appending(
                path: fileName)
    }

    public func save(_ url: URL? = VerseSnapshot.file()) {
        guard let url, let veri = try? JSONEncoder().encode(self) else { return }
        try? veri.write(to: url, options: .atomic)
    }

    public static func load(_ url: URL? = VerseSnapshot.file()) -> VerseSnapshot? {
        guard let url, let veri = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(VerseSnapshot.self, from: veri)
    }

    /// The verse that applies at `time`: the last one whose day has begun.
    public func valid(time: Date) -> DailyEntry? { days.last { $0.day <= time } }
}
