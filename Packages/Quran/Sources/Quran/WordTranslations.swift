import Foundation

/// Meaning of a word; `fallback` means: Quran.com does not have it in the desired language,
/// this is the English fallback meaning (the view sets it in italics and muted).
public struct WordMeaning: Codable, Hashable, Sendable {
    enum CodingKeys: String, CodingKey {
        case text = "metin"
        case fallback = "yedek"
    }

    public let text: String
    public let fallback: Bool

    public init(text: String, fallback: Bool = false) {
        self.text = text
        self.fallback = fallback
    }
}

/// Word-by-word meanings from Quran.com (Quran Foundation), loaded per surah.
///
/// Per the QF terms, never bundled with the app and cached for at most one week
///. TR and EN exist; for DE the source delivers English, which the app indicates.
/// Words are matched by position within each verse; if the word count does not match the
/// Tanzil text, the verse stays without word meanings instead of shifting.
public actor WordTranslations {
    public static let source = "Quran.com (Quran Foundation)"
    public static let lifetime: TimeInterval = 7 * 86400

    struct Response: Decodable {
        struct Verse: Decodable {
            let verseNumber: Int
            let words: [Word]
            enum CodingKeys: String, CodingKey {
                case verseNumber = "verse_number"
                case words
            }
        }
        struct Word: Decodable {
            let position: Int
            let kind: String
            let translation: Translation?
            enum CodingKeys: String, CodingKey {
                case position, translation
                case kind = "char_type_name"
            }
        }
        struct Translation: Decodable {
            let text: String?
            let language: String?
            enum CodingKeys: String, CodingKey {
                case text
                case language = "language_name"
            }
        }
        let verses: [Verse]
    }

    struct CacheEntry: Codable {
        enum CodingKeys: String, CodingKey {
            case date = "tarih"
            case language = "dil"
            case verses = "ayetler"
        }

        let date: Date
        let language: String
        /// verse → meaning per word position
        let verses: [Int: [WordMeaning]]
    }

    let folder: URL
    let session: URLSession
    private var inMemory: [String: CacheEntry] = [:]

    public init(folder: URL? = nil, session: URLSession = .shared) {
        self.folder = folder ?? URL.cachesDirectory.appending(path: "KelimeMeali")
        self.session = session
    }

    /// The language in which delivery actually takes place.
    public nonisolated static func sourceLanguage(_ language: String) -> String {
        language == "tr" ? "tr" : "en"
    }

    /// Meanings of a surah per verse; `nil` without network and without a valid cache.
    public func surah(_ s: Int, language: String, now: Date = .now) async -> [Int: [WordMeaning]]? {
        let d = Self.sourceLanguage(language)
        // v2: fallback words per word instead of whole English verses; old entries are no longer valid.
        let key = "v2-\(d)-\(s)"
        if let k = inMemory[key] ?? fromDisk(key), now.timeIntervalSince(k.date) < Self.lifetime {
            inMemory[key] = k
            return k.verses
        }
        var b = URLComponents(string: "https://api.quran.com/api/v4/verses/by_chapter/\(s)")!
        b.queryItems = [
            URLQueryItem(name: "words", value: "true"), URLQueryItem(name: "language", value: d),
            URLQueryItem(name: "per_page", value: "300"),
            URLQueryItem(name: "word_fields", value: "position"),
        ]
        guard let (veri, answer) = try? await session.data(from: b.url!),
            (answer as? HTTPURLResponse)?.statusCode == 200, Self.verseCount(veri) > 0
        else { return nil }
        guard let verses = Self.parse(veri, language: d), !verses.isEmpty else { return nil }
        let k = CacheEntry(date: now, language: d, verses: verses)
        inMemory[key] = k
        toDisk(key, k)
        return verses
    }

    /// Meanings per verse. If Quran.com delivers a different language than `language` for individual words
    /// (missing Turkish translation → English), the verse stays Turkish and only that word
    /// is marked as a fallback. Previously the whole verse fell back to English; in
    /// Duhâ almost everything was English as a result.
    static func parse(_ veri: Data, language: String? = nil) -> [Int: [WordMeaning]]? {
        guard let c = try? JSONDecoder().decode(Response.self, from: veri) else { return nil }
        let name = language.flatMap { languageName[$0] }
        var result: [Int: [WordMeaning]] = [:]
        for a in c.verses {
            let words = a.words.filter { $0.kind == "word" }.sorted { $0.position < $1.position }
            result[a.verseNumber] = words.map { k in
                let fallback = name.map { a in (k.translation?.language).map { $0 != a } ?? false } ?? false
                return WordMeaning(text: k.translation?.text ?? "", fallback: fallback)
            }
        }
        return result.isEmpty ? nil : result
    }

    static let languageName = ["tr": "turkish", "en": "english"]

    static func verseCount(_ veri: Data) -> Int {
        (try? JSONDecoder().decode(Response.self, from: veri))?.verses.count ?? 0
    }

    private func fromDisk(_ key: String) -> CacheEntry? {
        guard let v = try? Data(contentsOf: folder.appending(path: "\(key).json")) else { return nil }
        return try? JSONDecoder().decode(CacheEntry.self, from: v)
    }

    private func toDisk(_ key: String, _ k: CacheEntry) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let v = try? JSONEncoder().encode(k) {
            try? v.write(to: folder.appending(path: "\(key).json"))
        }
    }

    /// Removes expired entries (QF: at most one week).
    public func clear(now: Date = .now) {
        let files =
            (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for d in files {
            guard let v = try? Data(contentsOf: d),
                let k = try? JSONDecoder().decode(CacheEntry.self, from: v)
            else { continue }
            if now.timeIntervalSince(k.date) >= Self.lifetime { try? FileManager.default.removeItem(at: d) }
        }
        inMemory = inMemory.filter { now.timeIntervalSince($0.value.date) < Self.lifetime }
    }
}
