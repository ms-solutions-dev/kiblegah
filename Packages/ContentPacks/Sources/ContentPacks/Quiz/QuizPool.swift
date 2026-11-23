import Core
import Foundation

/// Everything the quiz generator builds questions from, read once from the content packages.
///
/// The selection depends only on the packages, never on the app language or the device: this way two
/// devices with the same app get the same daily round on the same day. Texts (translation, meaning, hadith)
/// are inserted by the UI only at display time, in the app language.
public final class QuizPool: Sendable {
    /// A subject that can be asked about, with its rule level (1…5).
    public struct Topic: Sendable, Hashable {
        public let key: String
        public let level: Int
    }

    struct WordItem: Sendable, Hashable {
        let key: ContentKey
        let text: String
        let skeleton: String
    }

    struct HadithItem: Sendable, Hashable {
        let identifier: Int
        let collection: HadithCollection?
        /// The single parent category, otherwise `nil`.
        let topCategory: Int?
    }

    let surahs: [Surah]
    let surahByNumber: [Int: Surah]
    /// Surah → juz, only for surahs that lie entirely within one juz.
    let singleJuz: [Int: Int]
    /// Words per verse (only verses from the tile and translation pools).
    let verseWords: [ContentKey: [WordItem]]
    /// Words from juz 30 (distinct skeletons) as tile distractors.
    let wordPool: [WordItem]
    let divineNames: [DivineName]
    let divineNameNumber: [Int: DivineName]
    let hadiths: [Int: HadithItem]
    let hadithTopCategories: [Int]
    let duas: [Dua]
    let duaSkeleton: [String: String]
    /// Subjects per question kind, sorted by key.
    let topics: [QuizQuestionKind: [Topic]]

    /// Which areas work with the loaded packages (Store edition without Esma package, etc.).
    public var areas: Set<QuizArea> {
        Set(topics.filter { !$0.value.isEmpty }.keys.map(\.area))
    }

    public func topics(_ kind: QuizQuestionKind) -> [Topic] { topics[kind] ?? [] }

    func wordText(_ a: ContentKey) -> String? {
        guard case .word(let s, let n, _) = a else { return nil }
        return verseWords[.verse(surah: s, verse: n)]?.first { $0.key == a }?.text
            ?? wordPool.first { $0.key == a }?.text
    }

    // MARK: Setup

    /// Surahs whose verses count as easy.
    static func isKnown(_ s: Int, _ a: Int) -> Bool {
        s >= 78 || s == 1 || s == 36 || s == 67 || (s == 18 && a <= 10)
    }

    public init(contentProvider: any ContentProvider) {
        surahs = contentProvider.surahs()
        surahByNumber = Dictionary(uniqueKeysWithValues: surahs.map { ($0.number, $0) })
        var singleJuz: [Int: Int] = [:]
        let juzs = (1...30).compactMap { contentProvider.juz($0) }
        for s in surahs {
            let end = s.firstIndex + s.verseCount - 1
            if let c = juzs.first(where: { $0.firstIndex <= s.firstIndex && end <= $0.lastIndex }) {
                singleJuz[s.number] = c.number
            }
        }
        self.singleJuz = singleJuz

        // All verses once: text skeleton for uniqueness, words for tiles.
        var verses: [Verse] = []
        for s in surahs { verses += contentProvider.verses(.surah(s.number)) }
        var skeletonSurahs: [String: Set<Int>] = [:]
        for a in verses {
            skeletonSurahs[QuizRules.skeleton(a.text), default: []].insert(a.surah)
        }
        var verseWords: [ContentKey: [WordItem]] = [:]
        var translationTopics: [Topic] = []
        var wordTopics: [Topic] = []
        var pool: [String: WordItem] = [:]
        for a in verses {
            let n = a.words.count
            // Only verses whose wording appears in no other surah – otherwise two surahs would be correct.
            guard (skeletonSurahs[QuizRules.skeleton(a.text)] ?? []).count == 1 else { continue }
            let known = Self.isKnown(a.surah, a.verse)
            let words = a.words.map {
                WordItem(key: $0.key, text: $0.text, skeleton: QuizRules.skeleton($0.text))
            }
            if a.surah >= 78 {
                for k in words where k.skeleton.unicodeScalars.count >= 2 && pool[k.skeleton] == nil {
                    pool[k.skeleton] = k
                }
            }
            if let sv = Self.translationLevel(surah: a.surah, verse: a.verse, word: n) {
                translationTopics.append(Topic(key: a.key.text, level: sv))
            }
            if known, let sv = Self.wordLevel(surah: a.surah, word: n) {
                verseWords[a.key] = words
                // The gap: a word with at least two letters; the generator chooses the position.
                for k in words where k.skeleton.unicodeScalars.count >= 2 {
                    wordTopics.append(Topic(key: k.key.text, level: sv))
                }
            }
        }
        self.verseWords = verseWords
        wordPool = pool.values.sorted { $0.key.text < $1.key.text }

        // ed-Dârr never stands alone (DivineName.namedWithPartner), so no quiz asks for it on its own.
        divineNames = contentProvider.divineNames().filter {
            $0.number != 1 && DivineName.namedWithPartner[$0.number] == nil
        }
        divineNameNumber = Dictionary(uniqueKeysWithValues: divineNames.map { ($0.number, $0) })

        var hadiths: [Int: HadithItem] = [:]
        let forbidden = ["buhâr", "müslim", "tirmiz", "dâvûd", "nesâ", "mâce", "ahmed", "bukhari", "muslim"]
        let rawHadiths = contentProvider.quizHadiths()
        for h in rawHadiths {
            let b = h.title.lowercased()
            guard (20...220).contains(h.title.count), !forbidden.contains(where: { b.contains($0) }) else {
                continue
            }
            let k = HadithCollection.parse(h.source)
            let parent = h.parentCategories.count == 1 ? h.parentCategories.first : nil
            if k != nil || parent != nil {
                hadiths[h.identifier] = HadithItem(
                    identifier: h.identifier, collection: k, topCategory: parent)
            }
        }
        self.hadiths = hadiths
        hadithTopCategories = Array(Set(rawHadiths.flatMap(\.parentCategories))).sorted()

        duas = contentProvider.duas()
        var duaSkeleton: [String: String] = [:]
        for d in duas {
            duaSkeleton[d.slug] = QuizRules.skeleton(Self.duaText(d, contentProvider: contentProvider))
        }
        self.duaSkeleton = duaSkeleton

        var k: [QuizQuestionKind: [Topic]] = [:]
        k[.translationSurah] = translationTopics
        k[.wordGap] = wordTopics
        k[.verseCount] = surahs.map { Topic(key: "s:\($0.number)", level: Self.verseCountLevel($0)) }
        k[.surahJuz] = surahs.compactMap { s in
            singleJuz[s.number].map { Topic(key: "s:\(s.number)", level: Self.juzLevel($0)) }
        }
        let disputed = QuestionGenerator.revelationPlaceDisputed
        k[.medinanSurah] = surahs.filter { $0.revelationPlace == .medinan && !disputed.contains($0.number) }
            .map { Topic(key: "s:\($0.number)", level: 2) }
        k[.meccanSurah] = surahs.filter { $0.revelationPlace == .meccan && !disputed.contains($0.number) }
            .map { Topic(key: "s:\($0.number)", level: 3) }
        k[.firstRevealed] = surahs.map { Topic(key: "s:\($0.number)", level: 4) }
        k[.divineNameMeaning] = divineNames.map {
            Topic(key: "e:\($0.number)", level: Self.divineNameLevel($0.number))
        }
        k[.meaningDivineName] = divineNames.map {
            Topic(key: "e:\($0.number)", level: Self.divineNameLevel($0.number))
        }
        let hs = hadiths.values.sorted { $0.identifier < $1.identifier }
        k[.hadithCollection] = hs.compactMap { h in
            h.collection.map {
                Topic(key: "h:hadeethenc:\(h.identifier)", level: Self.collectionLevel($0))
            }
        }
        k[.hadithCategory] = hs.compactMap { h in
            h.topCategory.map { _ in Topic(key: "h:hadeethenc:\(h.identifier)", level: 3) }
        }
        k[.duaCategory] = duas.filter { QuizRules.duaDistractors($0).count >= 2 }
            .map { Topic(key: "d:\($0.slug)", level: 2) }
        k[.duaSurah] = duas.map { Topic(key: "d:\($0.slug)", level: 3) }
        topics = k.mapValues { $0.sorted { $0.key < $1.key } }
    }

    /// The Arabic wording of a dua (from `firstWord`, up to `lastWord`).
    static func duaText(_ d: Dua, contentProvider: any ContentProvider) -> String {
        let verses = contentProvider.verses(d.source)
        var words: [String] = []
        for (i, a) in verses.enumerated() {
            let first = i == 0 ? max(1, d.firstWord) : 1
            let end = i == verses.count - 1 && d.lastWord > 0 ? d.lastWord : a.words.count
            guard first <= end else { continue }
            words += a.words.dropFirst(first - 1).prefix(end - first + 1).map(\.text)
        }
        return words.joined(separator: " ")
    }

    // MARK: Rule levels
    //
    // The table is deliberately in one place; whoever wants to change a level changes it only here.

    /// Translation → surah: known surahs 1–2, surahs 50–77 level 3, otherwise 4. Verses with 3–12 words;
    /// shorter ones carry too little content, longer ones overflow the card.
    static func translationLevel(surah: Int, verse: Int, word: Int) -> Int? {
        guard (3...12).contains(word) else { return nil }
        if isKnown(surah, verse) { return word <= 6 ? 1 : 2 }
        if (50...77).contains(surah) { return 3 }
        return word >= 6 ? 4 : nil
    }

    /// Word tiles: 3–5 words level 1 (Fâtiha, surahs 105–114) or 2, 6–8 words level 3,
    /// 9–14 words level 4.
    static func wordLevel(surah: Int, word: Int) -> Int? {
        switch word {
        case 3...5: (surah == 1 || surah >= 105) ? 1 : 2
        case 6...8: 3
        case 9...14: 4
        default: nil
        }
    }

    /// Verse count: up to 10 verses and Baqarah easy, Juz 29–30 medium, otherwise hard.
    static func verseCountLevel(_ s: Surah) -> Int {
        if s.number == 2 || s.verseCount <= 7 { return 1 }
        if s.verseCount <= 10 { return 2 }
        if s.number >= 67 { return 3 }
        return 4
    }

    static func juzLevel(_ juz: Int) -> Int {
        switch juz {
        case 30: 1
        case 29: 2
        case 26...28: 3
        default: 4
        }
    }

    /// Esmâ: the first 20 names easy (2–7 level 1), 21–60 medium, 61–99 hard.
    static func divineNameLevel(_ number: Int) -> Int {
        switch number {
        case ...7: 1
        case ...20: 2
        case ...60: 3
        default: 4
        }
    }

    /// Hadith → collection: Muttefekun aleyh easy, Buhârî/Müslim alone medium, the Sunan hard.
    static func collectionLevel(_ k: HadithCollection) -> Int {
        switch k {
        case .muttafaqAlayh: 1
        case .bukhari, .muslim: 3
        default: 4
        }
    }

    /// Esma level band for distractors from "the same level".
    static func divineNameBand(_ number: Int) -> ClosedRange<Int> {
        switch number {
        case ...20: 2...20
        case ...60: 21...60
        default: 61...99
        }
    }
}
