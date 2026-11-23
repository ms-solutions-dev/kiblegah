import Foundation

/// Verse timings in one file per surah, from the ``source`` a plugin installs.
/// `approximate`: verse boundary only approximate, because the reading counts differently than Hafs.
public actor SurahTimings {
    public struct VerseTiming: Decodable, Sendable {
        enum CodingKeys: String, CodingKey {
            case verse = "ayet"
            case start = "bas"
            case end = "son"
            case approximate = "yaklasik"
        }

        public let verse: Int
        public let start: Int
        public let end: Int
        public let approximate: Bool?
    }
    struct Response: Decodable {
        let verses: [VerseTiming]
        enum CodingKeys: String, CodingKey { case verses = "ayetler" }
    }

    private var inMemory: [String: [Int: VerseTiming]] = [:]

    public init() {}

    /// Result of a query: `notYet` means the service is still computing this surah (404),
    /// `unreachable` that it does not respond.
    public enum LoadStatus: Sendable {
        case ready([Int: VerseTiming])
        case notYet
        case unreachable
    }

    /// Where the timings come from: `(surah, reciter id)` → HTTP status and body; installed by a plugin.
    /// Without a source there are no surah-file reciters.
    public typealias Source =
        @Sendable (_ surah: Int, _ reciterID: String) async -> (status: Int, data: Data)?
    nonisolated(unsafe) public static var source: Source?
    /// Whether surah-file reciters can be offered right now.
    nonisolated(unsafe) public static var isAvailable: @Sendable () -> Bool = { false }

    public func surah(_ s: Int, reciter: Reciter) async -> LoadStatus {
        let key = "\(reciter.id)-\(s)"
        if let b = inMemory[key] { return .ready(b) }
        guard let source = Self.source, let (status, veri) = await source(s, reciter.id) else {
            return .unreachable
        }
        if status == 404 { return .notYet }
        guard status == 200, let c = try? JSONDecoder().decode(Response.self, from: veri)
        else { return .unreachable }
        let z = Dictionary(c.verses.map { ($0.verse, $0) }, uniquingKeysWith: { a, _ in a })
        inMemory[key] = z
        return .ready(z)
    }
}
