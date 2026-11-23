import Core
import Foundation
import Testing

@testable import ContentPacks

/// The question of the day against the real packs: what the data says is correct.
@Suite(.enabled(if: contentPacksAvailable, "content packs missing: run tools/content/fetch.sh"))
struct QuestionOfTheDayTests {
    var contentProvider: PackRegistry { ContentProviderTests.contentProvider }
    let verses: [ContentKey] = [
        .verse(surah: 94, verse: 5), .verse(surah: 13, verse: 28), .verse(surah: 2, verse: 286),
    ]

    func question(_ day: Int, language: String = "tr") -> QuestionOfTheDay? {
        QuestionGenerator.generate(
            dayNumber: day, surahs: contentProvider.surahs(), divineNames: contentProvider.divineNames(),
            verses: verses, language: language)
    }

    @Test func sameDaySameQuestion() {
        for g in [0, 20_744, 20_745, -3] {
            #expect(question(g) == question(g))
        }
        let week = Set((20_740..<20_750).compactMap { question($0)?.kind })
        #expect(week == Set(QuestionOfTheDay.Kind.allCases))
    }

    @Test(arguments: ["tr", "de", "en"]) func answersMatchTheData(language: String) throws {
        let surahs = Dictionary(uniqueKeysWithValues: contentProvider.surahs().map { ($0.number, $0) })
        let divineNames = Dictionary(
            uniqueKeysWithValues: contentProvider.divineNames().map { ($0.number, $0) })
        for g in 20_000..<20_400 {
            let s = try #require(question(g, language: language))
            #expect((3...4).contains(s.options.count))
            #expect(Set(s.options).count == s.options.count)
            #expect(s.options.indices.contains(s.correct))
            let d = s.options[s.correct]
            switch s.kind {
            case .verseSurah:
                guard case .verse(let a) = s.topic, case .verse(let number, _) = a else {
                    Issue.record("topic missing")
                    continue
                }
                #expect(verses.contains(a))
                #expect(d == .surah(number))
                #expect(s.source == .verse(a))
            case .verseCount:
                guard case .surah(let number) = s.topic, let surah = surahs[number] else {
                    Issue.record("topic missing")
                    continue
                }
                #expect(d == .number(surah.verseCount))
                #expect(s.source == .verse(.verse(surah: number, verse: surah.verseCount)))
            case .medinanSurah:
                let revelationPlace = s.options.compactMap { o -> Surah.RevelationPlace? in
                    if case .surah(let n) = o { return surahs[n]?.revelationPlace }
                    return nil
                }
                #expect(revelationPlace.filter { $0 == .medinan }.count == 1)
                for o in s.options {
                    if case .surah(let n) = o {
                        #expect(!QuestionGenerator.revelationPlaceDisputed.contains(n))
                    }
                }
                guard case .surah(let n) = d else { continue }
                #expect(surahs[n]?.revelationPlace == .medinan)
            case .firstRevealed:
                let index = s.options.compactMap { o -> Int? in
                    if case .surah(let n) = o { return surahs[n]?.revelationOrder }
                    return nil
                }
                guard case .surah(let n) = d else { continue }
                #expect(surahs[n]?.revelationOrder == index.min())
                #expect(Set(index).count == index.count)
            case .divineNameMeaning:
                guard case .divineName(let number) = s.topic else { continue }
                #expect(d == .divineName(number))
                #expect(number != 1)
                let meanings = s.options.compactMap { o -> String? in
                    if case .divineName(let n) = o {
                        return divineNames[n].flatMap { QuestionGenerator.meaning($0, language) }
                    }
                    return nil
                }
                #expect(meanings.count == s.options.count)
                #expect(Set(meanings).count == meanings.count)
            }
        }
    }

    @Test func withoutDivineNamesAndVerseFallsBack() {
        let s = QuestionGenerator.generate(
            dayNumber: 4, surahs: contentProvider.surahs(), divineNames: [], verses: [], language: "de")
        #expect(s != nil && s?.kind != .divineNameMeaning && s?.kind != .verseSurah)
        #expect(
            QuestionGenerator.generate(dayNumber: 4, surahs: [], divineNames: [], verses: [], language: "de")
                == nil)
    }

    @Test func shuffleStaysTheSame() {
        var a = SplitMix64(seed: 7)
        var b = SplitMix64(seed: 7)
        #expect(QuestionGenerator.shuffle(Array(1...20), &a) == QuestionGenerator.shuffle(Array(1...20), &b))
        var c = SplitMix64(seed: 7)
        #expect(Set(QuestionGenerator.shuffle(Array(1...20), &c)) == Set(1...20))
    }
}
