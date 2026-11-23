import Foundation

/// Reading position for the widget „Kur'an okuma“ (), written by the app when switching to the
/// background. Numbers only, no domain types: the widget recalculates nothing, it only advances
/// „heute“ and „diese Woche“ when a new day begins without the app having run.
public struct ReadingSnapshot: Codable, Sendable, Equatable {
    enum CodingKeys: String, CodingKey {
        case day = "gun"
        case todayVerses = "bugunAyet"
        case todayMinutes = "bugunDakika"
        case weekStart = "haftaBasi"
        case weekMinutes = "haftaDakika"
        case weekVerses = "haftaAyet"
        case streak = "seri"
        case khatmVerses = "hatimAyet"
        case lastPosition = "kaldiginYer"
        case link
        case goal = "hedef"
    }

    /// The day for which `today...` applies (start of the day).
    public let day: Date
    public let todayVerses: Int
    public let todayMinutes: Int
    /// Start of the calendar week and minutes per day (7 values, from the start of the week).
    public let weekStart: Date
    public let weekMinutes: [Int]
    public let weekVerses: Int
    /// Consecutive reading days up to today (or up to yesterday if nothing has been read today yet).
    public let streak: Int
    /// Verses read of the active reading position, out of 6236.
    public let khatmVerses: Int
    /// „Bakara 255“ - where to continue; the link opens the reader there.
    public let lastPosition: String?
    public let link: URL?
    /// Daily goal of the active reading position, if set (watch complication F,).
    public let goal: Goal?

    /// Done today (`actual`) of `target`, in the unit of the goal (verses, pages or minutes).
    public struct Goal: Codable, Sendable, Equatable {
        enum CodingKeys: String, CodingKey {
            case kind = "tur"
            case actual = "ist"
            case target = "ziel"
        }

        public let kind: String
        public let actual: Int
        public let target: Int

        public init(kind: String, actual: Int, target: Int) {
            self.kind = kind
            self.actual = actual
            self.target = target
        }
    }

    public init(
        day: Date, todayVerses: Int, todayMinutes: Int, weekStart: Date, weekMinutes: [Int], weekVerses: Int,
        streak: Int, khatmVerses: Int, lastPosition: String?, link: URL?, goal: Goal? = nil
    ) {
        self.day = day
        self.todayVerses = todayVerses
        self.todayMinutes = todayMinutes
        self.weekStart = weekStart
        self.weekMinutes = weekMinutes
        self.weekVerses = weekVerses
        self.streak = streak
        self.khatmVerses = khatmVerses
        self.lastPosition = lastPosition
        self.link = link
        self.goal = goal
    }

    public static let fileName = "okuma.json"
    public static let kind = "kuran-okuma"

    public static func file() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: PrayerTimesSnapshot.appGroup)?
            .appending(
                path: fileName)
    }

    public func save(_ url: URL? = ReadingSnapshot.file()) {
        guard let url, let veri = try? JSONEncoder().encode(self) else { return }
        try? veri.write(to: url, options: .atomic)
    }

    public static func load(_ url: URL? = ReadingSnapshot.file()) -> ReadingSnapshot? {
        guard let url, let veri = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ReadingSnapshot.self, from: veri)
    }

    /// The state on the day of `time`: on a later day "today" is 0, in a later
    /// week the week too; the streak only holds if something was read yesterday.
    public func valid(time: Date, calendar: Calendar = .current) -> ReadingSnapshot {
        let today = calendar.startOfDay(for: time)
        guard today > day else { return self }
        let newWeek = calendar.dateInterval(of: .weekOfYear, for: time).map { $0.start > weekStart } ?? false
        let dun = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let seriKalir = day == dun && todayVerses + todayMinutes > 0
        return ReadingSnapshot(
            day: today, todayVerses: 0, todayMinutes: 0,
            weekStart: newWeek ? calendar.dateInterval(of: .weekOfYear, for: time)!.start : weekStart,
            weekMinutes: newWeek ? Array(repeating: 0, count: 7) : weekMinutes,
            weekVerses: newWeek ? 0 : weekVerses, streak: seriKalir ? streak : 0, khatmVerses: khatmVerses,
            lastPosition: lastPosition, link: link,
            goal: goal.map { Goal(kind: $0.kind, actual: 0, target: $0.target) })
    }
}
