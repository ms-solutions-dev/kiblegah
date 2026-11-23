import Foundation
import SwiftData
import Testing

@testable import UserData

@MainActor @Suite struct DailyPointsTests {
    var calendar: Calendar {
        var t = Calendar(identifier: .gregorian)
        t.timeZone = TimeZone(identifier: "Europe/Berlin")!
        t.firstWeekday = 2
        return t
    }

    func date(_ g: Int, _ time: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: g, hour: time))!
    }

    @Test func streakCountsEveryPoint() {
        let n = DailyCalculation.points(
            reading: ["2026-10-14", "2026-10-15"], dhikr: ["2026-10-16"],
            question: ["2026-10-17", "2026-10-18"],
            now: date(18), calendar: calendar)
        #expect(n.streak == 5)
        #expect(!n.verse && !n.dhikr && n.question && n.done == 1)
        #expect(n.week == [false, false, true, true, true, true, true])
    }

    @Test func todayOpenCountsUntilYesterday() {
        let n = DailyCalculation.points(
            reading: ["2026-10-16", "2026-10-17"], dhikr: [], question: [], now: date(18), calendar: calendar)
        #expect(n.streak == 2 && n.done == 0)
        let gap = DailyCalculation.points(
            reading: ["2026-10-15"], dhikr: [], question: [], now: date(18), calendar: calendar)
        #expect(gap.streak == 0)
    }

    @Test func storeReadsAllThreeSources() throws {
        let d = UserStore(container: try UserDataSchema.container(iCloud: false, inMemory: true))
        let currentTime = Date.now
        d.addReading(firstIndex: 1, lastIndex: 7, seconds: 90, date: currentTime)
        d.addReading(firstIndex: 5, lastIndex: 10, seconds: 30, date: currentTime, khatm: "ikinci")
        d.addDhikr("subhanallah", 33, date: currentTime)
        let day = UserStore.dayText(currentTime, .current)
        d.answerQuestion(day: day, selection: 2, correct: true)
        d.answerQuestion(day: day, selection: 0, correct: false)
        #expect(d.questionAnswer(day: day)?.secim == 2)
        let n = d.dailyPoints(now: currentTime)
        #expect(n.verse && n.dhikr && n.question && n.streak == 1)
        let h = d.weeklyReading(now: currentTime)
        #expect(h == WeeklyReading(verse: 10, minutes: 2, day: 1))
    }

    @Test func dhikrZeroDoesNotCount() throws {
        let d = UserStore(container: try UserDataSchema.container(iCloud: false, inMemory: true))
        d.addDhikr("x", 1)
        d.addDhikr("x", -1)
        #expect(!d.dailyPoints().dhikr)
    }
}

@Suite struct ReadingSummaryTests {
    @Test func todayWeekStreak() {
        var t = Calendar(identifier: .gregorian)
        t.timeZone = TimeZone(identifier: "Europe/Berlin")!
        t.firstWeekday = 2
        let now = t.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 20))!  // Wednesday
        func tag(_ d: Int) -> Date { t.date(from: DateComponents(year: 2026, month: 10, day: d, hour: 9))! }
        let o = [
            OkumaOturumu(ilkSira: 1, sonSira: 7, saniye: 120, tarih: tag(21)),
            OkumaOturumu(ilkSira: 8, sonSira: 10, saniye: 60, tarih: tag(20)),
            OkumaOturumu(ilkSira: 11, sonSira: 11, saniye: 30, tarih: tag(19)),
            OkumaOturumu(ilkSira: 12, sonSira: 12, saniye: 30, tarih: tag(17)),
        ]
        let z = DailyCalculation.readingSummary(o, now: now, calendar: t)
        #expect(z.todayVerses == 7 && z.todayMinutes == 2)
        #expect(z.weekMinutes == [1, 1, 2, 0, 0, 0, 0] && z.weekVerses == 11)
        #expect(z.streak == 3)
        // Nothing yet today: the streak counts up to yesterday.
        #expect(DailyCalculation.readingSummary(Array(o.dropFirst()), now: now, calendar: t).streak == 2)
    }
}
