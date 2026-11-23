import PrayerTimes
import Testing

@testable import ContentPacks
@testable import Features

/// Wherever a single name is shown, ed-Dârr (91) comes with en-Nâfi‘ (92).
@MainActor struct DivineNamePairDisplayTests {
    static func names() -> [DivineName] {
        var names = (1...99).map {
            DivineName(
                number: $0, arabic: "a\($0)", latin: "l\($0)", transliterationTR: "o\($0)",
                meaningTR: "tr\($0)",
                meaningDE: "de\($0)", meaningEN: "en\($0)", source: nil)
        }
        PackRegistry.pairNames(&names)
        return names
    }

    @Test func darrIsShownAsPair() {
        let names = Self.names()
        let darr = names[90], nafi = names[91]
        #expect(darr.displayName == "\(darr.ownName) · \(nafi.ownName)")
        #expect(darr.displayMeaning == "\(darr.ownMeaning) · \(nafi.ownMeaning)")
        #expect(darr.displayArabic == "a91 a92")
        let note = darr.pairNote ?? ""
        #expect(note.contains(darr.ownName) && note.contains(nafi.ownName))
    }

    @Test func otherNamesStayAlone() {
        for e in Self.names() where e.number != 91 {
            #expect(e.displayName == e.ownName)
            #expect(e.displayMeaning == e.ownMeaning)
            #expect(e.displayArabic == e.arabic)
            #expect(e.pairNote == nil)
        }
    }

    @Test func nameOfTheDayOnDarrShowsThePair() throws {
        let names = Self.names()
        let g = Day(year: 2027, month: 1, day: 1)
        // The day on which the card lands on 91 shows the pair (displayName/displayArabic).
        let e = try #require(
            (0..<99).lazy.compactMap { DiscoverToday.divineName(names, day: g.added($0)) }.first {
                $0.number == 91
            })
        #expect(e.partner?.number == 92)
        #expect(e.displayName.contains(" · "))
    }
}
