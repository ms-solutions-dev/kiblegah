import Core
import Foundation
import Synchronization

/// On-device meaning search via the package `arama-vektor`.
///
/// The model is static (potion-multilingual-128M): a table „word piece → vector“.
/// A query is split as at build time (unigram Viterbi via `part.score`), the vectors
/// are averaged and compared with the precomputed verse vectors. How the package is built and
/// why tafsir and `agirlik` belong to it is described in `tools/content/arama_vektor.py`.
///
/// Tables are loaded on first call (~50,000 word pieces, ~0.2 s) and stay in
/// memory; verse vectors per translation likewise only on demand.
final class MeaningSearch: Sendable {
    static let size = 256

    private struct Lexicon {
        var parts: [String: (score: Float, index: Int)] = [:]
        var vectors: [Float] = []
        var longest = 1
    }

    private struct VerseTable {
        var keys: [(surah: Int, verse: Int)] = []
        var weights: [Float] = []
        var vectors: [Float] = []
        var center: [Float] = []
    }

    private let db: Database
    private let dictionary = Mutex<Lexicon?>(nil)
    private let tables = Mutex<[String: VerseTable]>([:])

    init(db: Database) { self.db = db }

    /// Row in the package format: float32 scale, then 256 × int8.
    private static func open(_ d: Data, _ goal: inout [Float]) {
        d.withUnsafeBytes { b in
            let scale = b.loadUnaligned(as: Float.self)
            for i in 0..<size { goal.append(Float(b.load(fromByteOffset: 4 + i, as: Int8.self)) * scale) }
        }
    }

    private func loadDictionary() -> Lexicon {
        dictionary.withLock { s in
            if let s { return s }
            var y = Lexicon()
            y.vectors.reserveCapacity(50_000 * Self.size)
            var index = 0
            _ = db.query("SELECT metin, skor, vektor FROM parca", []) { r in
                let p = r.text(0)
                y.parts[p] = (Float(r.double(1)), index)
                y.longest = max(y.longest, p.unicodeScalars.count)
                Self.open(r.data(2), &y.vectors)
                index += 1
                return 0
            }
            s = y
            return y
        }
    }

    private func table(_ pack: String) -> VerseTable? {
        if let t = tables.withLock({ $0[pack] }) { return t }
        var t = VerseTable()
        guard
            let m = db.first(
                "SELECT vektor FROM merkez WHERE paket = ?", [.text(pack)], row: { $0.data(0) }),
            m.count == Self.size * 4
        else { return nil }
        t.center = m.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        _ = db.query(
            "SELECT sure, ayet, agirlik, vektor FROM ayet WHERE paket = ? ORDER BY sure, ayet",
            [.text(pack)]
        ) { r in
            t.keys.append((r.integer(0), r.integer(1)))
            t.weights.append(Float(r.double(2)))
            Self.open(r.data(3), &t.vectors)
            return 0
        }
        tables.withLock { $0[pack] = t }
        return t
    }

    /// Unigram Viterbi like `Zerleger.tokenize` in the build tool; unknown single characters are dropped.
    func tokenize(_ text: String) -> [String] {
        let s = loadDictionary()
        let z = Array(
            ("▁" + text.precomposedStringWithCompatibilityMapping.replacingOccurrences(of: " ", with: "▁"))
                .unicodeScalars)
        let n = z.count
        var best = [Float](repeating: -.greatestFiniteMagnitude, count: n + 1)
        var rest = [(start: Int, part: String?)](repeating: (0, nil), count: n + 1)
        best[0] = 0
        for end in 1...max(1, n) where n > 0 {
            for start in max(0, end - s.longest)..<end {
                var p: String? = String(String.UnicodeScalarView(z[start..<end]))
                var sk = s.parts[p!]?.score
                if sk == nil {
                    guard end - start == 1 else { continue }
                    sk = -100
                    p = nil
                }
                if best[start] + sk! > best[end] {
                    best[end] = best[start] + sk!
                    rest[end] = (start, p)
                }
            }
        }
        var result: [String] = []
        var i = n
        while i > 0 {
            if let p = rest[i].part { result.append(p) }
            i = rest[i].start
        }
        return result.reversed()
    }

    /// Verses of a translation, sorted by closeness to the query (value 0…1, damped for very short verses).
    func search(_ text: String, pack: String, limit: Int) -> [(key: ContentKey, score: Float)] {
        let parts = tokenize(text)
        guard !parts.isEmpty, let t = table(pack) else { return [] }
        let s = loadDictionary()
        let d = Self.size
        var q = [Float](repeating: 0, count: d)
        for p in parts {
            guard let i = s.parts[p]?.index else { continue }
            for j in 0..<d { q[j] += s.vectors[i * d + j] }
        }
        Self.normalizeToUnit(&q)
        for j in 0..<d { q[j] -= t.center[j] }
        Self.normalizeToUnit(&q)
        var scores: [(Int, Float)] = []
        scores.reserveCapacity(t.keys.count)
        t.vectors.withUnsafeBufferPointer { v in
            for i in 0..<t.keys.count {
                var total: Float = 0
                for j in 0..<d { total += v[i * d + j] * q[j] }
                scores.append((i, total * t.weights[i]))
            }
        }
        return scores.sorted { $0.1 > $1.1 }.prefix(limit).map {
            (ContentKey.verse(surah: t.keys[$0.0].surah, verse: t.keys[$0.0].verse), $0.1)
        }
    }

    private static func normalizeToUnit(_ v: inout [Float]) {
        let l = v.reduce(0) { $0 + $1 * $1 }.squareRoot()
        if l > 0 { for i in v.indices { v[i] /= l } }
    }
}
