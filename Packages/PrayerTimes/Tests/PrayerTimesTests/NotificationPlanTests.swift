import Core
import Foundation
import Testing

@testable import PrayerTimes

@Suite struct NotificationPlanTests {
    func table(_ day: Int = 35) async throws -> PrayerTimeTable {
        try await OnDeviceSource().table(
            location: .sample, start: Day(year: 2026, month: 10, day: 18), dayCount: day)
    }

    @Test func limitAndWholeDays() async throws {
        let t = try await table()
        let now = t.days[0][.imsak] - 60
        let tum = Dictionary(
            uniqueKeysWithValues: Prayer.allCases.map {
                ($0, NotificationSetting(atTime: true, minutesBefore: 15))
            })
        let s = NotificationPlan.schedule(table: t, settings: tum, now: now)
        #expect(s.notifications.count <= NotificationPlan.limit)
        #expect(s.notifications.contains { $0.kind == .reminder })
        // 12 notifications per day → 5 whole days in 63 slots.
        #expect(s.lastDay == Day(year: 2026, month: 10, day: 22))
        let tz = Location.sample.timeZone
        let lastDayOnes = s.notifications.filter {
            $0.kind != .reminder && Day($0.time, timeZoneIdentifier: tz) == s.lastDay
        }
        #expect(lastDayOnes.count == 12)
        #expect(Set(s.notifications.map(\.identifier)).count == s.notifications.count)
    }

    @Test func defaultFivePrayers() async throws {
        let t = try await table()
        let s = NotificationPlan.schedule(table: t, settings: [:], now: t.days[0][.imsak] - 60)
        let ilkGun = s.notifications.filter {
            Day($0.time, timeZoneIdentifier: Location.sample.timeZone) == t.days[0].day
        }
        #expect(ilkGun.count == 5)
        #expect(!ilkGun.contains { $0.prayer == .sunrise })
        // 5 per day → 12 whole days.
        #expect(s.lastDay == Day(year: 2026, month: 10, day: 29))
    }

    /// Done-when AP5: ten days, rescheduling once every day (app start) - no notification is missing.
    @Test func tenDaysWithoutLoss() async throws {
        let t = try await table(40)
        let setting = Dictionary(
            uniqueKeysWithValues: Prayer.allCases.map {
                ($0, NotificationSetting(atTime: true, minutesBefore: 30))
            })
        var fired = Set<String>()
        var pending: [ScheduledNotification] = []
        var now = t.days[0][.imsak] - 3600
        let end = now + 10 * 86400
        while now < end {
            // Random start time of the day: rescheduling replaces everything pending.
            pending = NotificationPlan.schedule(table: t, settings: setting, now: now).notifications
            let morgen = now + 86400
            for b in pending where b.time <= morgen && b.kind != .reminder { fired.insert(b.identifier) }
            now = morgen
        }
        let tz = Location.sample.timeZone
        let expected = NotificationPlan.schedule(
            table: t, settings: setting, now: t.days[0][.imsak] - 3600, limit: 10_000
        )
        .notifications.filter { $0.kind != .reminder && $0.time < end }
        #expect(Set(expected.map(\.identifier)).isSubset(of: fired))
        #expect(
            !expected.isEmpty
                && Day(expected.last!.time, timeZoneIdentifier: tz) >= Day(year: 2026, month: 10, day: 27))
    }

    @Test func withoutOpeningTheStockLastsUntilTheReminder() async throws {
        let t = try await table()
        let s = NotificationPlan.schedule(table: t, settings: [:], now: t.days[0][.imsak] - 60)
        let h = try #require(s.notifications.first { $0.kind == .reminder })
        #expect(Day(h.time, timeZoneIdentifier: Location.sample.timeZone) == s.lastDay!.added(-2))
    }

    /// Karahat reminder: 15 minutes before each of the three windows, with the window.
    @Test func beforeKarahat() async throws {
        let t = try await table()
        let now = t.days[0][.imsak] - 60
        let s = NotificationPlan.schedule(table: t, settings: [:], now: now, karahatBefore: 15)
        let tz = Location.sample.timeZone
        let first = s.notifications.filter {
            $0.kind == .karahat && Day($0.time, timeZoneIdentifier: tz) == t.days[0].day
        }
        #expect(first.count == 3)
        let timeline = DayTimeline(today: t.days[0], tomorrow: nil)
        for b in first {
            let k = try #require(b.karahat)
            #expect(timeline.karahatWindows.contains(k))
            #expect(b.time == k.start - 15 * 60)
        }
        // 8 per day → fewer days, but still only whole ones.
        #expect(s.notifications.count <= NotificationPlan.limit)
        #expect(
            NotificationPlan.schedule(table: t, settings: [:], now: now).notifications.allSatisfy {
                $0.kind != .karahat
            })
    }
}
