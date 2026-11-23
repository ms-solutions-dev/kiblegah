import Core
import Foundation

/// The question of the day (Cockpit ): one question, three to four answers, with a citation.
///
/// There is no question catalog: every question is generated from the shipped data (surah table
/// from Tanzil, Esma package, translation verses) so that nothing religious is freely worded. The
/// UI assembles the texts in the app language; only numbers are held here.
public struct QuestionOfTheDay: Sendable, Hashable {
    public enum Kind: String, Sendable, CaseIterable {
        /// "Which surah is this verse in?" – the translation of the verse is shown.
        case verseSurah = "ayetSuresi"
        /// „Wie viele Ayet hat Sure Y?“
        case verseCount = "ayetSayisi"
        /// "Which of these surahs is Medinan?" – one Medinan, three Meccan.
        case medinanSurah = "medeniSure"
        /// „Welche dieser Suren wurde zuerst offenbart?“ – revelation order from Tanzil.
        case firstRevealed = "ilkNazil"
        /// „Was bedeutet der Name Z?“
        case divineNameMeaning = "esmaAnlami"
    }

    /// What the question refers to.
    public enum Topic: Sendable, Hashable {
        case verse(ContentKey)
        case surah(Int)
        case divineName(Int)
        case noTopic
    }

    /// An answer; the text comes from the same data in the UI.
    public enum Option: Sendable, Hashable {
        case surah(Int)
        case number(Int)
        case divineName(Int)
    }

    /// The citation the UI links after the answer.
    public enum Source: Sendable, Hashable {
        case verse(ContentKey)
        case divineName(Int)
    }

    public let kind: Kind
    public let topic: Topic
    public let options: [Option]
    /// Index of the correct answer in `options`.
    public let correct: Int
    public let source: Source
}

/// Generates the question of a day, the same for all users.
///
/// The selection depends only on the day number (days since 1970), a dedicated random generator
/// and dedicated shuffling – not on `SystemRandomNumberGenerator` or the shuffle algorithm of the
/// standard library, which may change between Swift versions.
public enum QuestionGenerator {
    /// Surahs whose Meccan/Medinan classification is disputed among scholars (Tanzil and Diyanet differ
    /// on Ra'd, Rahmân, İnsân, Felak, Nâs, among others). The daily question omits them so that nobody
    /// gets a „falsch“ for a defensible answer.
    public static let revelationPlaceDisputed: Set<Int> = [
        13, 22, 47, 55, 61, 64, 76, 83, 97, 98, 99, 113, 114,
    ]

    /// - Parameters:
    ///   - gunNo: days since 1970-01-01 (the calendar day, not the time).
    ///   - ayetler: candidates for "Which surah is this verse in?" (short, verified verses).
    ///   - dil: app language; Esma meanings must be distinct in it.
    public static func generate(
        dayNumber: Int, surahs: [Surah], divineNames: [DivineName], verses: [ContentKey], language: String
    ) -> QuestionOfTheDay? {
        let kinds = QuestionOfTheDay.Kind.allCases
        let first = ((dayNumber % kinds.count) + kinds.count) % kinds.count
        for i in 0..<kinds.count {
            var z = SplitMix64(seed: UInt64(bitPattern: Int64(dayNumber)) &* 0x9E37_79B9 &+ UInt64(i))
            let kind = kinds[(first + i) % kinds.count]
            if let s = question(
                kind, rng: &z, surahs: surahs, divineNames: divineNames, verses: verses, language: language)
            {
                return s
            }
        }
        return nil
    }

    static func question(
        _ kind: QuestionOfTheDay.Kind, rng z: inout SplitMix64, surahs: [Surah], divineNames: [DivineName],
        verses: [ContentKey],
        language: String
    ) -> QuestionOfTheDay? {
        guard surahs.count >= 4 else { return nil }
        switch kind {
        case .verseSurah:
            let candidates = verses.filter {
                if case .verse(let s, _) = $0 { return surahs.contains { $0.number == s } }
                return false
            }
            guard !candidates.isEmpty else { return nil }
            let a = candidates[z.pick(candidates.count)]
            guard case .verse(let s, _) = a else { return nil }
            let other = shuffle(surahs.map(\.number).filter { $0 != s }, &z).prefix(3)
            return bundle(
                .verseSurah, topic: .verse(a), correct: .surah(s), wrong: other.map { .surah($0) },
                source: .verse(a), rng: &z)
        case .verseCount:
            let surah = surahs[z.pick(surahs.count)]
            var seenItems: Set<Int> = [surah.verseCount]
            var wrong: [Int] = []
            for d in shuffle(surahs.map(\.verseCount), &z) where !seenItems.contains(d) {
                seenItems.insert(d)
                wrong.append(d)
                if wrong.count == 3 { break }
            }
            guard wrong.count == 3 else { return nil }
            return bundle(
                .verseCount, topic: .surah(surah.number), correct: .number(surah.verseCount),
                wrong: wrong.map { .number($0) },
                source: .verse(.verse(surah: surah.number, verse: surah.verseCount)), rng: &z)
        case .medinanSurah:
            let medinan = surahs.filter {
                $0.revelationPlace == .medinan && !Self.revelationPlaceDisputed.contains($0.number)
            }
            let meccan = surahs.filter {
                $0.revelationPlace == .meccan && !Self.revelationPlaceDisputed.contains($0.number)
            }
            guard !medinan.isEmpty, meccan.count >= 3 else { return nil }
            let d = medinan[z.pick(medinan.count)]
            let wrong = shuffle(meccan.map(\.number), &z).prefix(3)
            return bundle(
                .medinanSurah, topic: .noTopic, correct: .surah(d.number), wrong: wrong.map { .surah($0) },
                source: .verse(.verse(surah: d.number, verse: 1)), rng: &z)
        case .firstRevealed:
            var selected: [Surah] = []
            // The revelation order is transmission, not consensus: only surahs at least 20 places
            // apart, so that a defensible answer does not count as „falsch“.
            for s in shuffle(surahs, &z)
            where !selected.contains(where: { abs($0.revelationOrder - s.revelationOrder) < 20 }) {
                selected.append(s)
                if selected.count == 4 { break }
            }
            guard selected.count == 4, let d = selected.min(by: { $0.revelationOrder < $1.revelationOrder })
            else {
                return nil
            }
            return bundle(
                .firstRevealed, topic: .noTopic, correct: .surah(d.number),
                wrong: selected.filter { $0.number != d.number }.map { .surah($0.number) },
                source: .verse(.verse(surah: d.number, verse: 1)), rng: &z)
        case .divineNameMeaning:
            // Without ed-Dârr: it is never asked or offered alone (DivineName.namedWithPartner).
            let candidates = divineNames.filter {
                $0.number != 1 && DivineName.namedWithPartner[$0.number] == nil
                    && !(meaning($0, language) ?? "").isEmpty
            }
            guard candidates.count >= 4 else { return nil }
            let e = candidates[z.pick(candidates.count)]
            var seenItems: Set<String> = [meaning(e, language) ?? ""]
            var wrong: [Int] = []
            for d in shuffle(candidates, &z) {
                let a = meaning(d, language) ?? ""
                if seenItems.contains(a) { continue }
                seenItems.insert(a)
                wrong.append(d.number)
                if wrong.count == 3 { break }
            }
            guard wrong.count == 3 else { return nil }
            return bundle(
                .divineNameMeaning, topic: .divineName(e.number), correct: .divineName(e.number),
                wrong: wrong.map { .divineName($0) },
                source: .divineName(e.number), rng: &z)
        }
    }

    /// Meaning for comparison: without case and margins, so that „der Barmherzige“ and
    /// „Der Barmherzige“ do not appear as two answers.
    static func meaning(_ e: DivineName, _ language: String) -> String? {
        e.meaning(language)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func bundle(
        _ kind: QuestionOfTheDay.Kind, topic: QuestionOfTheDay.Topic, correct: QuestionOfTheDay.Option,
        wrong: [QuestionOfTheDay.Option], source: QuestionOfTheDay.Source, rng z: inout SplitMix64
    ) -> QuestionOfTheDay? {
        guard wrong.count >= 2, !wrong.contains(correct), Set(wrong).count == wrong.count else {
            return nil
        }
        let all = shuffle([correct] + wrong, &z)
        guard let i = all.firstIndex(of: correct) else { return nil }
        return QuestionOfTheDay(kind: kind, topic: topic, options: all, correct: i, source: source)
    }

    /// Fisher-Yates with the dedicated generator.
    static func shuffle<T>(_ array: [T], _ z: inout SplitMix64) -> [T] {
        var d = array
        guard d.count > 1 else { return d }
        for i in stride(from: d.count - 1, to: 0, by: -1) {
            d.swapAt(i, z.pick(i + 1))
        }
        return d
    }
}

/// SplitMix64: small, fast and identical everywhere.
struct SplitMix64 {
    var status: UInt64

    init(seed: UInt64) { status = seed }

    mutating func next() -> UInt64 {
        status &+= 0x9E37_79B9_7F4A_7C15
        var z = status
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A number in `0..<upperBound`.
    mutating func pick(_ upperBound: Int) -> Int { Int(next() % UInt64(max(1, upperBound))) }
}
