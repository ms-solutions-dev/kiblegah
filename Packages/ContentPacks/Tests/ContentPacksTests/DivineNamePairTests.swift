import Testing

@testable import ContentPacks

/// ed-Dârr (91) is never shown or asked alone, only together with en-Nâfi‘ (92).
@Suite struct DivineNamePairTests {
    /// 99 names with distinct meanings, without a content pack.
    static func names() -> [DivineName] {
        (1...99).map {
            DivineName(
                number: $0, arabic: "a\($0)", latin: "l\($0)", transliterationTR: "o\($0)",
                meaningTR: "tr\($0)",
                meaningDE: "de\($0)", meaningEN: "en\($0)", source: nil)
        }
    }

    @Test func onlyDarrGetsNafiAsPartner() {
        var names = Self.names()
        PackRegistry.pairNames(&names)
        #expect(names[90].partner?.number == 92)
        #expect(names.filter { $0.partner != nil }.map(\.number) == [91])
        #expect(DivineName.namedWithPartner == [91: 92])
    }

    @Test func questionOfTheDayNeverAsksOrOffersDarr() {
        var names = Self.names()
        PackRegistry.pairNames(&names)
        // The surah table only has to be there; the divine-name question does not use it.
        let surahs = (1...4).map {
            Surah(
                number: $0, verseCount: 5, firstIndex: $0 * 5, nameArabic: "", nameTurkish: "", nameLatin: "",
                meaningEnglish: "", revelationPlace: .meccan, revelationOrder: $0, basmala: true)
        }
        for seed in 0..<2_000 {
            var z = SplitMix64(seed: UInt64(seed))
            let q = QuestionGenerator.question(
                .divineNameMeaning, rng: &z, surahs: surahs, divineNames: names, verses: [], language: "tr")
            #expect(q != nil)
            #expect(q?.topic != .divineName(91))
            #expect(!(q?.options.contains(.divineName(91)) ?? true))
        }
    }
}
