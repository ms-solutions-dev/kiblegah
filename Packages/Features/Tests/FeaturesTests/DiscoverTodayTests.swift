import Foundation
import PrayerTimes
import Testing

@testable import Features

@MainActor @Suite struct DiscoverTodayTests {
    /// Same day, same entry; the next day the next one, cycling through all 99.
    @Test func divineNameTiedToDay() throws {
        let g = Day(year: 2026, month: 10, day: 18)
        let a = try #require(DiscoverToday.index(99, day: g))
        #expect(DiscoverToday.index(99, day: g) == a)
        #expect(DiscoverToday.index(99, day: g.added(1)) == (a + 1) % 99)
        #expect(Set((0..<99).compactMap { DiscoverToday.index(99, day: g.added($0)) }).count == 99)
        #expect(DiscoverToday.index(0, day: g) == nil)
    }

    /// The next dini gün counts today and returns the days until then.
    @Test func nextReligiousDay() throws {
        let today = Day(year: 2026, month: 10, day: 18)
        let l = ReligiousDay.calculate(year: 2026) + ReligiousDay.calculate(year: 2027)
        let s = try #require(DiscoverToday.next(l, today: today))
        #expect(s.day.day >= today)
        #expect(!l.contains { $0.day >= today && $0.day < s.day.day })
        #expect(today.added(s.remaining) == s.day.day)
        let same = try #require(DiscoverToday.next(l, today: s.day.day))
        #expect(same.remaining == 0)
    }

    /// Every top-level hadith category has a symbol and color, unknown ones have none.
    @Test func hadithCategoryView() {
        #expect((1...7).allSatisfy { HadithScreen.appearance($0) != nil })
        #expect(HadithScreen.appearance(99) == nil)
    }

    @Test func guideInBacklog() {
        #expect(!Backlog.prayerGuide)
    }
}
