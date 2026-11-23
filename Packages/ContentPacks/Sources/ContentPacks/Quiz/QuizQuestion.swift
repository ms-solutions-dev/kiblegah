import Core
import Foundation

/// An area of the quiz. Each area has its own level.
///
/// Not an `enum`: besides the five generator areas, every verified bank of an installed bank source
/// is an area. A new bank thus becomes a tile without an app change; its name comes from the
/// catalog or from the source.
public struct QuizArea: RawRepresentable, Sendable, Codable, Hashable, Identifiable {
    public let rawValue: String

    /// `nil` only for the empty text (stored as "Karışık").
    public init?(rawValue: String) {
        guard !rawValue.isEmpty else { return nil }
        self.rawValue = rawValue
    }

    /// The area of a bank (`ilmihal`, `siyer` …).
    public init(bank: String) { rawValue = bank }

    public var id: String { rawValue }

    public static let quran = QuizArea(bank: "kuran")
    public static let translation = QuizArea(bank: "meal")
    public static let divineName = QuizArea(bank: "esma")
    public static let hadith = QuizArea(bank: "hadis")
    public static let dua = QuizArea(bank: "dua")
    public static let ilmihal = QuizArea(bank: "ilmihal")

    /// The fixed areas in the order of the duel code (3 bits, index + 1) – never reorder.
    public static let allCases: [QuizArea] = [.quran, .translation, .divineName, .hadith, .dua, .ilmihal]

    /// Areas the generator fills from the content packs (the rest come from verified banks).
    public static let generated: [QuizArea] = [.quran, .translation, .divineName, .hadith, .dua]

    /// Area of a question bank (everything except the generator areas).
    public var isBank: Bool { !Self.generated.contains(self) }
}

/// How a question is answered.
public enum QuizFormat: String, Sendable, Hashable, Codable {
    case fourOptions = "dortSecenek", trueFalse = "dogruYanlis", wordTiles = "kelimeKacheln"
}

/// The question kind; it determines question text, answer class and rule level.
public enum QuizQuestionKind: String, CaseIterable, Sendable, Hashable, Codable {
    /// Question 1 of the daily round: the daily question from ``QuestionGenerator``, unchanged.
    case questionOfTheDay = "gununSorusu"
    /// "In which surah is this verse?" – the translation is shown.
    case translationSurah = "mealSure"
    case verseCount = "ayetSayisi"
    /// "In which Juz is surah X?" – only surahs lying entirely within one Juz.
    case surahJuz = "sureCuzu"
    /// "Which of these surahs is Medinan?" (one Medinan, three Meccan).
    case medinanSurah = "medeniSure"
    /// "Which of these surahs is Meccan?" (one Meccan, three Medinan).
    case meccanSurah = "mekkiSure"
    /// "Which of these surahs was revealed first?" – only with ≥ 20 places apart.
    case firstRevealed = "ilkNazil"
    /// Complete the verse with word tiles.
    case wordGap = "kelimeBosluk"
    /// Name → meaning.
    case divineNameMeaning = "esmaAnlami"
    /// Meaning → name.
    case meaningDivineName = "anlamEsma"
    /// Hadith text → collection.
    case hadithCollection = "hadisKoleksiyon"
    /// Hadith text → top-level category (HadeethEnc).
    case hadithCategory = "hadisKategori"
    /// Quran dua → group (Rabbenâ, Peygamber, Aile, İlim).
    case duaCategory = "duaKategori"
    /// Quran dua → surah.
    case duaSurah = "duaSure"
    /// Verified question of a question bank; the area is in the question itself.
    case bank = "banka"

    /// The area of a generated question; the daily question carries its own area.
    public var area: QuizArea {
        switch self {
        case .translationSurah, .questionOfTheDay: .translation
        case .verseCount, .surahJuz, .medinanSurah, .meccanSurah, .firstRevealed, .wordGap: .quran
        case .divineNameMeaning, .meaningDivineName: .divineName
        case .hadithCollection, .hadithCategory: .hadith
        case .duaCategory, .duaSurah: .dua
        case .bank: .ilmihal
        }
    }
}

/// The six books and Ahmed, as HadeethEnc names them. Only hadiths with exactly one of these
/// attributions appear in questions (distractor rule 3: nothing partially correct).
public enum HadithCollection: String, CaseIterable, Sendable, Hashable, Codable {
    case muttafaqAlayh = "muttefekunAleyh", bukhari = "buhari", muslim, abuDawud = "ebuDavud", tirmidhi =
        "tirmizi", nasai = "nesai", ibnMajah = "ibnMace", ahmad = "ahmed"

    /// Reads the pack's Turkish source attribution; anything other than a single collection yields `nil`.
    public static func parse(_ source: String) -> HadithCollection? {
        var k = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if k.hasSuffix(".") { k.removeLast() }
        switch k.lowercased() {
        case "muttefekun aleyh": return .muttafaqAlayh
        case "buhârî rivayet etmiştir": return .bukhari
        case "müslim rivayet etmiştir": return .muslim
        case "ebû dâvûd rivayet etmiştir": return .abuDawud
        case "tirmizî rivayet etmiştir": return .tirmidhi
        case "nesâî rivayet etmiştir": return .nasai
        case "i̇bn mâce rivayet etmiştir", "ibn mâce rivayet etmiştir": return .ibnMajah
        case "ahmed rivayet etmiştir": return .ahmad
        default: return nil
        }
    }
}

/// An answer option. There is deliberately no free text: options are metadata or real
/// content from the packs; only the verified banks carry their own texts (`text`).
public enum QuizOption: Sendable, Hashable {
    case surah(Int)
    case number(Int)
    case juz(Int)
    /// Shows the meaning of name no. n.
    case divineNameMeaning(Int)
    /// Shows name no. n.
    case divineNameLabel(Int)
    case collection(HadithCollection)
    /// Top-level category of the hadith encyclopedia (ID as in the pack).
    case hadithCategory(Int)
    case duaCategory(String)
    /// A real word from the word table (`w:s:a:i`).
    case word(ContentKey)
    case correct
    case wrong
    /// Option no. i of a curated question (text from the bank in the app language).
    case text(Int)
}

/// What the question refers to.
public enum QuizTopic: Sendable, Hashable {
    case verse(ContentKey)
    case surah(Int)
    case divineName(Int)
    case hadith(Int)
    case dua(String)
    /// The gap in the verse: the missing word.
    case word(ContentKey)
    /// Question `id` of bank `bank`.
    case bank(String, String)
    case noTopic
}

/// The citation after the answer.
public enum QuizSource: Sendable, Hashable {
    case verse(ContentKey)
    case divineName(Int)
    case hadith(Int)
    case dua(String)
    /// The citations of question `id` of bank `bank`.
    case bank(String, String)
}

/// A question at runtime; only its identifier (`identifier`) is stored.
public struct QuizQuestion: Sendable, Hashable, Identifiable {
    /// `gen:<kind>:<key>:<seed>`, `kur:quiz-<bank>:<id>:<seed>` or `day:<day number>`.
    public let identifier: String
    public let area: QuizArea
    public let kind: QuizQuestionKind
    public let format: QuizFormat
    /// Rule level 1…5.
    public let level: Int
    public let topic: QuizTopic
    public let options: [QuizOption]
    public let correct: Int
    public let source: QuizSource
    /// `true` ⇒ never in a round.
    public let disputed: Bool
    /// For the daily question: the kind from ``QuestionGenerator`` (for question text and citation).
    public let dayKind: QuestionOfTheDay.Kind?

    public var id: String { identifier }

    public init(
        identifier: String, area: QuizArea, kind: QuizQuestionKind, format: QuizFormat = .fourOptions,
        level: Int,
        topic: QuizTopic, options: [QuizOption], correct: Int, source: QuizSource,
        disputed: Bool = false, dayKind: QuestionOfTheDay.Kind? = nil
    ) {
        self.identifier = identifier
        self.area = area
        self.kind = kind
        self.format = format
        self.level = level
        self.topic = topic
        self.options = options
        self.correct = correct
        self.source = source
        self.disputed = disputed
        self.dayKind = dayKind
    }

    /// The daily question as question 1 of the daily round: same options in the same order, so that the
    /// answer (index) given on the start page still applies here.
    public init(ofTheDay s: QuestionOfTheDay, dayNumber: Int) {
        let area: QuizArea =
            switch s.kind {
            case .verseSurah: .translation
            case .divineNameMeaning: .divineName
            default: .quran
            }
        let topic: QuizTopic =
            switch s.topic {
            case .verse(let a): .verse(a)
            case .surah(let n): .surah(n)
            case .divineName(let n): .divineName(n)
            case .noTopic: .noTopic
            }
        let options: [QuizOption] = s.options.map {
            switch $0 {
            case .surah(let n): .surah(n)
            case .number(let n): .number(n)
            case .divineName(let n): .divineNameMeaning(n)
            }
        }
        let source: QuizSource =
            switch s.source {
            case .verse(let a): .verse(a)
            case .divineName(let n): .divineName(n)
            }
        self.init(
            identifier: QuizID.ofTheDay(dayNumber), area: area, kind: .questionOfTheDay, level: 1,
            topic: topic,
            options: options, correct: s.correct, source: source, dayKind: s.kind)
    }

    /// The same question as a generator identifier, so that a wrongly answered daily question can
    /// go into the review (options may be reshuffled there, the subject stays).
    public var reviewID: String {
        guard kind == .questionOfTheDay, let g = dayKind else { return identifier }
        let seed = UInt64(abs(identifier.stableHashValue) % 1_000_000)
        switch (g, topic, options.indices.contains(correct) ? options[correct] : nil) {
        case (.verseSurah, .verse(let a), _): return QuizID.gen(.translationSurah, a.text, seed)
        case (.verseCount, .surah(let n), _): return QuizID.gen(.verseCount, "s:\(n)", seed)
        case (.divineNameMeaning, .divineName(let n), _):
            return QuizID.gen(.divineNameMeaning, "e:\(n)", seed)
        case (.medinanSurah, _, .surah(let n)?): return QuizID.gen(.medinanSurah, "s:\(n)", seed)
        case (.firstRevealed, _, .surah(let n)?): return QuizID.gen(.firstRevealed, "s:\(n)", seed)
        default: return identifier
        }
    }
}

/// Building and parsing identifiers (concept "Data model sketch").
public enum QuizID {
    public static func gen(_ kind: QuizQuestionKind, _ key: String, _ seed: UInt64) -> String {
        "gen:\(kind.rawValue):\(key):\(seed)"
    }

    /// `kur:quiz-<bank>:<id>:<seed>`; the seed shuffles the options. For İlmihal the same form as
    /// in V1 (`kur:quiz-ilmihal:…`), old rounds and review cards remain valid.
    public static func bank(_ bank: String, _ id: String, seed: UInt64) -> String {
        "kur:quiz-\(bank):\(id):\(seed)"
    }

    public static func ofTheDay(_ dayNumber: Int) -> String { "gun:\(dayNumber)" }

    /// `gen:<kind>:<key>:<seed>` → parts; the key may itself contain colons (`a:112:1`).
    public static func parse(_ identifier: String) -> (kind: QuizQuestionKind, key: String, seed: UInt64)? {
        let p = identifier.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard p.count >= 4, p[0] == "gen", let kind = QuizQuestionKind(rawValue: p[1]),
            let seed = UInt64(p[p.count - 1])
        else { return nil }
        return (kind, p[2..<(p.count - 1)].joined(separator: ":"), seed)
    }

    /// Bank, ID and seed from `kur:quiz-<bank>:<id>:<seed>`.
    public static func decodeBank(_ identifier: String) -> (bank: String, id: String, seed: UInt64)? {
        let prefix = "kur:quiz-"
        guard identifier.hasPrefix(prefix) else { return nil }
        let remaining = identifier.dropFirst(prefix.count)
        guard let b = remaining.firstIndex(of: ":"), !remaining[..<b].isEmpty else { return nil }
        let bank = String(remaining[..<b])
        let rest = remaining[remaining.index(after: b)...]
        guard let i = rest.lastIndex(of: ":"), let t = UInt64(rest[rest.index(after: i)...]) else {
            return rest.isEmpty ? nil : (bank, String(rest), 0)
        }
        return (bank, String(rest[..<i]), t)
    }

    /// The subject of an identifier without seed: `<kind>:<key>` for generator questions,
    /// `<bank>:<id>` for bank questions, `nil` for the daily question. "Already seen" depends on it –
    /// the same question with reshuffled options is not a new one.
    public static func topicKey(_ identifier: String) -> String? {
        if let p = parse(identifier) { return "\(p.kind.rawValue):\(p.key)" }
        if let p = decodeBank(identifier) { return "\(p.bank):\(p.id)" }
        return nil
    }

    /// The day number from `day:<n>`.
    public static func dayNumber(_ identifier: String) -> Int? {
        identifier.hasPrefix("gun:") ? Int(identifier.dropFirst(4)) : nil
    }
}

/// When each subject was last shown (key from ``QuizID/topicKey(_:)``).
///
/// Practice rounds thus draw unseen ones first; once an area is exhausted, the longest-unseen
/// questions. Daily round and duel get ``empty`` so that they stay the same for everyone.
public struct QuizSeen: Sendable {
    public var dates: [String: Date]

    public static let empty = QuizSeen(dates: [:])

    public init(dates: [String: Date]) { self.dates = dates }

    /// From question identifiers with the time of their answer (multiple allowed, the latest counts).
    public init(ids: [(String, Date)]) {
        var t: [String: Date] = [:]
        for (k, time) in ids {
            guard let a = QuizID.topicKey(k) else { continue }
            if let old = t[a], old >= time { continue }
            t[a] = time
        }
        dates = t
    }

    public var isEmpty: Bool { dates.isEmpty }

    /// The candidates of a pass: `fresh` only unseen ones; otherwise the longest-unseen quarter
    /// (at least one), so that the same ones do not always crowd in on the second pass.
    func pick<T>(_ l: [T], fresh: Bool, key: (T) -> String) -> [T] {
        if fresh { return l.filter { dates[key($0)] == nil } }
        let ordered = l.enumerated().sorted {
            (dates[key($0.element)] ?? .distantPast, $0.offset)
                < (dates[key($1.element)] ?? .distantPast, $1.offset)
        }
        return ordered.prefix(max(1, (l.count + 3) / 4)).map(\.element)
    }
}

extension String {
    /// FNV-1a: the same across runs and devices (unlike `hashValue`).
    var stableHashValue: Int {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in utf8 {
            h ^= UInt64(b)
            h = h &* 0x100_0000_01b3
        }
        return Int(truncatingIfNeeded: h >> 1)
    }
}
