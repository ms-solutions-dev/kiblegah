import Core
import Foundation

/// Builds quiz questions from the ``QuizPool``.
///
/// A question depends only on kind, subject and seed: `gen:<kind>:<key>:<seed>`. From that it
/// is rebuilt identically on every device; the question itself is never stored, only its identifier.
public struct QuizGenerator: Sendable {
    public let pool: QuizPool

    public init(pool: QuizPool) { self.pool = pool }

    /// The question for an identifier, or `nil` if it cannot be built with these packs.
    public func question(identifier: String) -> QuizQuestion? {
        guard let p = QuizID.parse(identifier) else { return nil }
        return question(p.kind, key: p.key, seed: p.seed)
    }

    /// A question on a random subject of level `level`; `excluding` excludes subjects (no repetition
    /// in a round). With `seen` only unseen (`fresh`) or the longest-unseen; without history
    /// (``QuizSeen/empty``) chance decides as before.
    func question(
        _ kind: QuizQuestionKind, level: Int, excluding: Set<String>, seen: QuizSeen = .empty,
        fresh: Bool = true,
        rng z: inout SplitMix64
    ) -> QuizQuestion? {
        let all = pool.topics(kind).filter { $0.level == level && !excluding.contains($0.key) }
        let candidates = seen.pick(all, fresh: fresh) { "\(kind.rawValue):\($0.key)" }
        guard !candidates.isEmpty else { return nil }
        for _ in 0..<6 {
            let k = candidates[z.pick(candidates.count)]
            let seed = z.next() % 1_000_000
            if let s = question(kind, key: k.key, seed: seed),
                QuizRules.violations(s, pool: pool).isEmpty
            {
                return s
            }
        }
        return nil
    }

    /// The question for kind, subject and seed.
    public func question(_ kind: QuizQuestionKind, key: String, seed: UInt64) -> QuizQuestion? {
        guard let topic = pool.topics(kind).first(where: { $0.key == key }) else { return nil }
        var z = SplitMix64(seed: seed &* 0x2545_F491_4F6C_DD1D &+ UInt64(kind.rawValue.stableHashValue))
        let identifier = QuizID.gen(kind, key, seed)
        let a = ContentKey(text: key)
        switch (kind, a) {
        case (.translationSurah, .verse(let s, _)?):
            guard let surah = pool.surahByNumber[s] else { return nil }
            // Surahs of similar length (in Juz 30: only Juz 30 surahs), so that length gives nothing away.
            let candidate = pool.surahs.filter { $0.number != s && (s < 78 || $0.number >= 78) }
                .sorted {
                    (abs($0.verseCount - surah.verseCount), $0.number) < (
                        abs($1.verseCount - surah.verseCount), $1.number
                    )
                }
                .prefix(8).map(\.number)
            let wrong = QuestionGenerator.shuffle(Array(candidate), &z).prefix(3).map { QuizOption.surah($0) }
            return bundle(
                identifier, kind, topic.level, .verse(a!), correct: .surah(s), wrong: wrong,
                source: .verse(a!), &z)
        case (.verseCount, .surah(let s)?):
            guard let surah = pool.surahByNumber[s] else { return nil }
            let values = Set(pool.surahs.map(\.verseCount)).filter {
                abs($0 - surah.verseCount) >= QuizRules.numberRange
            }
            // Easy: any real values; hard: the nearest ones (concept: "answer options close together").
            let ordered =
                topic.level >= 3
                ? values.sorted {
                    (abs($0 - surah.verseCount), $0) < (abs($1 - surah.verseCount), $1)
                }
                : QuestionGenerator.shuffle(values.sorted(), &z)
            let wrong = Self.spaced(ordered, correct: surah.verseCount, count: 3).map {
                QuizOption.number($0)
            }
            return bundle(
                identifier, kind, topic.level, .surah(s), correct: .number(surah.verseCount), wrong: wrong,
                source: .verse(.verse(surah: s, verse: surah.verseCount)), &z)
        case (.surahJuz, .surah(let s)?):
            guard let c = pool.singleJuz[s] else { return nil }
            let allNumbers = (1...30).filter { abs($0 - c) >= QuizRules.numberRange }
            let ordered =
                topic.level >= 3
                ? QuestionGenerator.shuffle(allNumbers.filter { abs($0 - c) <= 8 }, &z)
                : QuestionGenerator.shuffle(allNumbers, &z)
            let wrong = Self.spaced(ordered, correct: c, count: 3).map { QuizOption.juz($0) }
            return bundle(
                identifier, kind, topic.level, .surah(s), correct: .juz(c), wrong: wrong,
                source: .verse(.verse(surah: s, verse: 1)), &z)
        case (.medinanSurah, .surah(let s)?), (.meccanSurah, .surah(let s)?):
            let sought: Surah.RevelationPlace = kind == .medinanSurah ? .meccan : .medinan
            let other = pool.surahs.filter {
                $0.revelationPlace == sought && !QuestionGenerator.revelationPlaceDisputed.contains($0.number)
            }
            let wrong = QuestionGenerator.shuffle(other.map(\.number), &z).prefix(3).map {
                QuizOption.surah($0)
            }
            return bundle(
                identifier, kind, topic.level, .noTopic, correct: .surah(s), wrong: Array(wrong),
                source: .verse(.verse(surah: s, verse: 1)), &z)
        case (.firstRevealed, .surah(let s)?):
            guard let d = pool.surahByNumber[s] else { return nil }
            var selected: [Surah] = [d]
            for x in QuestionGenerator.shuffle(pool.surahs, &z)
            where x.revelationOrder > d.revelationOrder
                && !selected.contains(where: {
                    abs($0.revelationOrder - x.revelationOrder) < QuizRules.revelationRange
                })
            {
                selected.append(x)
                if selected.count == 4 { break }
            }
            return bundle(
                identifier, kind, topic.level, .noTopic, correct: .surah(s),
                wrong: selected.dropFirst().map { .surah($0.number) },
                source: .verse(.verse(surah: s, verse: 1)),
                &z)
        case (.wordGap, .word(let s, let n, _)?):
            guard let words = pool.verseWords[.verse(surah: s, verse: n)],
                let k = words.first(where: { $0.key == a })
            else { return nil }
            let scalarCount = k.skeleton.unicodeScalars.count
            var seenItems: Set<String> = [k.skeleton]
            var wrong: [QuizOption] = []
            // Real words from Juz 30 of similar length; never an invented word.
            let candidates = pool.wordPool.filter { abs($0.skeleton.unicodeScalars.count - scalarCount) <= 2 }
            for d in QuestionGenerator.shuffle(candidates, &z) where seenItems.insert(d.skeleton).inserted {
                wrong.append(.word(d.key))
                if wrong.count == 3 { break }
            }
            return bundle(
                identifier, kind, topic.level, .word(k.key), correct: .word(k.key), wrong: wrong,
                source: .verse(.verse(surah: s, verse: n)), &z, format: .wordTiles)
        case (.divineNameMeaning, .divineName(let number)?), (.meaningDivineName, .divineName(let number)?):
            let band = QuizPool.divineNameBand(number)
            var wrong: [Int] = []
            let candidates =
                QuestionGenerator.shuffle(pool.divineNames.filter { band.contains($0.number) }, &z)
                + QuestionGenerator.shuffle(pool.divineNames.filter { !band.contains($0.number) }, &z)
            for e in candidates
            where !([number] + wrong).contains(where: {
                QuizRules.divineNameOverlaps($0, e.number, divineNames: pool.divineNameNumber)
            }) {
                wrong.append(e.number)
                if wrong.count == 3 { break }
            }
            let option: (Int) -> QuizOption =
                kind == .divineNameMeaning ? { .divineNameMeaning($0) } : { .divineNameLabel($0) }
            return bundle(
                identifier, kind, topic.level, .divineName(number), correct: option(number),
                wrong: wrong.map(option),
                source: .divineName(number), &z)
        case (.hadithCollection, .hadith(_, let number)?):
            guard let d = pool.hadiths[number]?.collection else { return nil }
            let forbidden = QuizRules.excludedCollections(d)
            let other = HadithCollection.allCases.filter { $0 != d && !forbidden.contains($0) }
            let wrong = QuestionGenerator.shuffle(other, &z).prefix(3).map { QuizOption.collection($0) }
            return bundle(
                identifier, kind, topic.level, .hadith(number), correct: .collection(d), wrong: Array(wrong),
                source: .hadith(number), &z)
        case (.hadithCategory, .hadith(_, let number)?):
            guard let d = pool.hadiths[number]?.topCategory else { return nil }
            let other = pool.hadithTopCategories.filter { $0 != d }
            let wrong = QuestionGenerator.shuffle(other, &z).prefix(3).map { QuizOption.hadithCategory($0) }
            return bundle(
                identifier, kind, topic.level, .hadith(number), correct: .hadithCategory(d),
                wrong: Array(wrong),
                source: .hadith(number), &z)
        case (.duaCategory, .dua(let slug)?):
            guard let d = pool.duas.first(where: { $0.slug == slug }) else { return nil }
            return bundle(
                identifier, kind, topic.level, .dua(slug), correct: .duaCategory(d.category),
                wrong: QuizRules.duaDistractors(d).map { .duaCategory($0) }, source: .dua(slug), &z)
        case (.duaSurah, .dua(let slug)?):
            guard let d = pool.duas.first(where: { $0.slug == slug }) else { return nil }
            let skeleton = pool.duaSkeleton[slug]
            // Other surahs with Quran duas, but none in which the same wording appears again.
            let same = Set(pool.duas.filter { pool.duaSkeleton[$0.slug] == skeleton }.map(\.surah))
            let other = Array(Set(pool.duas.map(\.surah)).subtracting(same)).sorted()
            let wrong = QuestionGenerator.shuffle(other, &z).prefix(3).map { QuizOption.surah($0) }
            return bundle(
                identifier, kind, topic.level, .dua(slug), correct: .surah(d.surah), wrong: Array(wrong),
                source: .dua(slug), &z)
        default:
            return nil
        }
    }

    /// Takes numbers from `ordered` in order that keep the minimum distance to each other and to the correct one.
    static func spaced(_ ordered: [Int], correct: Int, count: Int) -> [Int] {
        var selected: [Int] = []
        for d in ordered
        where !([correct] + selected).contains(where: { abs($0 - d) < QuizRules.numberRange }) {
            selected.append(d)
            if selected.count == count { break }
        }
        return selected
    }

    private func bundle(
        _ identifier: String, _ kind: QuizQuestionKind, _ level: Int, _ topic: QuizTopic, correct: QuizOption,
        wrong: [QuizOption], source: QuizSource, _ z: inout SplitMix64, format: QuizFormat = .fourOptions
    ) -> QuizQuestion? {
        guard wrong.count >= 2, !wrong.contains(correct), Set(wrong).count == wrong.count else {
            return nil
        }
        let all = QuestionGenerator.shuffle([correct] + wrong, &z)
        guard let i = all.firstIndex(of: correct) else { return nil }
        return QuizQuestion(
            identifier: identifier, area: kind.area, kind: kind, format: format, level: level, topic: topic,
            options: all, correct: i, source: source)
    }
}
