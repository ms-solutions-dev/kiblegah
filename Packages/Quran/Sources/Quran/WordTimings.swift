import Foundation

/// Word timings per verse (Quran.com segments), so that playback starts at a word and the
/// current word follows along.
///
/// The segments only apply to the same recording: for `Reciter.qcID` the files from
/// Quran.com and EveryAyah are byte-identical. As with `WordTranslations`,
/// never bundled and cached for at most one week.
public actor WordTimings {
    public static let lifetime: TimeInterval = 7 * 86400

    /// One word: position (1-based) and time range in milliseconds.
    public struct Word: Codable, Sendable, Equatable {
        enum CodingKeys: String, CodingKey {
            case index = "sira"
            case start = "bas"
            case end = "son"
        }

        public let index: Int
        public let start: Int
        public let end: Int
    }

    struct Response: Decodable {
        struct File: Decodable {
            let verseKey: String
            let segments: [[Int]]?
            enum CodingKeys: String, CodingKey {
                case verseKey = "verse_key"
                case segments
            }
        }
        struct Page: Decodable {
            let nextPage: Int?
            enum CodingKeys: String, CodingKey { case nextPage = "next_page" }
        }
        let audioFiles: [File]
        let pagination: Page?
        enum CodingKeys: String, CodingKey {
            case audioFiles = "audio_files"
            case pagination
        }
    }

    struct CacheEntry: Codable {
        enum CodingKeys: String, CodingKey {
            case date = "tarih"
            case verses = "ayetler"
        }

        let date: Date
        let verses: [Int: [Word]]
    }

    let folder: URL
    let session: URLSession
    private var inMemory: [String: CacheEntry] = [:]

    public init(folder: URL? = nil, session: URLSession = .shared) {
        self.folder = folder ?? URL.cachesDirectory.appending(path: "KelimeZamanlari")
        self.session = session
    }

    /// Word timings of a surah per verse; `nil` without network, without cache or without a matching recording.
    public func surah(_ s: Int, reciter: Reciter, now: Date = .now) async -> [Int: [Word]]? {
        guard let qc = reciter.qcID else { return nil }
        let key = "\(reciter.id)-\(s)"
        if let k = inMemory[key] ?? fromDisk(key), now.timeIntervalSince(k.date) < Self.lifetime {
            inMemory[key] = k
            return k.verses
        }
        var verses: [Int: [Word]] = [:]
        var page: Int? = 1
        while let n = page {
            var b = URLComponents(string: "https://api.quran.com/api/v4/recitations/\(qc)/by_chapter/\(s)")!
            b.queryItems = [
                URLQueryItem(name: "fields", value: "segments"), URLQueryItem(name: "per_page", value: "50"),
                URLQueryItem(name: "page", value: "\(n)"),
            ]
            guard let (veri, answer) = try? await session.data(from: b.url!),
                (answer as? HTTPURLResponse)?.statusCode == 200,
                let c = try? JSONDecoder().decode(Response.self, from: veri)
            else { return nil }
            verses.merge(Self.parse(c)) { a, _ in a }
            page = c.pagination?.nextPage
        }
        guard !verses.isEmpty else { return nil }
        let k = CacheEntry(date: now, verses: verses)
        inMemory[key] = k
        toDisk(key, k)
        return verses
    }

    /// Segment `[i, wort, start, end]`; incomplete ones are dropped.
    static func parse(_ c: Response) -> [Int: [Word]] {
        var result: [Int: [Word]] = [:]
        for d in c.audioFiles {
            guard let verse = d.verseKey.split(separator: ":").last.flatMap({ Int($0) }) else { continue }
            result[verse] = (d.segments ?? []).compactMap { s in
                s.count >= 4 ? Word(index: s[1], start: s[2], end: s[3]) : nil
            }
            .sorted { $0.index < $1.index }
        }
        return result
    }

    /// The word at time `ms` (for the follow-along highlighting).
    public nonisolated static func word(_ l: [Word], ms: Int) -> Int? {
        l.last { $0.start <= ms }?.index
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
