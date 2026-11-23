import Foundation
import SwiftData

/// The three daily points of the „Bugün“ start page and the streak above them.
///
/// Everything comes from existing events (reading history, dhikr counter, answer to the question
/// of the day); there is no separate counter that could drift apart.
public struct DailyPoints: Sendable, Equatable {
    public var verse = false
    public var dhikr = false
    public var question = false
    /// Consecutive days with at least one point; today only counts once there is something today.
    public var streak = 0
    /// The last seven days, oldest first, today last: whether there was a point.
    public var week: [Bool] = []

    public init(
        verse: Bool = false, dhikr: Bool = false, question: Bool = false, streak: Int = 0, week: [Bool] = []
    ) {
        self.verse = verse
        self.dhikr = dhikr
        self.question = question
        self.streak = streak
        self.week = week
    }

    public var done: Int { [verse, dhikr, question].filter { $0 }.count }
}

/// Reading this week, counted positively (Cockpit /): verses, minutes, days.
public struct WeeklyReading: Sendable, Equatable {
    /// Distinct verses read in this calendar week.
    public var verse = 0
    public var minutes = 0
    public var day = 0

    public init(verse: Int = 0, minutes: Int = 0, day: Int = 0) {
        self.verse = verse
        self.minutes = minutes
        self.day = day
    }
}

public enum DailyCalculation {
    /// Points and streak from the days (`yyyy-MM-dd`) on which there was something for each point.
    public static func points(
        reading: Set<String>, dhikr: Set<String>, question: Set<String>, now: Date = .now,
        calendar: Calendar = .current
    ) -> DailyPoints {
        let today = UserStore.dayText(now, calendar)
        let anyActivity = reading.union(dhikr).union(question)
        let day0 = calendar.startOfDay(for: now)
        func text(_ rest: Int) -> String {
            UserStore.dayText(calendar.date(byAdding: .day, value: -rest, to: day0) ?? day0, calendar)
        }
        var rest = anyActivity.contains(today) ? 0 : 1
        var streak = 0
        while anyActivity.contains(text(rest)) {
            streak += 1
            rest += 1
        }
        return DailyPoints(
            verse: reading.contains(today), dhikr: dhikr.contains(today), question: question.contains(today),
            streak: streak,
            week: (0..<7).reversed().map { anyActivity.contains(text($0)) })
    }

    /// Reading in the calendar week of `now`, across all reading positions.
    public static func week(
        _ sessions: [OkumaOturumu], now: Date = .now, calendar: Calendar = .current
    ) -> WeeklyReading {
        guard let w = calendar.dateInterval(of: .weekOfYear, for: now) else { return WeeklyReading() }
        let o = sessions.filter { w.contains($0.tarih) }
        return WeeklyReading(
            verse: ReadingStats.merged(o.map { $0.ilkSira...$0.sonSira }),
            minutes: Int((o.reduce(0) { $0 + $1.saniye } / 60).rounded()),
            day: Set(o.map { calendar.startOfDay(for: $0.tarih) }).count)
    }
}

extension UserStore {
    /// The daily points up to `now`; looks back at most a good year.
    public func dailyPoints(now: Date = .now, calendar: Calendar = .current) -> DailyPoints {
        let first = calendar.date(byAdding: .day, value: -400, to: now) ?? now
        let limit = Self.dayText(first, calendar)
        let reading =
            (try? container.mainContext.fetch(
                FetchDescriptor<OkumaOturumu>(predicate: #Predicate { $0.tarih >= first }))) ?? []
        let dhikr =
            (try? container.mainContext.fetch(
                FetchDescriptor<ZikirGunu>(predicate: #Predicate { $0.gun >= limit && $0.adet > 0 }))) ?? []
        let question =
            (try? container.mainContext.fetch(
                FetchDescriptor<SoruCevabi>(predicate: #Predicate { $0.gun >= limit }))) ?? []
        return DailyCalculation.points(
            reading: Set(reading.map { Self.dayText($0.tarih, calendar) }), dhikr: Set(dhikr.map(\.gun)),
            question: Set(question.filter(\.isQuestionOfTheDay).map(\.gun)), now: now, calendar: calendar)
    }

    /// Reading this week across all reading positions.
    public func weeklyReading(now: Date = .now, calendar: Calendar = .current) -> WeeklyReading {
        let first = calendar.date(byAdding: .day, value: -8, to: now) ?? now
        let o =
            (try? container.mainContext.fetch(
                FetchDescriptor<OkumaOturumu>(predicate: #Predicate { $0.tarih >= first }))) ?? []
        return DailyCalculation.week(o, now: now, calendar: calendar)
    }
}

/// Reading figures for the „Kur'an okuma“ widget (): today, minutes per weekday, streak.
public struct ReadingSummary: Sendable, Equatable {
    public var todayVerses = 0
    public var todayMinutes = 0
    public var weekStart = Date.distantPast
    /// Minutes per day from the start of the week, seven values.
    public var weekMinutes: [Int] = Array(repeating: 0, count: 7)
    public var weekVerses = 0
    /// Reading days in a row up to today, or up to yesterday if nothing has been read today yet.
    public var streak = 0
}

extension DailyCalculation {
    public static func readingSummary(
        _ sessions: [OkumaOturumu], now: Date = .now, calendar: Calendar = .current
    ) -> ReadingSummary {
        var o = ReadingSummary()
        let today = calendar.startOfDay(for: now)
        let b = sessions.filter { calendar.isDate($0.tarih, inSameDayAs: now) }
        o.todayVerses = ReadingStats.merged(b.map { $0.ilkSira...$0.sonSira })
        o.todayMinutes = Int((b.reduce(0) { $0 + $1.saniye } / 60).rounded())
        if let w = calendar.dateInterval(of: .weekOfYear, for: now) {
            o.weekStart = w.start
            let h = sessions.filter { w.contains($0.tarih) }
            o.weekVerses = ReadingStats.merged(h.map { $0.ilkSira...$0.sonSira })
            o.weekMinutes = (0..<7).map { i in
                guard let g = calendar.date(byAdding: .day, value: i, to: w.start) else { return 0 }
                let s = h.filter { calendar.isDate($0.tarih, inSameDayAs: g) }.reduce(0) { $0 + $1.saniye }
                return Int((s / 60).rounded())
            }
        }
        let days = Set(sessions.map { calendar.startOfDay(for: $0.tarih) })
        var g = days.contains(today) ? today : calendar.date(byAdding: .day, value: -1, to: today) ?? today
        while days.contains(g) {
            o.streak += 1
            g = calendar.date(byAdding: .day, value: -1, to: g) ?? g
        }
        return o
    }
}

extension UserStore {
    /// Reading figures across all reading positions; looks back at most a good year (for the streak).
    public func readingSummary(now: Date = .now, calendar: Calendar = .current) -> ReadingSummary {
        let first = calendar.date(byAdding: .day, value: -400, to: now) ?? now
        let o =
            (try? container.mainContext.fetch(
                FetchDescriptor<OkumaOturumu>(predicate: #Predicate { $0.tarih >= first }))) ?? []
        return DailyCalculation.readingSummary(o, now: now, calendar: calendar)
    }
}
