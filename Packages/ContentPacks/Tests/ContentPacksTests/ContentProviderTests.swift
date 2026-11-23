import Core
import Foundation
import Testing

@testable import ContentPacks

/// Checks against the real packs from `App/Resources/Paketler` (built by tools/content/fetch.sh).
/// True when `App/Resources/Paketler/kuran-text/manifest.json` exists (built by tools/content/fetch.sh).
let contentPacksAvailable = FileManager.default.fileExists(
    atPath: URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "App/Resources/Paketler/kuran-text/manifest.json").path(percentEncoded: false))

/// True when `App/Resources/Paketler/hadis/manifest.json` exists (built by tools/content/fetch.sh).
let hadithPackAvailable = FileManager.default.fileExists(
    atPath: URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "App/Resources/Paketler/hadis/manifest.json").path(percentEncoded: false))

/// True when `App/Resources/Paketler/arama-vektor/manifest.json` exists (built by tools/content/fetch.sh).
let vectorPackAvailable = FileManager.default.fileExists(
    atPath: URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "App/Resources/Paketler/arama-vektor/manifest.json").path(percentEncoded: false))

/// True when `App/Resources/Paketler/benzer/manifest.json` exists (built by tools/content/fetch.sh).
let similarPackAvailable = FileManager.default.fileExists(
    atPath: URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "App/Resources/Paketler/benzer/manifest.json").path(percentEncoded: false))

@Suite(.enabled(if: contentPacksAvailable, "content packs missing: run tools/content/fetch.sh"))
struct ContentProviderTests {
    static let packs = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "App/Resources/Paketler")

    static let contentProvider: PackRegistry = {
        do { return try PackRegistry(folders: [packs]) } catch {
            fatalError("content packs missing: \(error)")
        }
    }()

    var contentProvider: PackRegistry { Self.contentProvider }

    /// Word search of the Esmâ page: ending, article and prefixes don't matter, short vowels do
    /// (مَلِك ≠ مُلْك), basmala prefix doesn't count.
    @Test func versesContainingWord() {
        let rauf = contentProvider.versesContainingWord("الرَّؤُوفُ")
        #expect(rauf.count == 11)
        #expect(rauf.contains(.verse(surah: 59, verse: 10)) && rauf.contains(.verse(surah: 9, verse: 128)))
        let malik = contentProvider.versesContainingWord("الْمَلِكُ")
        #expect(malik.contains(.verse(surah: 59, verse: 23)) && !malik.contains(.verse(surah: 67, verse: 1)))
        #expect(!contentProvider.versesContainingWord("ٱلرَّحْمَٰنُ").contains(.verse(surah: 2, verse: 1)))
        #expect(contentProvider.versesContainingWord("الصَّبُورُ").isEmpty)
        let allah = contentProvider.versesContainingWord("الله")
        #expect(
            allah.count > 1500 && allah.contains(.verse(surah: 1, verse: 2))
                && allah.contains(.verse(surah: 2, verse: 255)))
    }

    /// Same decomposition as the build tool (checked there with the full model: parity 1.000).
    @Test(.enabled(if: vectorPackAvailable, "semantic index (--no-vector) not built"))
    func meaningTokenization() {
        #expect(
            contentProvider.meaningTokenize("zor zamanlarda sabretmek") == [
                "▁zor", "▁zamanlarda", "▁sabre", "t", "mek",
            ])
        #expect(
            contentProvider.meaningTokenize("Besitz der Waisen") == ["▁Be", "sitz", "▁der", "▁Wa", "isen"])
    }

    /// Finds verses without a common word, e.g. "parents" verses via "kindness" and topic.
    @Test(.enabled(if: vectorPackAvailable, "semantic index (--no-vector) not built"))
    func meaningSearch() {
        let tr = contentProvider.searchMeaning("içki ve kumar", pack: "meal-tr-ozek", limit: 10).map(\.key)
        #expect(tr.contains(.verse(surah: 5, verse: 91)))
        let en = contentProvider.searchMeaning("kindness to parents", pack: "meal-en-saheeh", limit: 10).map(
            \.key)
        #expect(en.contains(.verse(surah: 31, verse: 14)))
        let de = contentProvider.searchMeaning("Besitz der Waisen", pack: "meal-de-bubenheim", limit: 10).map(
            \.key)
        #expect(de.contains(.verse(surah: 4, verse: 2)))
        #expect(contentProvider.searchMeaning("xy", pack: "meal-en-saheeh", limit: 10).isEmpty)
    }

    @Test(.enabled(if: hadithPackAvailable, "hadith pack (--no-hadith) not built"))
    func hadithAndVerseLink() throws {
        let h = try #require(contentProvider.verseHadiths(.verse(surah: 32, verse: 17), language: "tr").first)
        #expect(!h.source.isEmpty && !h.degrees.isEmpty)
        #expect(contentProvider.hadithVerses(h.identifier).contains(.verse(surah: 32, verse: 17)))
        #expect(contentProvider.hadith(h.identifier, language: "de") != nil)  // falls back to EN/TR
        #expect(!contentProvider.hadithCategories(language: "tr", parent: nil).isEmpty)
        // "next verse with hadith" skips verses without a reference and back
        let n = try #require(contentProvider.nearbyVerseWithHadith(.verse(surah: 32, verse: 17), rest: false))
        #expect(!contentProvider.verseHadiths(n, language: "tr").isEmpty)
        #expect(contentProvider.nearbyVerseWithHadith(n, rest: true) == .verse(surah: 32, verse: 17))
    }

    @Test func ayatAlKursiWithWords() throws {
        let a = try #require(contentProvider.verse(.verse(surah: 2, verse: 255)))
        #expect(a.words.count == 50)
        #expect(a.words.first?.key == .word(surah: 2, verse: 255, index: 1))
        #expect(a.page == 42)
        #expect(a.juz == 3)
        #expect(a.basmalaEnd == 0)
        // Word boundaries point into the unchanged text.
        let scalars = Array(a.rawText.unicodeScalars)
        for k in a.words {
            #expect(String(String.UnicodeScalarView(scalars[k.interval])) == k.text)
        }
    }

    @Test func translationInThreeLanguages() throws {
        for language in ["tr", "de", "en"] {
            let pack = try #require(contentProvider.translations(language: language).first)
            let m = try #require(contentProvider.translation(.verse(surah: 2, verse: 255), pack: pack.id))
            #expect(!m.text.isEmpty)
        }
        #expect(
            contentProvider.translation(.verse(surah: 2, verse: 255), pack: "meal-de-bubenheim")?.text
                .hasPrefix("Allah")
                == true)
        // QuranEnc verse numbers are removed.
        #expect(
            contentProvider.translation(.verse(surah: 1, verse: 1), pack: "meal-en-saheeh")?.text.hasPrefix(
                "In the name")
                == true)
    }

    @Test func underFiftyMilliseconds() {
        let time = ContinuousClock()
        let surah = time.measure {
            _ = contentProvider.verse(.verse(surah: 2, verse: 255))
            for p in ["meal-tr-ozek", "meal-de-bubenheim", "meal-en-saheeh"] {
                _ = contentProvider.translation(.verse(surah: 2, verse: 255), pack: p)
            }
        }
        #expect(surah < .milliseconds(50))
    }

    @Test func basmalaPrefix() throws {
        let fatiha = try #require(contentProvider.verse(.verse(surah: 1, verse: 1)))
        #expect(fatiha.basmalaEnd == 0 && fatiha.words.count == 4)
        let baqarah = try #require(contentProvider.verse(.verse(surah: 2, verse: 1)))
        #expect(baqarah.basmalaEnd > 0)
        #expect(baqarah.words.count == 1)
        let tawbah = try #require(contentProvider.verse(.verse(surah: 9, verse: 1)))
        #expect(tawbah.basmalaEnd == 0)
        #expect(contentProvider.surah(9)?.basmala == false)
        // 95 and 97 write the basmala with shadda; the verse still begins after four words.
        #expect(contentProvider.verse(.verse(surah: 97, verse: 1))?.words.count == 5)
    }

    @Test func areas() {
        #expect(contentProvider.verses(.verseRange(surah: 2, first: 8, end: 9)).map(\.verse) == [8, 9])
        #expect(contentProvider.verses(.verseRange(surah: 1, first: 6, end: 99)).map(\.verse) == [6, 7])
        #expect(contentProvider.verses(.surah(114)).count == 6)
        #expect(contentProvider.verses(.page(1)).count == 7)
        #expect(contentProvider.verses(.juz(30)).first?.key == .verse(surah: 78, verse: 1))
        #expect(contentProvider.verses(.verse(surah: 1, verse: 8)).isEmpty)
        #expect(contentProvider.verses(.dua("x")).isEmpty)
        #expect(contentProvider.words(.word(surah: 1, verse: 5, index: 2)).map(\.text) == ["نَعْبُدُ"])
    }

    @Test func orderAndKey() {
        #expect(contentProvider.key(index: 1) == .verse(surah: 1, verse: 1))
        #expect(contentProvider.key(index: 8) == .verse(surah: 2, verse: 1))
        #expect(contentProvider.key(index: 6236) == .verse(surah: 114, verse: 6))
        #expect(contentProvider.key(index: 0) == nil)
        #expect(contentProvider.surahs().count == 114)
        #expect(contentProvider.surah(2)?.nameTurkish == "Bakara")
    }

    /// QUL Similar Ayah: 1:2 "el-hamdu lillâhi rabbi'l-âlemîn" also appears verbatim in 37:182.
    @Test(.enabled(if: similarPackAvailable, "similar-verses pack (not public) not built"))
    func similarVerses() throws {
        let b = contentProvider.similarVerses(.verse(surah: 1, verse: 2))
        let first = try #require(b.first { $0.goal == .verse(surah: 37, verse: 182) })
        #expect(first.scope == 100 && first.words == [1...4])
        #expect(b.map(\.score) == b.map(\.score).sorted(by: >))
        #expect(contentProvider.similarVerses(.verse(surah: 114, verse: 6)).allSatisfy { $0.score > 0 })
    }

    @Test func tajweedOnTheVerse() throws {
        let a = try #require(contentProvider.verse(.verse(surah: 2, verse: 1)))
        let t = contentProvider.tajweed(a.key)
        // Alif-Lam-Mim: two medd-i lâzım on the verse itself, not on the basmala.
        #expect(t.map(\.rule) == ["madd_6", "madd_6"])
        let scalars = Array(a.text.unicodeScalars)
        #expect(t.allSatisfy { $0.interval.upperBound <= scalars.count })
        #expect(!contentProvider.tajweed(.verse(surah: 1, verse: 2)).isEmpty)
    }

    @Test func duasFromTheQuran() throws {
        let l = contentProvider.duas()
        #expect(l.count >= 50)
        let d = try #require(l.first { $0.slug == "2-201" })
        #expect(d.category == "rabbena" && d.firstWord == 4)
        #expect(d.key.text == "d:2-201")
        #expect(contentProvider.unreviewed("dualar"))
    }

    @Test func divineName() throws {
        let l = contentProvider.divineNames()
        #expect(l.count == 99)
        #expect(l.first?.latin == "Allāh")
        #expect(l[1].sourceVerse == .verse(surah: 1, verse: 1))
        #expect(l.filter { $0.meaning("tr") != nil }.count >= 97)
    }

    @Test func searchSabrAndKursi() throws {
        let time = ContinuousClock()
        var a: [SearchResult] = []
        let surah = time.measure {
            a = contentProvider.search("sabır", preferred: ["meal-tr-ozek"], limit: 50)
        }
        #expect(surah < .milliseconds(100), "\(surah)")
        #expect(a.contains { $0.key == .verse(surah: 2, verse: 153) })
        let b = contentProvider.search("sabir", preferred: ["meal-tr-ozek"], limit: 50)
        #expect(Set(b.map(\.key)) == Set(a.map(\.key)))
        #expect(
            contentProvider.search("2:255", preferred: [], limit: 5).first?.key
                == .verse(surah: 2, verse: 255))
        #expect(
            contentProvider.search("Geduld", preferred: ["meal-de-bubenheim"], limit: 10).contains {
                $0.pack == "meal-de-bubenheim"
            })
        #expect(
            contentProvider.search("Rahmân", preferred: [], limit: 10).contains { $0.key == .divineName(2) })
        #expect(contentProvider.search("x", preferred: [], limit: 10).isEmpty)
    }

    @Test func tafsirWithFallback() {
        #expect(
            contentProvider.tafsir(.verse(surah: 2, verse: 255), language: "tr").first?.pack
                == "tefsir-tr-muhtasar")
        #expect(
            contentProvider.tafsir(.verse(surah: 2, verse: 255), language: "de").first?.pack
                == "tefsir-en-muhtasar")
        #expect(
            contentProvider.tafsir(.verse(surah: 2, verse: 255), language: "en").first?.text.hasPrefix(
                "Allah") == true)
    }

    @Test func sajdah() {
        #expect(contentProvider.verse(.verse(surah: 96, verse: 19))?.sajdah == .obligatory)
        #expect(contentProvider.verse(.verse(surah: 96, verse: 18))?.sajdah == nil)
        // Hanafi/Diyanet: in the Hajj surah only 22:18.
        #expect(contentProvider.verse(.verse(surah: 22, verse: 18))?.sajdah != nil)
        #expect(contentProvider.verse(.verse(surah: 22, verse: 77))?.sajdah == nil)
    }

    @Test func transliteration() throws {
        let tr = try #require(contentProvider.transliteration(.verse(surah: 1, verse: 1), language: "tr"))
        #expect(tr.text == "Bismillâhirrahmânirrahîm")
        #expect(tr.words.count == 4)
        #expect(
            contentProvider.transliteration(.verse(surah: 112, verse: 2), language: "en")?.text
                == "Allaahus samad")
        #expect(contentProvider.packs.first { $0.id == "okunus-tr" }?.unreviewed == true)
    }
}

/// Text version and Store rule with throwaway packs.
@Suite(.enabled(if: contentPacksAvailable, "content packs missing: run tools/content/fetch.sh"))
struct TextVersionTests {
    func writePack(_ stem: URL, id: String, kind: String, textVersion: String?, store: Bool = true) throws {
        let folder = stem.appending(path: id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var m: [String: Any] = [
            "id": id, "art": kind, "sprache": "tr", "titel": id, "quelle": "test", "quelle_url": "https://x",
            "lizenz": "test", "store_tauglich": store, "version": "1",
        ]
        m["textstand"] = textVersion ?? NSNull()
        try JSONSerialization.data(withJSONObject: m).write(to: folder.appending(path: "manifest.json"))
        // Same database as the real pack of that kind, so that loading goes through.
        let source = ContentProviderTests.packs.appending(
            path: kind == "kuran-text" ? "kuran-text" : "meal-tr-ozek")
        try FileManager.default.copyItem(
            at: source.appending(path: "veri.sqlite"), to: folder.appending(path: "veri.sqlite"))
    }

    @Test func wrongTextVersionIsRejected() throws {
        let stem = FileManager.default.temporaryDirectory.appending(path: "kiblegah test \(UUID())")
        defer { try? FileManager.default.removeItem(at: stem) }
        try writePack(stem, id: "kuran-text", kind: "kuran-text", textVersion: "stand-a")
        try writePack(stem, id: "tecvid-alt", kind: "tecvid", textVersion: "stand-b")
        try writePack(stem, id: "meal-x", kind: "meal", textVersion: nil)
        try writePack(stem, id: "meal-privat", kind: "meal", textVersion: nil, store: false)
        let b = try PackRegistry(folders: [stem])
        #expect(b.rejected.map(\.id) == ["tecvid-alt"])
        #expect(b.translations().map(\.id) == ["meal-privat", "meal-x"])
        let s = try PackRegistry(folders: [stem], store: true)
        #expect(s.rejected.map(\.id).sorted() == ["meal-privat", "tecvid-alt"])
    }

    @Test func noStartWithoutQuran() {
        #expect(throws: ContentPackError.quranMissing) {
            try PackRegistry(folders: [
                FileManager.default.temporaryDirectory.appending(path: "leer-\(UUID())")
            ])
        }
    }
}
