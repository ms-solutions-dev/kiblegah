import Core

public struct Surah: Sendable, Hashable, Identifiable {
    public enum RevelationPlace: String, Sendable { case meccan = "mekki", medinan = "medeni" }

    public let number: Int
    public let verseCount: Int
    /// Sequential number of the first verse (1…6236).
    public let firstIndex: Int
    public let nameArabic: String
    public let nameTurkish: String
    public let nameLatin: String
    public let meaningEnglish: String
    public let revelationPlace: RevelationPlace
    public let revelationOrder: Int
    /// Whether the basmala precedes verse 1 (all except 1 and 9; in 1 it is verse 1).
    public let basmala: Bool

    public var id: Int { number }
    public var key: ContentKey { .surah(number) }
}

public struct Word: Sendable, Hashable, Identifiable {
    public let key: ContentKey
    public let text: String
    /// Unicode scalar offsets in the unchanged verse text (for tajweed spans).
    public let interval: Range<Int>

    public var id: ContentKey { key }
}

public struct Verse: Sendable, Hashable, Identifiable {
    public enum Sajdah: String, Sendable { case obligatory = "obligatory", recommended = "recommended" }

    public let surah: Int
    public let verse: Int
    /// Sequential number in the Mushaf (1…6236).
    public let index: Int
    /// The Tanzil text unchanged, for verse 1 including the basmala prefix.
    public let rawText: String
    /// Unicode scalar offset at which the verse itself begins (0 without basmala prefix).
    public let basmalaEnd: Int
    public let words: [Word]
    public let juz: Int
    public let hizbQuarter: Int
    public let page: Int
    public let sajdah: Sajdah?

    public var id: Int { index }
    public var key: ContentKey { .verse(surah: surah, verse: verse) }

    /// The verse without basmala prefix, assembled from the words.
    public var text: String { words.map(\.text).joined(separator: " ") }
}

/// A translation text for a verse including source and footnotes.
///
/// Some translations (Saheeh International) put markers like „[1260]“ into the text and the notes
/// into a separate column („[1260]- See footnote to 2:1.“, one per line). The wording is never
/// changed; for display the markers are either left out (`text`) or shown as superscript numbers
/// that match `footnotes` (`markedText`).
public struct TranslationText: Sendable, Hashable {
    public struct Footnote: Sendable, Hashable {
        /// Number of the note within this verse, 1, 2, … (the marker in `markedText`).
        public let number: Int
        public let text: String
    }

    public let pack: String
    /// The text as published, footnote markers included.
    public let rawText: String
    /// The footnote column as published.
    public let footnote: String?
    /// The text for display: the same wording without footnote markers.
    public let text: String
    /// The text with the footnote markers as superscript numbers ¹ ² …
    public let markedText: String
    /// The notes in the order of their markers in the text.
    public let footnotes: [Footnote]

    public init(pack: String, rawText: String, footnote: String?) {
        self.pack = pack
        self.rawText = rawText
        self.footnote = footnote
        let notes = Self.parseNotes(footnote)
        guard !notes.isEmpty else {
            text = rawText
            markedText = rawText
            footnotes = []
            return
        }
        var plain = ""
        var marked = ""
        var found: [Footnote] = []
        var rest = Substring(rawText)
        while let r = rest.firstMatch(of: /\[(\d+)\]/) {
            plain += rest[..<r.range.lowerBound]
            marked += rest[..<r.range.lowerBound]
            if let note = notes[String(r.output.1)] {
                found.append(Footnote(number: found.count + 1, text: note))
                marked += Self.superscript(found.count)
            } else {
                // A bracketed number without a note stays as it is.
                plain += rest[r.range]
                marked += rest[r.range]
            }
            rest = rest[r.range.upperBound...]
        }
        plain += rest
        marked += rest
        text = plain.replacing("  ", with: " ").trimmingCharacters(in: .whitespaces)
        markedText = marked
        footnotes = found
    }

    /// „[8]- Literally …“ per line → ["8": "Literally …"]; lines without a marker continue the previous note.
    static func parseNotes(_ column: String?) -> [String: String] {
        guard let column, !column.isEmpty else { return [:] }
        var notes: [String: String] = [:]
        var last: String?
        for line in column.split(whereSeparator: \.isNewline) {
            if let m = line.wholeMatch(of: /\s*\[(\d+)\]\s*-?\s*(.*)/) {
                let k = String(m.output.1)
                notes[k] = String(m.output.2).trimmingCharacters(in: .whitespaces)
                last = k
            } else if let k = last {
                notes[k, default: ""] += "\n" + line.trimmingCharacters(in: .whitespaces)
            }
        }
        return notes
    }

    static func superscript(_ n: Int) -> String {
        let digits: [Character] = ["⁰", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹"]
        return String(String(n).compactMap { $0.wholeNumberValue.map { digits[$0] } })
    }
}

public struct Transliteration: Sendable, Hashable {
    public let text: String
    public let words: [String]
}

/// A contiguous verse range (page, juz, hizb).
public struct Chapter: Sendable, Hashable {
    public let number: Int
    public let firstIndex: Int
    public let lastIndex: Int
}

/// A verse with similar wording (QUL Similar Ayah, package `benzer`): matching verse, how many
/// words coincide, share of the source verse (%), value 0–100 and the word positions in the match
/// (1-based, QF counting – only approximate for Tanzil words).
public struct SimilarVerse: Sendable, Hashable {
    public let goal: ContentKey
    public let word: Int
    public let scope: Int
    public let score: Int
    public let words: [ClosedRange<Int>]

    public init(goal: ContentKey, word: Int, scope: Int, score: Int, words: [ClosedRange<Int>]) {
        self.goal = goal
        self.word = word
        self.scope = scope
        self.score = score
        self.words = words
    }
}

/// A tajweed rule over a section of the verse (cpfair, Unicode scalar offsets in the
/// verse without basmala prefix – matching `Verse.text`).
public struct TajweedSpan: Sendable, Hashable {
    public let rule: String
    public let interval: Range<Int>

    public init(rule: String, interval: Range<Int>) {
        self.rule = rule
        self.interval = interval
    }
}

/// A dua from the Quran: verses `first…end` of a surah, from word `firstWord` in the first verse.
public struct Dua: Sendable, Hashable, Identifiable {
    public let slug: String
    public let category: String
    public let surah: Int
    public let first: Int
    public let end: Int
    public let firstWord: Int
    /// Last word in the last verse; 0 = up to the end of the verse.
    public let lastWord: Int
    public let index: Int

    public var id: String { slug }
    public var key: ContentKey { .dua(slug) }
    /// The source as a verse key (for „Kur'an'da aç“ and translation).
    public var source: ContentKey {
        first == end ? .verse(surah: surah, verse: first) : .verseRange(surah: surah, first: first, end: end)
    }

    public init(
        slug: String, category: String, surah: Int, first: Int, end: Int, firstWord: Int, lastWord: Int = 0,
        index: Int
    ) {
        self.slug = slug
        self.category = category
        self.surah = surah
        self.first = first
        self.end = end
        self.firstWord = firstWord
        self.lastWord = lastWord
        self.index = index
    }
}

/// A name from the Esmâü'l-Hüsnâ (Tirmidhi order, 1 = Allah).
public struct DivineName: Sendable, Hashable, Identifiable {
    public let number: Int
    public let arabic: String
    public let latin: String
    public let transliterationTR: String?
    public let meaningTR: String?
    public let meaningDE: String?
    public let meaningEN: String?
    /// Citation as in the source: „Q2:32“ (verse) or „T(3507)“ (Tirmidhi).
    public let source: String?
    /// Set by the registry for a name that is never named alone (``namedWithPartner``); an array
    /// only because a struct cannot hold itself directly.
    var partnerStorage: [DivineName] = []

    /// Names that are only ever named together with a partner: ed-Dârr (91) with en-Nâfi‘ (92).
    /// el-Halîmî, el-Minhâc I, 206: calling on Allah with nâfi‘ alone is allowed, with dârr alone it
    /// is not; TDV İslâm Ansiklopedisi, „DÂR“: the name is not used on its own, unlike nâfi‘.
    public static let namedWithPartner: [Int: Int] = [91: 92]

    /// The name this one is always shown with (en-Nâfi‘ for ed-Dârr), otherwise nil.
    public var partner: DivineName? { partnerStorage.first }

    public var id: Int { number }
    public var key: ContentKey { .divineName(number) }

    public func meaning(_ language: String) -> String? {
        switch language {
        case "tr": meaningTR ?? meaningEN
        case "de": meaningDE ?? meaningEN
        default: meaningEN
        }
    }

    /// Whether `meaning(language)` is the English text because the pack has none in `language`
    /// (the Turkish meanings are still missing, see `tools/content/esma.py`). The screens say so
    /// instead of passing the English text off as a translation.
    public func meaningIsEnglishFallback(_ language: String) -> Bool {
        switch language {
        case "tr": meaningTR == nil && meaningEN != nil
        case "de": meaningDE == nil && meaningEN != nil
        default: false
        }
    }

    /// The citation as a verse key, if one is given.
    public var sourceVerse: ContentKey? {
        guard let k = source, k.hasPrefix("Q") else { return nil }
        let p = k.dropFirst().split(separator: ":").compactMap { Int($0) }
        return p.count == 2 ? .verse(surah: p[0], verse: p[1]) : nil
    }
}

/// A search hit.
public struct SearchResult: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable {
        case verse = "ayet", translation = "meal", transliteration = "okunus", dua, divineName = "esma",
            hadith = "hadis"
    }
    public let key: ContentKey
    public let kind: Kind
    public let pack: String
    /// The original text (translation, Okunuş, Esma meaning …) for display.
    public let text: String

    public var id: String { "\(key.text)|\(pack)|\(kind.rawValue)" }
}

/// A tafsir section for a verse range.
public struct TafsirText: Sendable, Hashable {
    public let pack: String
    public let surah: Int
    public let first: Int
    public let end: Int
    public let text: String
}

/// A hadith from HadeethEnc (key `h:hadeethenc:<id>`), with source and grade.
public struct Hadith: Sendable, Hashable, Identifiable {
    public let identifier: Int
    public let language: String
    public let title: String
    public let text: String
    /// „Muttefekun aleyh“, „Buhârî rivayet etmiştir“ …
    public let source: String
    /// „Sahih Hadis“, „Hasen“ …
    public let degrees: String
    public let explanation: String
    public let benefits: [String]
    public let arabic: String

    public var id: Int { identifier }
    public var key: ContentKey { .hadith(collection: "hadeethenc", number: identifier) }
}

public struct HadithCategory: Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let parent: Int?
    public let count: Int
}
