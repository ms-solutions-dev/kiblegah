import Foundation
import SwiftData
import Testing

@testable import UserData

@MainActor @Suite struct UserStoreTests {
    func defaults() throws -> UserStore {
        UserStore(container: try UserDataSchema.container(iCloud: false, inMemory: true))
    }

    @Test func noteWriteArchiveDelete() throws {
        let d = try defaults()
        d.saveNote("a:2:255", text: "Âyetü'l-Kürsî ezberle")
        #expect(d.note("a:2:255")?.metin == "Âyetü'l-Kürsî ezberle")
        d.saveNote("a:2:255", text: "güncel")
        #expect(d.notes().count == 1)
        d.archiveNote("a:2:255", true)
        #expect(d.notes(archived: false).isEmpty && d.notes(archived: true).count == 1)
        d.saveNote("a:2:255", text: "  ")
        #expect(d.note("a:2:255") == nil)
    }

    @Test func toggleEntry() throws {
        let d = try defaults()
        d.toggleSaved("a:36:1")
        #expect(d.isSaved("a:36:1"))
        d.toggleSaved("a:36:1")
        #expect(!d.isSaved("a:36:1"))
    }

    @Test func readingPositionAndKhatm() throws {
        let d = try defaults()
        d.saveLastPosition("a:1:4")
        d.saveLastPosition("a:2:10")
        #expect(d.lastPosition() == "a:2:10")
        d.addReading(firstIndex: 1, lastIndex: 7, seconds: 60)
        d.addReading(firstIndex: 5, lastIndex: 17, seconds: 60)
        d.addReading(firstIndex: 100, lastIndex: 110, seconds: 1)  // too short
        #expect(d.versesReadCount() == 17)
        #expect(d.thisWeekDays() == 1)
    }

    @Test func dhikrCount() throws {
        let d = try defaults()
        d.addDhikr("subhanallah", 33)
        d.addDhikr("elhamdulillah", 10)
        d.addDhikr("elhamdulillah", -1)
        d.addDhikr("x", -5)
        #expect(d.dhikrTotal(days: 1) == 42)
        let dun = Calendar.current.date(byAdding: .day, value: -3, to: .now)!
        d.addDhikr("subhanallah", 100, date: dun)
        #expect(d.dhikrTotal(days: 7) == 142)
        #expect(d.dhikrTotal(days: 1) == 42)
    }

    @Test func collections() throws {
        let d = try defaults()
        let a = d.createCollection("Sabır")
        let b = d.createCollection("Aile")
        d.toggleCollection("a:2:153", a)
        d.toggleCollection("a:2:153", b)
        d.toggleCollection("d:17-24", b)
        #expect(d.items(a) == ["a:2:153"])
        #expect(Set(d.items(b)) == ["a:2:153", "d:17-24"])
        #expect(d.contains("a:2:153", b))
        d.toggleCollection("a:2:153", b)
        #expect(!d.contains("a:2:153", b))
        d.renameCollection(a, "Sabır ayetleri")
        d.deleteCollection(b)
        #expect(d.collections().map(\.ad) == ["Sabır ayetleri"])
    }

    @Test func readingPositionsAndGoals() throws {
        let d = try defaults()
        let h = d.createKhatm("Ramazan", goal: ReadingGoal(kind: .verses, value: 20))
        d.addReading(firstIndex: 1, lastIndex: 7, seconds: 60, khatm: h.kimlik)
        d.addReading(firstIndex: 8, lastIndex: 20, seconds: 60)
        #expect(d.versesReadCount(khatm: h.kimlik) == 7)
        #expect(d.versesReadCount() == 13)
        #expect(d.khatms().map(\.ad) == ["Ramazan"])
        #expect(d.khatm(h.kimlik)?.goal == ReadingGoal(kind: .verses, value: 20))
        #expect(d.khatm("")?.goal == nil)  // Default khatm is created, without goal
        #expect(d.khatms().count == 1)
        d.deleteKhatm(h)
        #expect(d.khatms().isEmpty && d.sessions(khatm: h.kimlik).isEmpty)
    }

    @Test func weekStreakAndDailyGoal() throws {
        var t = Calendar(identifier: .gregorian)
        t.timeZone = TimeZone(identifier: "Europe/Berlin")!
        t.firstWeekday = 2
        let d = try defaults()
        let mi = t.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 12))!  // Wednesday
        let day = { (n: Int) in t.date(byAdding: .day, value: n, to: mi)! }
        d.addReading(firstIndex: 1, lastIndex: 30, seconds: 600, date: day(-2))  // Mon: goal reached
        d.addReading(firstIndex: 31, lastIndex: 35, seconds: 60, date: day(-1))  // Tue: partial
        let o = d.sessions()
        let week = ReadingStats.week(
            o, goal: ReadingGoal(kind: .verses, value: 20), readCount: 35, pageStarts: [1, 8, 30], now: mi,
            calendar: t)
        #expect(week.map(\.status) == [.done, .partial, .empty, .upcoming, .upcoming, .upcoming, .upcoming])
        #expect(ReadingStats.streak(o, now: mi, calendar: t) == 2)  // still open today, streak holds
        #expect(ReadingStats.streak(o, now: day(1), calendar: t) == 0)
        let oz = ReadingStats.summary(o, day: day(-2), pageStarts: [1, 8, 30], calendar: t)
        #expect(oz == ReadingStats.DaySummary(verse: 30, page: 3, seconds: 600))
        // 6236 − 35 verses in 10 days (today included) → 621 per day
        let h = ReadingGoal(kind: .finishDate, value: 0, end: day(9))
        #expect(ReadingStats.dailyGoal(h, readCount: 35, now: mi, calendar: t) == 621)
    }

    @Test func memorizationPlan() throws {
        var y = MemorizationScheduler.next(interval: 0, ease: 2.5, repetition: 0, score: .good)
        #expect(y.interval == 1 && y.repetition == 1)
        y = MemorizationScheduler.next(
            interval: y.interval, ease: y.ease, repetition: y.repetition, score: .good)
        #expect(y.interval == 3)
        y = MemorizationScheduler.next(
            interval: y.interval, ease: y.ease, repetition: y.repetition, score: .good)
        #expect(y.interval == 8)  // 3 × 2.5 rounded
        let z = MemorizationScheduler.next(interval: 8, ease: 2.5, repetition: 3, score: .zor)
        #expect(z.interval == 1 && z.repetition == 0 && z.ease == 2.3)
        let d = try defaults()
        d.addToMemorization("a:67:1-5")
        d.addToMemorization("a:67:1-5")
        #expect(d.memorizationCards().count == 1)
        let k = try #require(d.memorizationCards().first)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        d.rateMemorization(k, .kolay, now: now)
        #expect(k.sonraki == now.addingTimeInterval(4 * 86400))
        #expect(!MemorizationScheduler.isDue(k.sonraki, now: now))
    }

    @Test func merged() {
        #expect(ReadingStats.merged([1...3, 4...5, 10...10]) == 6)
        #expect(ReadingStats.merged([]) == 0)
    }

    @Test func persistentAfterRestart() throws {
        let folderURL = FileManager.default.temporaryDirectory.appending(path: "nd \(UUID())")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let url = folderURL.appending(path: "t.store")
        do {
            let k = try ModelContainerHelper.container(url)
            let d = UserStore(container: k)
            d.saveNote("a:1:1", text: "bleibt")
        }
        let d2 = UserStore(container: try ModelContainerHelper.container(url))
        #expect(d2.note("a:1:1")?.metin == "bleibt")
    }
}

enum ModelContainerHelper {
    static func container(_ url: URL) throws -> ModelContainer {
        let s = Schema(UserDataSchema.models)
        return try ModelContainer(for: s, configurations: ModelConfiguration(schema: s, url: url))
    }
}
