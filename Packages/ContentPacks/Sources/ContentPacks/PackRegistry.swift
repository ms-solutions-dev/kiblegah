import Core
import Foundation

/// `ContentProvider` over the packages in one or more folders (app bundle, downloads).
///
/// Packages with a text version load only if it matches the Quran text – otherwise
/// tajweed colors or word boundaries would sit next to the text. Rejected packages
/// are listed in `rejected` so that Ayarlar can name them.
public final class PackRegistry: ContentProvider {
    public static let mushaf = "medine-604"

    private let quran: ContentPack
    private let others: [String: ContentPack]
    public let packs: [PackManifest]
    public let rejected: [PackManifest]
    public let basmala: String
    private let surahList: [Surah]
    private let pages: [Chapter]
    private let juzs: [Chapter]
    private let meaning: MeaningSearch?

    /// - Parameters:
    ///   - klasorler: folders whose subfolders are one package each. Later ones win on the same ID.
    ///   - store: `true` loads no packages with `store_tauglich: false`.
    public init(folders: [URL], store: Bool = false) throws(ContentPackError) {
        var all: [String: ContentPack] = [:]
        let fm = FileManager.default
        for folder in folders {
            let content = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for bottom in content.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            where fm.fileExists(atPath: bottom.appending(path: "manifest.json").path(percentEncoded: false)) {
                if let p = try? ContentPack(folder: bottom) { all[p.manifest.id] = p }
            }
        }
        guard let quran = all.removeValue(forKey: "kuran-text") else { throw .quranMissing }
        self.quran = quran
        var accepted: [String: ContentPack] = [:]
        var rejectedPacks: [PackManifest] = []
        for (id, p) in all {
            let textMatches =
                p.manifest.textVersion == nil || p.manifest.textVersion == quran.manifest.textVersion
            if textMatches && (!store || p.manifest.storeEligible) {
                accepted[id] = p
            } else {
                rejectedPacks.append(p.manifest)
            }
        }
        others = accepted
        meaning = accepted["arama-vektor"].map { MeaningSearch(db: $0.db) }
        packs = ([quran.manifest] + accepted.values.map(\.manifest)).sorted { $0.id < $1.id }
        rejected = rejectedPacks.sorted { $0.id < $1.id }
        basmala = quran.db.first("SELECT deger FROM bilgi WHERE anahtar='besmele'") { $0.text(0) } ?? ""
        surahList = quran.db.query(
            """
            SELECT no, ayet_sayisi, ilk_sira, ad_ar, ad_tr, ad_latin, anlam_en, inis, nuzul_sirasi, besmele
            FROM sure ORDER BY no
            """
        ) { s in
            Surah(
                number: s.integer(0), verseCount: s.integer(1), firstIndex: s.integer(2),
                nameArabic: s.text(3),
                nameTurkish: s.text(4), nameLatin: s.text(5), meaningEnglish: s.text(6),
                revelationPlace: Surah.RevelationPlace(rawValue: s.text(7)) ?? .meccan,
                revelationOrder: s.integer(8), basmala: s.integer(9) == 1
            )
        }
        pages = quran.db.query(
            "SELECT no, ilk_sira, son_sira FROM sayfa WHERE mushaf = ? ORDER BY no", [.text(Self.mushaf)]
        ) { Chapter(number: $0.integer(0), firstIndex: $0.integer(1), lastIndex: $0.integer(2)) }
        juzs = quran.db.query("SELECT no, ilk_sira, son_sira FROM cuz ORDER BY no") {
            Chapter(number: $0.integer(0), firstIndex: $0.integer(1), lastIndex: $0.integer(2))
        }
    }

    // MARK: Surah

    public func surahs() -> [Surah] { surahList }

    public func surah(_ number: Int) -> Surah? {
        surahList.indices.contains(number - 1) ? surahList[number - 1] : nil
    }

    public func key(index: Int) -> ContentKey? {
        guard (1...6236).contains(index) else { return nil }
        // The surahs are sorted by ilkSira: the last one with ilkSira ≤ sira.
        var bottom = 0
        var parent = surahList.count - 1
        while bottom < parent {
            let intermediate = (bottom + parent + 1) / 2
            if surahList[intermediate].firstIndex <= index {
                bottom = intermediate
            } else {
                parent = intermediate - 1
            }
        }
        let s = surahList[bottom]
        return .verse(surah: s.number, verse: index - s.firstIndex + 1)
    }

    /// Verses in which the word `arabic` occurs (Esmâ page); the basmala prefix does not count.
    public func versesContainingWord(_ arabic: String) -> [ContentKey] {
        let h = WordSearch.goal(arabic)
        guard !h.isEmpty else { return [] }
        return quran.db.query("SELECT sure, ayet, metin, besmele_son FROM ayet ORDER BY sira") { r in
            (r.integer(0), r.integer(1), r.text(2), r.integer(3))
        }.compactMap { s, a, m, b in
            let body = b > 0 ? String(String.UnicodeScalarView(m.unicodeScalars.dropFirst(b))) : m
            return WordSearch.occurs(h, verse: body) ? .verse(surah: s, verse: a) : nil
        }
    }

    // MARK: Verse

    public func verse(_ key: ContentKey) -> Verse? {
        guard case .verse(let s, let a) = key, let index = index(surah: s, verse: a) else { return nil }
        return verses(first: index, end: index).first
    }

    public func verses(_ key: ContentKey) -> [Verse] {
        switch key {
        case .verse, .word:
            guard case .some(let k) = verseKey(key), let a = verse(k) else { return [] }
            return [a]
        case .verseRange(let s, let first, let end):
            guard let su = surah(s), first <= su.verseCount else { return [] }
            return verses(first: su.firstIndex + first - 1, end: su.firstIndex + min(end, su.verseCount) - 1)
        case .surah(let s):
            guard let su = surah(s) else { return [] }
            return verses(first: su.firstIndex, end: su.firstIndex + su.verseCount - 1)
        case .page(let n):
            guard let b = page(n) else { return [] }
            return verses(first: b.firstIndex, end: b.lastIndex)
        case .juz(let n):
            guard let b = juz(n) else { return [] }
            return verses(first: b.firstIndex, end: b.lastIndex)
        default:
            return []
        }
    }

    public func words(_ key: ContentKey) -> [Word] {
        switch key {
        case .word(let s, let a, _):
            return verse(.verse(surah: s, verse: a))?.words.filter { $0.key == key } ?? []
        default:
            return verses(key).flatMap(\.words)
        }
    }

    public func page(_ number: Int) -> Chapter? {
        pages.indices.contains(number - 1) ? pages[number - 1] : nil
    }

    public func juz(_ number: Int) -> Chapter? { juzs.indices.contains(number - 1) ? juzs[number - 1] : nil }

    // MARK: Translation and transliteration

    public func translations(language: String?) -> [PackManifest] {
        packs.filter { $0.kind == "meal" && (language == nil || $0.language == language) }
    }

    public func translation(_ key: ContentKey, pack: String) -> TranslationText? {
        guard case .verse(let s, let a) = verseKey(key), let p = others[pack],
            p.manifest.kind == "meal"
        else { return nil }
        return p.db.first(
            "SELECT metin, dipnot FROM meal WHERE sure = ? AND ayet = ?", [.integer(s), .integer(a)]
        ) {
            TranslationText(pack: pack, rawText: $0.text(0), footnote: $0.optionalText(1))
        }
    }

    public func transliteration(_ key: ContentKey, language: String) -> Transliteration? {
        guard case .verse(let s, let a) = verseKey(key), let p = others["okunus-\(language)"] else {
            return nil
        }
        guard
            let row = p.db.first(
                "SELECT metin FROM okunus WHERE sure = ? AND ayet = ?", [.integer(s), .integer(a)],
                row: { $0.text(0) })
        else { return nil }
        let single = p.db.query(
            "SELECT metin FROM kelime_okunus WHERE sure = ? AND ayet = ? ORDER BY sira",
            [.integer(s), .integer(a)]
        ) { $0.text(0) }
        return Transliteration(text: row, words: single)
    }

    public func similarVerses(_ key: ContentKey) -> [SimilarVerse] {
        guard case .verse(let s, let a) = verseKey(key), let p = others["benzer"] else {
            return []
        }
        return p.db.query(
            "SELECT hedef_sure, hedef_ayet, kelime, kapsam, puan, aralik FROM benzer "
                + "WHERE sure = ? AND ayet = ? ORDER BY puan DESC, kelime DESC", [.integer(s), .integer(a)]
        ) { r in
            let ar = (try? JSONDecoder().decode([[Int]].self, from: Data(r.text(5).utf8))) ?? []
            return SimilarVerse(
                goal: .verse(surah: r.integer(0), verse: r.integer(1)), word: r.integer(2),
                scope: r.integer(3),
                score: r.integer(4),
                words: ar.compactMap { $0.count == 2 && $0[0] <= $0[1] ? $0[0]...$0[1] : nil })
        }
    }

    public func tajweed(_ key: ContentKey) -> [TajweedSpan] {
        guard case .verse(let s, let a) = verseKey(key), let p = others["tecvid"],
            let verse = verse(.verse(surah: s, verse: a))
        else { return [] }
        let offset = verse.basmalaEnd
        return p.db.query(
            "SELECT kural, bas, son FROM tecvid WHERE sure = ? AND ayet = ? ORDER BY bas",
            [.integer(s), .integer(a)]
        ) { r in TajweedSpan(rule: r.text(0), interval: (r.integer(1) - offset)..<(r.integer(2) - offset)) }
        .filter { $0.interval.lowerBound >= 0 }
    }

    public func duas() -> [Dua] {
        guard let p = others["dualar"] else { return [] }
        return p.db.query(
            "SELECT slug, kategori, sure, ilk, son, ilk_kelime, sira, son_kelime FROM dua ORDER BY sira"
        ) { r in
            Dua(
                slug: r.text(0), category: r.text(1), surah: r.integer(2), first: r.integer(3),
                end: r.integer(4),
                firstWord: r.integer(5), lastWord: r.integer(7),
                index: r.integer(6))
        }
    }

    public func divineNames() -> [DivineName] {
        guard let p = others["esma"] else { return [] }
        var names = p.db.query(
            "SELECT no, arapca, latin, okunus_tr, anlam_tr, anlam_de, anlam_en, kaynak_ayet FROM esma ORDER BY no"
        ) { r in
            DivineName(
                number: r.integer(0), arabic: r.text(1), latin: r.text(2),
                transliterationTR: r.optionalText(3),
                meaningTR: r.optionalText(4),
                meaningDE: r.optionalText(5), meaningEN: r.optionalText(6), source: r.optionalText(7))
        }
        Self.pairNames(&names)
        return names
    }

    /// Gives every name of ``DivineName/namedWithPartner`` its partner, so that no screen shows it alone.
    static func pairNames(_ names: inout [DivineName]) {
        for (n, m) in DivineName.namedWithPartner {
            guard let i = names.firstIndex(where: { $0.number == n }),
                let partner = names.first(where: { $0.number == m })
            else { continue }
            names[i].partnerStorage = [partner]
        }
    }

    public func search(_ text: String, preferred: [String], limit: Int = 50) -> [SearchResult] {
        var result: [SearchResult] = []
        let numbers = text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        if numbers.count >= 2, text.contains(where: { ":. ".contains($0) }),
            let a = verse(.verse(surah: numbers[0], verse: numbers[1]))
        {
            result.append(SearchResult(key: a.key, kind: .verse, pack: "kuran-text", text: a.text))
        }
        guard let p = others["arama"], let queryText = Self.ftsQuery(text) else { return result }
        let rawRows = p.db.query(
            "SELECT anahtar, tur, paket FROM belge WHERE belge MATCH ? ORDER BY bm25(belge, 0, 0, 0, 2.0, 1.0) LIMIT 400",
            [.text(queryText)]
        ) { r in (r.text(0), r.text(1), r.text(2)) }
        // Preferred packs first, only one hit per key and kind.
        let ordered = rawRows.enumerated().sorted { x, y in
            let tx = preferred.contains(x.element.2) || x.element.2 == "esma"
            let ty = preferred.contains(y.element.2) || y.element.2 == "esma"
            return tx != ty ? tx : x.offset < y.offset
        }
        var seenItems = Set<String>()
        for (_, (a, t, pk)) in ordered where result.count < limit {
            guard let key = ContentKey(text: a), let kind = SearchResult.Kind(rawValue: t) else { continue }
            guard seenItems.insert("\(a)|\(t)").inserted else { continue }
            if let m = original(key, kind: kind, pack: pk) {
                result.append(SearchResult(key: key, kind: kind, pack: pk, text: m))
            }
        }
        return result
    }

    /// Folded words → FTS5 query: per word a prefix in the text or in the consonant skeleton.
    static func ftsQuery(_ text: String) -> String? {
        let words = TurkishText.searchForm(text).split(separator: " ").map(String.init)
            .map { $0.filter { $0.isLetter || $0.isNumber } }.filter { $0.count >= 2 }
        guard !words.isEmpty else { return nil }
        return words.map { k in
            let skeleton = k.filter { $0.isLetter && !"aeiou".contains($0) }
            if skeleton.count >= 3 {
                return "(katli: \"\(k)\"* OR iskelet: \"\(skeleton)\"*)"
            }
            return "katli: \"\(k)\"*"
        }.joined(separator: " AND ")
    }

    private func original(_ a: ContentKey, kind: SearchResult.Kind, pack: String) -> String? {
        switch kind {
        case .translation: return translation(a, pack: pack)?.text
        case .transliteration:
            return transliteration(a, language: pack.replacingOccurrences(of: "okunus-", with: ""))?.text
        case .divineName:
            guard case .divineName(let n) = a, let e = divineNames().first(where: { $0.number == n }) else {
                return nil
            }
            // ed-Dârr only together with en-Nâfi‘ (``DivineName/namedWithPartner``).
            return ([e] + (e.partner.map { [$0] } ?? [])).flatMap {
                [$0.transliterationTR ?? $0.latin, $0.meaningTR, $0.meaningDE, $0.meaningEN].compactMap { $0 }
            }
            .joined(separator: " · ")
        case .dua:
            guard case .dua(let slug) = a, let d = duas().first(where: { $0.slug == slug }) else {
                return nil
            }
            return (d.first...d.end).compactMap {
                translation(.verse(surah: d.surah, verse: $0), pack: pack)?.text
            }
            .joined(separator: " ")
        case .hadith:
            guard case .hadith(_, let n) = a,
                let h = hadith(n, language: String(pack.dropFirst("hadis-".count)))
            else {
                return nil
            }
            return "\(h.title) — \(h.text)"
        case .verse: return verse(a)?.text
        }
    }

    public func tafsirs(language: String) -> [PackManifest] {
        packs.filter { $0.kind == "tefsir" && $0.language == language }
    }

    public func tafsir(_ key: ContentKey, language: String) -> [TafsirText] {
        guard case .verse(let s, let a) = verseKey(key) else { return [] }
        let packs =
            tafsirs(language: language).isEmpty ? tafsirs(language: "en") : tafsirs(language: language)
        return packs.flatMap { m -> [TafsirText] in
            guard let p = others[m.id] else { return [] }
            return p.db.query(
                "SELECT ilk, son, metin FROM tefsir WHERE sure = ? AND ilk <= ? AND son >= ? ORDER BY ilk",
                [.integer(s), .integer(a), .integer(a)]
            ) { TafsirText(pack: m.id, surah: s, first: $0.integer(0), end: $0.integer(1), text: $0.text(2)) }
        }
    }

    private var hadithPack: ContentPack? { others["hadis"] }

    private func hadithLanguage(_ language: String) -> [String] {
        Array(NSOrderedSet(array: [language, "en", "tr"])) as? [String] ?? [language]
    }

    private static let hadithColumns =
        "kimlik, dil, baslik, metin, kaynak, derece, aciklama, faydalar, arapca"

    private static func hadithRow(_ r: Row) -> Hadith {
        let benefits = (try? JSONDecoder().decode([String].self, from: Data(r.text(7).utf8))) ?? []
        return Hadith(
            identifier: r.integer(0), language: r.text(1), title: r.text(2), text: r.text(3),
            source: r.text(4),
            degrees: r.text(5), explanation: r.text(6), benefits: benefits, arabic: r.text(8))
    }

    public func hadithCategories(language: String, parent: Int?) -> [HadithCategory] {
        guard let p = hadithPack else { return [] }
        let d =
            hadithLanguage(language).first { d in
                (p.db.first("SELECT count(*) FROM kategori WHERE dil = ?", [.text(d)]) { $0.integer(0) } ?? 0)
                    > 0
            } ?? "en"
        let sql =
            parent == nil
            ? "SELECT id, ad, ust, adet FROM kategori WHERE dil = ? AND ust IS NULL ORDER BY id"
            : "SELECT id, ad, ust, adet FROM kategori WHERE dil = ? AND ust = ? ORDER BY id"
        let values: [Value] = parent.map { [.text(d), .integer($0)] } ?? [.text(d)]
        return p.db.query(sql, values) { r in
            HadithCategory(
                id: r.integer(0), name: r.text(1), parent: r.optionalText(2).flatMap(Int.init),
                count: r.integer(3)
            )
        }
    }

    public func hadiths(category: Int, language: String) -> [Hadith] {
        guard let p = hadithPack else { return [] }
        for d in hadithLanguage(language) {
            let l = p.db.query(
                "SELECT \(Self.hadithColumns) FROM hadis WHERE dil = ? AND (',' || kategoriler || ',') LIKE ? ORDER BY kimlik",
                [.text(d), .text("%,\(category),%")], row: Self.hadithRow)
            if !l.isEmpty { return l }
        }
        return []
    }

    public func hadith(_ identifier: Int, language: String) -> Hadith? {
        guard let p = hadithPack else { return nil }
        for d in hadithLanguage(language) {
            if let h = p.db.first(
                "SELECT \(Self.hadithColumns) FROM hadis WHERE kimlik = ? AND dil = ?",
                [.integer(identifier), .text(d)],
                row: Self.hadithRow)
            {
                return h
            }
        }
        return nil
    }

    public func verseHadiths(_ key: ContentKey, language: String) -> [Hadith] {
        guard case .verse(let s, let a) = verseKey(key), let p = hadithPack else { return [] }
        let ids = p.db.query(
            "SELECT DISTINCT hadis FROM bag WHERE sure = ? AND ilk <= ? AND son >= ? ORDER BY hadis",
            [.integer(s), .integer(a), .integer(a)]
        ) { $0.integer(0) }
        return ids.compactMap { hadith($0, language: language) }
    }

    public func nearbyVerseWithHadith(_ key: ContentKey, rest: Bool) -> ContentKey? {
        guard case .verse(let s, let a) = verseKey(key), let p = hadithPack else { return nil }
        let sql =
            rest
            ? "SELECT sure, ilk FROM bag WHERE sure < ? OR (sure = ? AND ilk < ?) ORDER BY sure DESC, ilk DESC LIMIT 1"
            : "SELECT sure, ilk FROM bag WHERE sure > ? OR (sure = ? AND ilk > ?) ORDER BY sure, ilk LIMIT 1"
        return p.db.first(sql, [.integer(s), .integer(s), .integer(a)]) {
            ContentKey.verse(surah: $0.integer(0), verse: $0.integer(1))
        }
    }

    public func hadithVerses(_ identifier: Int) -> [ContentKey] {
        guard let p = hadithPack else { return [] }
        return p.db.query(
            "SELECT sure, ilk, son FROM bag WHERE hadis = ? ORDER BY sure, ilk", [.integer(identifier)]
        ) { r in
            r.integer(1) == r.integer(2)
                ? ContentKey.verse(surah: r.integer(0), verse: r.integer(1))
                : ContentKey.verseRange(surah: r.integer(0), first: r.integer(1), end: r.integer(2))
        }
    }

    public func searchMeaning(_ text: String, pack: String, limit: Int) -> [SearchResult] {
        guard let meaning, text.trimmingCharacters(in: .whitespaces).count >= 3 else { return [] }
        return meaning.search(text, pack: pack, limit: limit).compactMap { a, _ in
            translation(a, pack: pack).map {
                SearchResult(key: a, kind: .translation, pack: pack, text: $0.text)
            }
        }
    }

    func meaningTokenize(_ text: String) -> [String] { meaning?.tokenize(text) ?? [] }

    public func quizHadiths() -> [QuizHadithRecord] {
        guard let p = hadithPack else { return [] }
        var parent: [Int: Int?] = [:]
        _ = p.db.query("SELECT id, ust FROM kategori WHERE dil = 'tr'") { r -> Int in
            parent.updateValue(r.optionalText(1).flatMap { Int($0) }, forKey: r.integer(0))
            return 0
        }
        /// The top level above a category; loops in the tree stop after 20 steps.
        func stem(_ id: Int) -> Int? {
            var k = id
            for _ in 0..<20 {
                guard let u = parent[k] else { return nil }
                guard let parent = u else { return k }
                k = parent
            }
            return nil
        }
        return p.db.query(
            "SELECT kimlik, kaynak, baslik, kategoriler FROM hadis WHERE dil = 'tr' ORDER BY kimlik"
        ) {
            r in
            let categories = r.text(3).split(separator: ",").compactMap {
                Int($0.trimmingCharacters(in: .whitespaces))
            }
            return QuizHadithRecord(
                identifier: r.integer(0), source: r.text(1), title: r.text(2),
                parentCategories: Set(categories.compactMap(stem)))
        }
    }

    public func unreviewed(_ pack: String) -> Bool {
        packs.first { $0.id == pack }?.unreviewed ?? false
    }

    // MARK: Hilfen

    private func verseKey(_ key: ContentKey) -> ContentKey? {
        switch key {
        case .verse: key
        case .word(let s, let a, _): .verse(surah: s, verse: a)
        default: nil
        }
    }

    private func index(surah s: Int, verse a: Int) -> Int? {
        guard let su = surah(s), (1...su.verseCount).contains(a) else { return nil }
        return su.firstIndex + a - 1
    }

    private func pageNumber(index: Int) -> Int {
        var bottom = 0
        var parent = pages.count - 1
        while bottom < parent {
            let intermediate = (bottom + parent + 1) / 2
            if pages[intermediate].firstIndex <= index {
                bottom = intermediate
            } else {
                parent = intermediate - 1
            }
        }
        return pages.isEmpty ? 1 : pages[bottom].number
    }

    private func verses(first: Int, end: Int) -> [Verse] {
        guard first <= end else { return [] }
        var words: [Int: [Word]] = [:]
        _ = quran.db.query(
            """
            SELECT a.sira, k.sure, k.ayet, k.sira, k.metin, k.bas, k.son
            FROM ayet a JOIN kelime k ON k.sure = a.sure AND k.ayet = a.ayet
            WHERE a.sira BETWEEN ? AND ? ORDER BY a.sira, k.sira
            """, [.integer(first), .integer(end)]
        ) { s -> Int in
            let index = s.integer(0)
            words[index, default: []].append(
                Word(
                    key: .word(surah: s.integer(1), verse: s.integer(2), index: s.integer(3)),
                    text: s.text(4),
                    interval: s.integer(5)..<s.integer(6)))
            return index
        }
        return quran.db.query(
            """
            SELECT sira, sure, ayet, metin, besmele_son, cuz, hizb_ceyrek, secde
            FROM ayet WHERE sira BETWEEN ? AND ? ORDER BY sira
            """, [.integer(first), .integer(end)]
        ) { s in
            let index = s.integer(0)
            return Verse(
                surah: s.integer(1), verse: s.integer(2), index: index, rawText: s.text(3),
                basmalaEnd: s.integer(4),
                words: words[index] ?? [], juz: s.integer(5), hizbQuarter: s.integer(6),
                page: pageNumber(index: index),
                sajdah: s.optionalText(7).flatMap(Verse.Sajdah.init(rawValue:)))
        }
    }
}
