import Core
import Foundation

public struct BankQuestion: Codable, Sendable, Hashable, Identifiable {
    public struct LocalizedText: Codable, Sendable, Hashable {
        public var tr: String?
        public var de: String?
        public var en: String?

        public init(tr: String? = nil, de: String? = nil, en: String? = nil) {
            self.tr = tr
            self.de = de
            self.en = en
        }

        /// Text in `language`, otherwise Turkish (the banks are built from Turkish works).
        public func text(_ language: String) -> String {
            let d: String? =
                switch language {
                case "de": de
                case "en": en
                default: tr
                }
            return [d, tr, en, de].compactMap { $0 }.first { !$0.isEmpty } ?? ""
        }
    }

    public struct Options: Codable, Sendable, Hashable {
        public var tr: [String]?
        public var de: [String]?
        public var en: [String]?

        public init(tr: [String]? = nil, de: [String]? = nil, en: [String]? = nil) {
            self.tr = tr
            self.de = de
            self.en = en
        }

        /// Options in `language`, otherwise Turkish – only if the count matches the Turkish ones.
        public func list(_ language: String) -> [String] {
            let baseList = tr ?? en ?? de ?? []
            let d: [String]? =
                switch language {
                case "de": de
                case "en": en
                default: tr
                }
            if let d, d.count == baseList.count, !d.contains(where: \.isEmpty) { return d }
            return baseList
        }
    }

    /// Where the answer is: work (`sallabi1`, `hisam2`, `translation-tr-diyanet` …), volume, print and PDF page,
    /// literal quote. For a translation the verse stands in place of the page (`verse`, „2:34“).
    public struct Citation: Codable, Sendable, Hashable {
        public var work: String?
        public var volume: Int?
        public var page: Int?
        public var pdfPage: Int?
        public var verse: String?
        public var excerpt: String?

        enum CodingKeys: String, CodingKey {
            case work = "eser", volume = "cilt", page = "sayfa", verse = "ayet", excerpt = "alinti"
            case pdfPage = "pdf_sayfa"
        }

        public init(
            work: String? = nil, volume: Int? = nil, page: Int? = nil, pdfPage: Int? = nil,
            verse: String? = nil,
            excerpt: String? = nil
        ) {
            self.work = work
            self.volume = volume
            self.page = page
            self.pdfPage = pdfPage
            self.verse = verse
            self.excerpt = excerpt
        }

        /// Read leniently: a broken field (page as text, `null`) costs only itself.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            work = try? c.decodeIfPresent(String.self, forKey: .work)
            volume = try? c.decodeIfPresent(Int.self, forKey: .volume)
            page = try? c.decodeIfPresent(Int.self, forKey: .page)
            pdfPage = try? c.decodeIfPresent(Int.self, forKey: .pdfPage)
            verse = try? c.decodeIfPresent(String.self, forKey: .verse)
            excerpt = try? c.decodeIfPresent(String.self, forKey: .excerpt)
        }

        /// The work without volume number (`hisam2` → `hisam`), for the work title in the catalog.
        public var workName: String? {
            guard let work else { return nil }
            let stem = String(work.reversed().drop(while: \.isNumber).reversed())
            return stem.isEmpty ? work : stem
        }

        /// The verse of a translation citation as key (`a:2:34`).
        public var verseKey: ContentKey? {
            guard let verse else { return nil }
            let p = verse.split(separator: ":").compactMap { Int($0) }
            guard p.count == 2 else { return nil }
            return .verse(surah: p[0], verse: p[1])
        }
    }

    public struct Review: Codable, Sendable, Hashable {
        enum CodingKeys: String, CodingKey {
            case reviewer = "kim"
            case date = "tarih"
            case approval = "onay"
            case note = "not"
        }

        public var reviewer: String?
        public var date: String?
        public var approval: Bool?
        public var note: String?

        public init(reviewer: String? = nil, date: String? = nil, approval: Bool? = nil, note: String? = nil)
        {
            self.reviewer = reviewer
            self.date = date
            self.approval = approval
            self.note = note
        }
    }

    public let id: String
    /// The bank the question comes from (`ilmihal`, `siyer` …); not in the JSON, ``parse(_:bank:)`` sets it.
    public var bank: String
    public var area: String?
    public var topic: String?
    public var format: String
    public var level: Int
    public var disputed: Bool
    public var text: LocalizedText
    public var options: Options?
    /// Index of the correct option; for true/false 0 = doğru, 1 = yanlış.
    public var correct: Int
    public var citation: Citation?
    /// Second source (Siyer, Sahâbe: the second work; Peygamberler: the translation verse).
    public var citation2: Citation?
    public var review: Review?

    enum CodingKeys: String, CodingKey {
        case id, bank = "banka", area = "alan", topic = "konu", format = "bicim", level = "seviye", disputed =
            "ihtilafli", text = "metin", options = "secenekler", correct = "dogru", citation = "beleg",
            citation2 = "beleg2", review = "kontrol"
    }

    public init(
        id: String, bank: String = "ilmihal", area: String? = nil, topic: String? = nil,
        format: String = "dortSecenek", level: Int = 2, disputed: Bool = false, text: LocalizedText,
        options: Options? = nil, correct: Int, citation: Citation? = nil, citation2: Citation? = nil,
        review: Review? = nil
    ) {
        self.id = id
        self.bank = bank
        self.area = area ?? bank
        self.topic = topic
        self.format = format
        self.level = level
        self.disputed = disputed
        self.text = text
        self.options = options
        self.correct = correct
        self.citation = citation
        self.citation2 = citation2
        self.review = review
    }

    /// Read leniently: `correct` may also be `true`/`false` for true/false, numbers may come as text.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) {
            id = s
        } else {
            id = String(try c.decode(Int.self, forKey: .id))
        }
        area = try? c.decodeIfPresent(String.self, forKey: .area)
        bank = (try? c.decodeIfPresent(String.self, forKey: .bank)) ?? area ?? "ilmihal"
        topic = try? c.decodeIfPresent(String.self, forKey: .topic)
        format = (try? c.decodeIfPresent(String.self, forKey: .format)) ?? "dortSecenek"
        level = (try? c.decodeIfPresent(Int.self, forKey: .level)) ?? 2
        disputed = (try? c.decodeIfPresent(Bool.self, forKey: .disputed)) ?? false
        text = try c.decode(LocalizedText.self, forKey: .text)
        options = try? c.decodeIfPresent(Options.self, forKey: .options)
        if let i = try? c.decode(Int.self, forKey: .correct) {
            correct = i
        } else if let b = try? c.decode(Bool.self, forKey: .correct) {
            correct = b ? 0 : 1
        } else {
            correct = -1
        }
        citation = try? c.decodeIfPresent(Citation.self, forKey: .citation)
        citation2 = try? c.decodeIfPresent(Citation.self, forKey: .citation2)
        review = try? c.decodeIfPresent(Review.self, forKey: .review)
    }

    public var isTrueFalse: Bool { format == "dogruYanlis" }

    /// Reviewed and approved.
    public var approved: Bool { review?.approval == true }

    /// Not yet reviewed (neither approved nor rejected).
    public var isPending: Bool { review?.approval == nil }

    /// The area in the quiz: every bank is its own.
    public var quizArea: QuizArea { QuizArea(bank: bank) }

    /// May go into a round: not rejected, not disputed, answer present.
    public var available: Bool {
        guard review?.approval != false, !disputed else { return false }
        let n = isTrueFalse ? 2 : (options?.list("tr").count ?? 0)
        return (2...4).contains(n) && (0..<n).contains(correct)
    }

    /// As a quiz question. The bank sorts numbers ascending, so the correct one is often first;
    /// the options are shuffled per seed (same seed, same order on every device).
    /// True/false keeps the order „doğru, yanlış“ – there the position gives nothing away.
    public func question(seed: UInt64) -> QuizQuestion {
        let n = isTrueFalse ? 2 : (options?.list("tr").count ?? 0)
        var options: [QuizOption] = isTrueFalse ? [.correct, .wrong] : (0..<n).map { .text($0) }
        var d = correct
        if !isTrueFalse, options.indices.contains(correct) {
            let actual = options[correct]
            var z = SplitMix64(seed: seed &* 0x9E37_79B9_7F4A_7C15 &+ UInt64(id.stableHashValue))
            options = QuestionGenerator.shuffle(options, &z)
            d = options.firstIndex(of: actual) ?? correct
        }
        return QuizQuestion(
            identifier: QuizID.bank(bank, id, seed: seed), area: quizArea, kind: .bank,
            format: isTrueFalse ? .trueFalse : .fourOptions, level: min(5, max(1, level)),
            topic: .bank(bank, id), options: options, correct: d, source: .bank(bank, id),
            disputed: disputed)
    }

    /// Reads a bank: a list or an object with the list under `questions`.
    /// A broken entry costs only itself, not the whole bank.
    public static func parse(_ data: Data, bank: String) throws -> [BankQuestion] {
        struct LenientQuestion: Decodable {
            let question: BankQuestion?
            init(from decoder: Decoder) throws { question = try? BankQuestion(from: decoder) }
        }
        struct Wrapper: Decodable {
            let questions: [LenientQuestion]
            enum CodingKeys: String, CodingKey { case questions = "sorular" }
        }
        let l: [BankQuestion]
        if let d = try? JSONDecoder().decode([LenientQuestion].self, from: data) {
            l = d.compactMap(\.question)
        } else {
            l = try JSONDecoder().decode(Wrapper.self, from: data).questions.compactMap(\.question)
        }
        return l.map {
            var s = $0
            s.bank = bank
            return s
        }
    }
}

/// A bank as a bank source lists it.
public struct QuizBank: Codable, Sendable, Hashable, Identifiable {
    enum CodingKeys: String, CodingKey {
        case bank = "banka"
        case name = "ad"
        case number = "sayi"
        case approved = "onayli"
    }

    public let bank: String
    public var name: BankQuestion.LocalizedText
    public var number: Int
    public var approved: Int

    public var id: String { bank }

    public init(bank: String, name: BankQuestion.LocalizedText = .init(), number: Int = 0, approved: Int = 0)
    {
        self.bank = bank
        self.name = name
        self.number = number
        self.approved = approved
    }

    /// Read leniently: a missing name or missing numbers cost nothing.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bank = try c.decode(String.self, forKey: .bank)
        name = (try? c.decodeIfPresent(BankQuestion.LocalizedText.self, forKey: .name)) ?? .init()
        number = (try? c.decodeIfPresent(Int.self, forKey: .number)) ?? 0
        approved = (try? c.decodeIfPresent(Int.self, forKey: .approved)) ?? 0
    }

    /// Reads `{"banks":[…]}`; only lowercase names.
    public static func parse(_ data: Data) throws -> [QuizBank] {
        struct Wrapper: Decodable {
            let banks: [QuizBank]
            enum CodingKeys: String, CodingKey { case banks = "bankalar" }
        }
        return try JSONDecoder().decode(Wrapper.self, from: data).banks.filter {
            !$0.bank.isEmpty && $0.bank.allSatisfy { $0.isASCII && $0.isLowercase }
        }
    }
}
