import ContentPacks
import Foundation
import Testing

@testable import Duas

/// True when `App/Resources/Paketler/kuran-text/manifest.json` exists (built by tools/content/fetch.sh).
let duaPacksAvailable = FileManager.default.fileExists(
    atPath: URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "App/Resources/Paketler/kuran-text/manifest.json").path(percentEncoded: false))

@Suite(.enabled(if: duaPacksAvailable, "content packs missing: run tools/content/fetch.sh"))
struct DuaContentTests {
    static let contentProvider: PackRegistry = {
        let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "App/Resources/Paketler")
        return try! PackRegistry(folders: [url])
    }()

    var contentProvider: PackRegistry { Self.contentProvider }

    @Test func rabbanaAtinaFromTheAddress() throws {
        let d = try #require(contentProvider.duas().first { $0.slug == "2-201" })
        let ar = DuaContent.arabic(d, contentProvider)
        #expect(ar.hasPrefix("رَبَّنَآ"))
        #expect(!ar.contains("يَقُولُ"))
        #expect(DuaContent.transliteration(d, contentProvider, language: "tr")?.hasPrefix("Rabbenâ") == true)
        #expect(DuaContent.translation(d, contentProvider, pack: "meal-tr-ozek")?.isEmpty == false)
    }

    @Test func duaVerseEndEndsEarlier() throws {
        let ibrahim = try #require(contentProvider.duas().first { $0.slug == "2-126" })
        let ar = DuaContent.arabic(ibrahim, contentProvider)
        #expect(ar.split(separator: " ").count == 15)
        #expect(!ar.contains("كَفَرَ"))
        let musa = try #require(contentProvider.duas().first { $0.slug == "28-16" })
        #expect(DuaContent.arabic(musa, contentProvider).split(separator: " ").count == 6)
        #expect(
            DuaContent.transliteration(musa, contentProvider, language: "tr")?.split(separator: " ").count
                == 6)
    }

    @Test func multipleVerses() throws {
        let d = try #require(contentProvider.duas().first { $0.slug == "20-25-28" })
        #expect(DuaContent.arabic(d, contentProvider).split(separator: " ").count > 8)
    }

    @Test func searchAndDailyDua() {
        let l = contentProvider.duas()
        #expect(
            !DuaContent.search("bağışla", l, contentProvider, pack: "meal-tr-ozek", language: "tr").isEmpty
        )
        #expect(
            DuaContent.search("xyzqq", l, contentProvider, pack: "meal-tr-ozek", language: "tr").isEmpty)
        #expect(
            DuaContent.search("bakara", l, contentProvider, pack: "meal-tr-ozek", language: "tr").contains
            {
                $0.slug == "2-201"
            })
        #expect(DuaContent.ofTheDay(l, day: .now) != nil)
    }
}

@Suite struct DhikrTests {
    @Test func tasbihatAdvances() {
        var s = DhikrCounter(index: Dhikr.tasbihat)
        for _ in 0..<32 { #expect(s.count() == .counted) }
        #expect(s.count() == .roundFinished)
        #expect(s.dhikr?.id == "elhamdulillah" && s.number == 0)
        for _ in 0..<66 { _ = s.count() }
        #expect(s.kind == 2 && s.dhikr?.id == "subhanallah")
    }

    @Test func undoAndReset() {
        var s = DhikrCounter(index: [Dhikr.others[0]])
        _ = s.count()
        _ = s.count()
        s.undo()
        #expect(s.number == 1)
        s.reset()
        #expect(s.number == 0 && s.kind == 1)
        var free = DhikrCounter(index: [])
        for _ in 0..<500 { _ = free.count() }
        #expect(free.number == 500 && free.withoutGoal)
    }
}

@Suite struct GuideTests {
    @Test func rakatTable() {
        let total = PrayerGuide.prayerTimes.map { $0.parts.reduce(0) { $0 + $1.rakat } }
        #expect(total == [4, 10, 8, 5, 13])
    }

    @Test func stepsFardAndSunnah() throws {
        let ogleF = try #require(PrayerGuide.prayerTimes[1].parts.first { $0.kind == .fard })
        let s = PrayerGuide.steps(ogleF)
        // Zamm-ı sûre only in rakat 1 and 2 of the fard.
        let additional = s.filter { $0.recitations.contains(PrayerGuide.additionalSurah) }.map(\.rakat)
        #expect(additional == [1, 2])
        #expect(s.last?.title.tr == "Selâm")
        #expect(s.filter { $0.title.tr == "Birinci oturuş" }.count == 1)
        let fajrSunnah = PrayerGuide.prayerTimes[0].parts[0]
        #expect(!PrayerGuide.steps(fajrSunnah).contains { $0.title.tr == "Birinci oturuş" })
        let witr = PrayerGuide.prayerTimes[4].parts[3]
        #expect(PrayerGuide.steps(witr).contains { $0.recitations.contains(PrayerGuide.qunut) })
        let asrSunnah = PrayerGuide.prayerTimes[2].parts[0]
        #expect(
            PrayerGuide.steps(asrSunnah).filter { $0.recitations.contains(PrayerGuide.subhanaka) }.map(
                \.rakat)
                == [1, 3])
    }
}
