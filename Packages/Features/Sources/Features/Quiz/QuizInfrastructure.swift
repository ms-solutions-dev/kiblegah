import ContentPacks
import Core
import DesignSystem
import Foundation
import PrayerTimes
import SwiftUI
import Synchronization
import UserData

/// The question pool, built once per app run in the background (read all verses once, ~½ s).
actor QuizPoolStore {
    static let shared = QuizPoolStore()
    private var pool: QuizPool?
    private var loadTask: Task<QuizPool, Never>?

    func pool(_ contentProvider: any ContentProvider) async -> QuizPool {
        if let pool { return pool }
        let g =
            loadTask ?? Task.detached(priority: .userInitiated) { QuizPool(contentProvider: contentProvider) }
        loadTask = g
        let h = await g.value
        pool = h
        return h
    }
}

/// Additional question banks that an app target may plug in (``QuizBanks/source``); without a
/// source there are only the questions generated from the content packs.
public protocol QuizBankSource: Sendable {
    /// Banks and their questions (including unreviewed ones; rounds filter themselves).
    func status(refresh: Bool) async -> QuizBankStatus
}

/// Banks and questions as a ``QuizBankSource`` delivers them.
public struct QuizBankStatus: Sendable {
    public var banks: [QuizBank]
    public var questions: [BankQuestion]

    public init(banks: [QuizBank] = [], questions: [BankQuestion] = []) {
        self.banks = banks
        self.questions = questions
    }
}

/// The installed bank source, if any.
public enum QuizBanks {
    nonisolated(unsafe) public static var source: (any QuizBankSource)?
    /// From this many approved questions a bank becomes a tile.
    static let tileThreshold = 10

    public static func status(refresh: Bool = false) async -> QuizBankStatus {
        guard let source else { return QuizBankStatus() }
        let d = await source.status(refresh: refresh)
        QuizBankNames.configure(d.banks)
        return d
    }

    static func questions() async -> [BankQuestion] { await status().questions }
}

/// The names of the banks as the source reports them - for banks the catalog does not know yet.
enum QuizBankNames {
    private static let names = Mutex<[String: BankQuestion.LocalizedText]>([:])

    static func configure(_ banks: [QuizBank]) {
        names.withLock { a in for b in banks { a[b.bank] = b.name } }
    }

    static func name(_ bank: String) -> String? {
        let m = names.withLock { $0[bank] }?.text(translationLanguage())
        return m?.isEmpty == false ? m : nil
    }
}

extension QuizArea {
    var nameKey: String { "quiz.alan.\(rawValue)" }

    /// Catalog first (short names for the tiles), then the name from the source, finally the identifier.
    public var name: String {
        let yok = "\u{1}"
        let k = localized(key: nameKey, fallback: yok)
        if k != yok { return k }
        return QuizBankNames.name(rawValue) ?? rawValue.capitalized
    }

    public var icon: String {
        switch self {
        case .quran: "book"
        case .translation: "text.quote"
        case .divineName: "sparkles"
        case .hadith: "text.book.closed"
        case .dua: "hands.and.sparkles"
        case .ilmihal: "drop"
        case QuizArea(bank: "siyer"): "map"
        case QuizArea(bank: "sahabe"): "person.3"
        case QuizArea(bank: "peygamber"): "scroll"
        default: "books.vertical"
        }
    }

    public var ton: CategoryTone {
        switch self {
        case .quran: .sage
        case .translation: .turquoise
        case .divineName: .saffron
        case .hadith: .sea
        case .dua: .clay
        case .ilmihal: .purple
        case QuizArea(bank: "siyer"): .olive
        case QuizArea(bank: "sahabe"): .rose
        case QuizArea(bank: "peygamber"): .saffron
        default: .neutral
        }
    }
}

/// Which areas the quiz section shows as tiles and how many bank questions are waiting for review.
struct QuizAreas {
    var areas: [QuizArea] = QuizArea.generated
    /// Unreviewed questions of all banks (0 without a bank source).
    var pending = 0

    /// Generator areas that ship with the loaded bundles, then each bank with at least
    /// ``QuizBanks/tileThreshold`` approved questions in the order of the source.
    static func load(contentProvider: any ContentProvider) async -> QuizAreas {
        let h = await QuizPoolStore.shared.pool(contentProvider)
        let d = await QuizBanks.status()
        let numbers = Dictionary(grouping: d.questions.filter(\.available), by: \.bank).mapValues(\.count)
        let banks = (d.banks.map(\.bank) + numbers.keys.sorted()).reduce(into: [String]()) {
            if !$0.contains($1) { $0.append($1) }
        }
        return QuizAreas(
            areas: QuizArea.generated.filter { h.areas.contains($0) }
                + banks.filter { (numbers[$0] ?? 0) >= QuizBanks.tileThreshold }.map {
                    QuizArea(bank: $0)
                },
            pending: d.questions.filter(\.isPending).count)
    }
}

extension QuizScoring.Tier {
    var name: String { localized(key: "quiz.kademe.\(rawValue)") }
}

/// The calendar day of the device and its day number (like the daily question on the start page).
enum QuizDay {
    static func today(_ time: Date = .now) -> Day { Day(time, timeZoneIdentifier: .current) }

    static func dayNumber(_ g: Day) -> Int {
        Int((g.start(.gmt).timeIntervalSince1970 / 86400).rounded(.down))
    }
}

/// Assembles questions, options and citations in the app language. Everything comes from the bundles or
/// the reviewed bank; nothing is worded here that could be read as a religious statement.
public struct QuizText {
    let contentProvider: any ContentProvider
    let bank: [BankQuestion]

    public init(contentProvider: any ContentProvider, bank: [BankQuestion]) {
        self.contentProvider = contentProvider
        self.bank = bank
    }
    var language: String { translationLanguage() }

    func bankQuestion(_ bank: String, _ id: String) -> BankQuestion? {
        self.bank.first { $0.bank == bank && $0.id == id }
    }

    /// The bank question behind a quiz question (header line, options, citation).
    func bankQuestion(_ s: QuizQuestion) -> BankQuestion? {
        guard case .bank(let b, let id) = s.topic else { return nil }
        return bankQuestion(b, id)
    }

    /// The question itself (heading of the card).
    func title(_ s: QuizQuestion) -> String {
        switch (s.kind, s.dayKind, s.topic) {
        case (.translationSurah, _, _), (.questionOfTheDay, .verseSurah?, _):
            return localized("bugun.soru.ayet_suresi")
        case (.verseCount, _, .surah(let n)), (.questionOfTheDay, .verseCount?, .surah(let n)):
            return localized("bugun.soru.ayet_sayisi \(surahName(n))")
        case (.medinanSurah, _, _), (.questionOfTheDay, .medinanSurah?, _):
            return localized("bugun.soru.medeni")
        case (.meccanSurah, _, _): return localized("quiz.soru.mekki")
        case (.firstRevealed, _, _), (.questionOfTheDay, .firstRevealed?, _):
            return localized("bugun.soru.ilk_nazil")
        case (.divineNameMeaning, _, .divineName(let n)),
            (.questionOfTheDay, .divineNameMeaning?, .divineName(let n)):
            return localized("bugun.soru.esma \(divineNameLabel(n))")
        case (.meaningDivineName, _, _): return localized("quiz.soru.anlam_esma")
        case (.surahJuz, _, .surah(let n)): return localized("quiz.soru.cuz \(surahName(n))")
        case (.wordGap, _, _): return localized("quiz.soru.kelime")
        case (.hadithCollection, _, _): return localized("quiz.soru.koleksiyon")
        case (.hadithCategory, _, _): return localized("quiz.soru.hadis_kategori")
        case (.duaCategory, _, _): return localized("quiz.soru.dua_kategori")
        case (.duaSurah, _, _): return localized("quiz.soru.dua_sure")
        case (.bank, _, .bank(let b, let id)):
            return bankQuestion(b, id)?.text.text(language) ?? ""
        default: return ""
        }
    }

    /// Text of an option.
    func option(_ o: QuizOption, question s: QuizQuestion) -> String {
        switch o {
        case .surah(let n): return surahName(n)
        case .number(let n): return n.formatted(.number.locale(AppLanguage.locale))
        case .juz(let n): return localized("quiz.cuz \(n)")
        case .divineNameMeaning(let n): return divineName(n)?.meaning(language) ?? ""
        case .divineNameLabel(let n): return divineNameLabel(n)
        case .collection(let k): return localized(key: "quiz.koleksiyon.\(k.rawValue)")
        case .hadithCategory(let id):
            return contentProvider.hadithCategories(language: language, parent: nil).first { $0.id == id }?
                .name ?? "\(id)"
        case .duaCategory(let k): return categoryName(k)
        case .word(let a): return contentProvider.words(a).first?.text ?? ""
        case .correct: return localized("quiz.dogru")
        case .wrong: return localized("quiz.yanlis")
        case .text(let i):
            let l = bankQuestion(s)?.options?.list(language) ?? []
            return l.indices.contains(i) ? l[i] : ""
        }
    }

    func surahName(_ n: Int) -> String { contentProvider.surah(n)?.name(language: language) ?? "\(n)" }

    func divineName(_ n: Int) -> DivineName? { contentProvider.divineNames().first { $0.number == n } }

    /// In Turkish the reading according to Diyanet („er-Rahmân“), otherwise the transliteration.
    func divineNameLabel(_ n: Int) -> String {
        guard let e = divineName(n) else { return "" }
        return language == "tr" ? (e.transliterationTR ?? e.latin) : e.latin
    }

    func translationText(_ a: ContentKey) -> (text: String, pack: String)? {
        guard let p = contentProvider.translations(language: language).first,
            let m = contentProvider.translation(a, pack: p.id)
        else {
            return nil
        }
        return (m.text, p.title)
    }

    /// Wording of a Quran dua (Arabic) and its translation (whole verses).
    func dua(_ slug: String) -> (arabic: String, translation: String, dua: Dua)? {
        guard let d = contentProvider.duas().first(where: { $0.slug == slug }) else { return nil }
        let verses = contentProvider.verses(d.source)
        var words: [String] = []
        for (i, a) in verses.enumerated() {
            let first = i == 0 ? max(1, d.firstWord) : 1
            let end = i == verses.count - 1 && d.lastWord > 0 ? d.lastWord : a.words.count
            guard first <= end else { continue }
            words += a.words.dropFirst(first - 1).prefix(end - first + 1).map(\.text)
        }
        let translation = verses.compactMap { translationText($0.key)?.text }.joined(separator: " ")
        return (words.joined(separator: " "), translation, d)
    }

    /// The citation strip: short excerpt, source line, jump target; for bank questions with a second
    /// source (`second`: quotation and work/volume/page or translation verse).
    func citation(
        _ s: QuizQuestion
    ) -> (
        excerpt: String, arabic: String, source: String, goal: Goal?, mapButton: String,
        second: (excerpt: String, source: String)?
    ) {
        switch s.source {
        case .verse(let a):
            guard case .verse(let su, let n) = a else { return ("", "", a.text, nil, "", nil) }
            let m = translationText(a)
            var place = "\(surahName(su)) \(su):\(n)"
            if let m { place += " · \(m.pack)" }
            if s.kind == .medinanSurah || s.kind == .meccanSurah || s.kind == .firstRevealed
                || s.dayKind == .medinanSurah || s.dayKind == .firstRevealed
            {
                place = "\(localized("bugun.soru.kaynak.tanzil")) · \(place)"
            }
            let arabic = contentProvider.verse(a)?.text ?? ""
            return (m?.text ?? "", arabic, place, .verse(a), localized("quiz.ac.ayet"), nil)
        case .divineName(let n):
            let e = divineName(n)
            let place = [localized("sekme.esma"), divineNameLabel(n), e?.source ?? ""].filter { !$0.isEmpty }
                .joined(separator: " · ")
            return (
                e?.meaning(language) ?? "", e?.arabic ?? "", place, .divineNameDetail(n),
                localized("quiz.ac.esma"), nil
            )
        case .hadith(let n):
            guard let h = contentProvider.hadith(n, language: language) else {
                return ("", "", "", .hadithDetail(n), localized("quiz.ac.hadis"), nil)
            }
            let place = [h.source, h.degrees, "HadeethEnc #\(n)"].filter { !$0.isEmpty }.joined(
                separator: " · ")
            return (h.title, "", place, .hadithDetail(n), localized("quiz.ac.hadis"), nil)
        case .dua(let slug):
            guard let d = dua(slug) else { return ("", "", "", .dua(slug), localized("quiz.ac.dua"), nil) }
            let place =
                "\(surahName(d.dua.surah)) \(d.dua.source.text.dropFirst(2)) · \(categoryName(d.dua.category))"
            return (d.translation, d.arabic, place, .dua(slug), localized("quiz.ac.dua"), nil)
        case .bank(let bank, let id):
            let q = bankQuestion(bank, id)
            let b2 = q?.citation2
            // A translation verse as second source gets the jump into the verse.
            let goal = b2?.verseKey.map { Goal.verse($0) }
            let second = b2.map { (excerpt: $0.excerpt ?? "", source: citationPlace($0)) }
            return (
                q?.citation?.excerpt ?? "", "", q?.citation.map(citationPlace) ?? "", goal,
                goal == nil ? "" : localized("quiz.ac.ayet"), second
            )
        }
    }

    /// „Hayâtü's-Sahâbe · c. 4 · s. 562“, for a translation „Diyanet Meali · Bakara 2:34“.
    public func citationPlace(_ b: BankQuestion.Citation) -> String {
        let (name, multiVolume) = workName(b)
        if let a = b.verseKey, case .verse(let su, let n) = a {
            return [name, "\(surahName(su)) \(su):\(n)"].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        return [
            name, multiVolume ? "" : b.volume.map { localized("quiz.cilt \($0)") } ?? "",
            b.page.map { localized("quiz.sayfa \($0)") } ?? "",
        ].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Work title from the catalog: first the whole key (`ilmihal1` → „Diyanet İlmihal I“, volume
    /// in the title), otherwise the work without volume (`hisam2` → „İbn Hişâm, Sîret“), otherwise the identifier.
    func workName(_ b: BankQuestion.Citation) -> (name: String, multiVolume: Bool) {
        guard let work = b.work else { return ("", false) }
        let yok = "\u{1}"
        let tam = localized(key: "quiz.eser.\(work)", fallback: yok)
        if tam != yok { return (tam, true) }
        return (localized(key: "quiz.eser.\(b.workName ?? work)", fallback: work), false)
    }
}
