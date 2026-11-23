import Core
import Foundation

/// The single read interface to all content.
///
/// Views, search and later the AI tools (`ayet_getir`, `meal_getir` …)
/// go only through this. Whoever needs new content kinds extends this interface,
/// not the view.
public protocol ContentProvider: Sendable {
    var packs: [PackManifest] { get }

    func surahs() -> [Surah]
    func surah(_ number: Int) -> Surah?
    /// A single verse with words, or `nil` for unknown keys.
    func verse(_ key: ContentKey) -> Verse?
    /// All verses of a key: surah, range, page, juz or single verse.
    func verses(_ key: ContentKey) -> [Verse]
    func words(_ key: ContentKey) -> [Word]
    /// Translation of a verse from a package (`translation-tr-diyanet` …).
    func translation(_ key: ContentKey, pack: String) -> TranslationText?
    /// Translation packages of a language; without a language all.
    func translations(language: String?) -> [PackManifest]
    func transliteration(_ key: ContentKey, language: String) -> Transliteration?
    /// Tajweed spans of a verse; empty without a tajweed package.
    func tajweed(_ key: ContentKey) -> [TajweedSpan]
    /// Verses with similar wording; empty without the package `benzer`.
    func similarVerses(_ key: ContentKey) -> [SimilarVerse]
    /// All Dualar (Quran duas) in order; empty without a dua package.
    func duas() -> [Dua]
    /// The 99 names; empty without an Esma package.
    func divineNames() -> [DivineName]
    /// Verses in which an Arabic word occurs (word search, Esmâ page).
    func versesContainingWord(_ arabic: String) -> [ContentKey]
    /// Tafsir for a verse in the language `language` (otherwise English); empty without a package.
    func tafsir(_ key: ContentKey, language: String) -> [TafsirText]
    /// Tafsir packages of a language.
    func tafsirs(language: String) -> [PackManifest]
    /// Hadith categories under `parent` (nil = top level).
    func hadithCategories(language: String, parent: Int?) -> [HadithCategory]
    /// Hadiths of a category (including subcategories), only header and grade.
    func hadiths(category: Int, language: String) -> [Hadith]
    /// A hadith in `language`, otherwise English, otherwise Turkish.
    func hadith(_ identifier: Int, language: String) -> Hadith?
    /// Hadiths whose explanation refers to this verse.
    func verseHadiths(_ key: ContentKey, language: String) -> [Hadith]
    /// Verses a hadith refers to.
    func hadithVerses(_ identifier: Int) -> [ContentKey]
    /// The next (or with `rest` the previous) verse a hadith refers to.
    func nearbyVerseWithHadith(_ key: ContentKey, rest: Bool) -> ContentKey?
    /// Full-text search over translations, Okunuş, Dualar and Esma; „2:255“ jumps to the verse.
    /// `preferred`: packages whose hits should come first (the chosen translations).
    func search(_ text: String, preferred: [String], limit: Int) -> [SearchResult]
    /// Meaning search: verses of a translation that match the query in content, even without
    /// a shared word. Empty if `arama-vektor` is missing or the translation is not included.
    func searchMeaning(_ text: String, pack: String, limit: Int) -> [SearchResult]
    /// Whether a package is marked „ungeprüft“ (Hoca-Prüfung offen).
    func unreviewed(_ pack: String) -> Bool
    func page(_ number: Int) -> Chapter?
    func juz(_ number: Int) -> Chapter?
    /// The verse with sequential number `index` (1…6236) as key.
    func key(index: Int) -> ContentKey?
    var basmala: String { get }
    /// Hadiths with Turkish source reference and parent categories, for the quiz questions.
    func quizHadiths() -> [QuizHadithRecord]
}

extension ContentProvider {
    public func translations() -> [PackManifest] { translations(language: nil) }
}

extension ContentProvider {
    public func nearbyVerseWithHadith(_ key: ContentKey, rest: Bool) -> ContentKey? { nil }
    public func versesContainingWord(_ arabic: String) -> [ContentKey] { [] }

    /// Verses with similar wording, best first; empty without the package `benzer` (Store edition).
    public func similarVerses(_ key: ContentKey) -> [SimilarVerse] { [] }

    public func searchMeaning(_ text: String, pack: String, limit: Int) -> [SearchResult] { [] }

    public func quizHadiths() -> [QuizHadithRecord] { [] }
}

/// A hadith as the quiz generator needs it: identifier, Turkish source reference, short text and
/// the parent categories (top level of the hadith encyclopedia) it belongs to.
public struct QuizHadithRecord: Sendable, Hashable {
    public let identifier: Int
    public let source: String
    public let title: String
    public let parentCategories: Set<Int>

    public init(identifier: Int, source: String, title: String, parentCategories: Set<Int>) {
        self.identifier = identifier
        self.source = source
        self.title = title
        self.parentCategories = parentCategories
    }
}
