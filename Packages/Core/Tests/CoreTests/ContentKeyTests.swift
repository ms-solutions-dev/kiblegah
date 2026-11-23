import Foundation
import Testing

@testable import Core

@Suite struct ContentKeyTests {
    @Test(arguments: [
        "s:36", "a:2:255", "a:2:8-9", "w:1:5:2", "p:604", "j:30", "d:evden-cikarken", "e:99",
        "h:buhari:1", "k:sabir",
    ])
    func roundTrip(_ text: String) throws {
        let a = try #require(ContentKey(text: text))
        #expect(a.text == text)
    }

    @Test(arguments: ["", "x:1", "a:2", "a:0:1", "a:2:9-8", "j:31", "e:100", "w:1:2", "d:", "s:abc"])
    func invalid(_ text: String) {
        #expect(ContentKey(text: text) == nil)
    }

    @Test func singleVerseRangeBecomesVerse() {
        #expect(ContentKey(text: "a:2:5-5") == .verse(surah: 2, verse: 5))
    }

    @Test func rangeCovers() throws {
        let a = try #require(ContentKey(text: "a:2:8-9"))
        #expect(a.covers(surah: 2, verse: 8))
        #expect(a.covers(surah: 2, verse: 9))
        #expect(!a.covers(surah: 2, verse: 10))
        #expect(!a.covers(surah: 3, verse: 8))
    }

    @Test func codableWrittenAsText() throws {
        let veri = try JSONEncoder().encode([ContentKey.verse(surah: 1, verse: 4)])
        #expect(String(decoding: veri, as: UTF8.self) == #"["a:1:4"]"#)
        #expect(try JSONDecoder().decode([ContentKey].self, from: veri) == [.verse(surah: 1, verse: 4)])
    }
}

@Suite struct TurkishTextTests {
    @Test func uppercasedDottedI() {
        #expect(TurkishText.uppercased("istanbul") == "İSTANBUL")
        #expect(TurkishText.lowercased("IŞIK") == "ışık")
    }

    @Test func searchFormFolds() {
        #expect(TurkishText.searchForm("Sabır") == TurkishText.searchForm("sabir"))
        #expect(TurkishText.searchForm("Âyete'l-Kürsî") == "ayete l kursi")
        #expect(TurkishText.searchForm("ILIK") == "ilik")
    }
}

@Suite struct AppTabTests {
    @Test func normalizedFourUnique() {
        #expect(AppTab.normalized([.dhikr, .dhikr, .discover]) == [.dhikr, .prayerTimes, .qibla, .quran])
        #expect(AppTab.normalized([]) == AppTab.standard)
    }
}
