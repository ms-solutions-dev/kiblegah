import Foundation

/// The stable key of a content item.
///
/// Everything that carries user data – note, favorite, reading position, collection – hangs only on
/// this key. This way notes on a hadith (V2) work without a new
/// schema. The text form (`a:2:255`) is the stored form and must never change.
public enum ContentKey: Hashable, Sendable, Codable, CustomStringConvertible {
    case surah(Int)
    case verse(surah: Int, verse: Int)
    case verseRange(surah: Int, first: Int, end: Int)
    case word(surah: Int, verse: Int, index: Int)
    case page(Int)
    case juz(Int)
    case dua(String)
    case divineName(Int)
    case hadith(collection: String, number: Int)
    case topic(String)

    /// The stored text form, e.g. `a:2:255` or `d:evden-cikarken`.
    public var text: String {
        switch self {
        case .surah(let n): "s:\(n)"
        case .verse(let s, let a): "a:\(s):\(a)"
        case .verseRange(let s, let first, let end): "a:\(s):\(first)-\(end)"
        case .word(let s, let a, let p): "w:\(s):\(a):\(p)"
        case .page(let n): "p:\(n)"
        case .juz(let n): "j:\(n)"
        case .dua(let slug): "d:\(slug)"
        case .divineName(let n): "e:\(n)"
        case .hadith(let k, let n): "h:\(k):\(n)"
        case .topic(let slug): "k:\(slug)"
        }
    }

    public var description: String { text }

    /// Reads the text form. Unknown or incomplete input yields `nil`, never a crash.
    public init?(text: String) {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard let kind = parts.first, parts.count >= 2 else { return nil }
        let numbers = parts.dropFirst().compactMap { Int($0) }
        switch (kind, parts.count) {
        case ("s", 2): guard let n = numbers.first, n >= 1 else { return nil }; self = .surah(n)
        case ("a", 3):
            guard let s = Int(parts[1]), s >= 1 else { return nil }
            let second = parts[2]
            if let tire = second.firstIndex(of: "-") {
                guard let first = Int(second[..<tire]), let end = Int(second[second.index(after: tire)...]),
                    first >= 1, end >= first
                else { return nil }
                self =
                    first == end
                    ? .verse(surah: s, verse: first) : .verseRange(surah: s, first: first, end: end)
            } else {
                guard let a = Int(second), a >= 1 else { return nil }
                self = .verse(surah: s, verse: a)
            }
        case ("w", 4):
            guard numbers.count == 3, numbers.allSatisfy({ $0 >= 1 }) else { return nil }
            self = .word(surah: numbers[0], verse: numbers[1], index: numbers[2])
        case ("p", 2): guard let n = numbers.first, n >= 1 else { return nil }; self = .page(n)
        case ("j", 2): guard let n = numbers.first, (1...30).contains(n) else { return nil }; self = .juz(n)
        case ("d", 2): guard !parts[1].isEmpty else { return nil }; self = .dua(parts[1])
        case ("e", 2):
            guard let n = numbers.first, (1...99).contains(n) else { return nil }; self = .divineName(n)
        case ("h", 3):
            guard !parts[1].isEmpty, let n = Int(parts[2]) else { return nil }
            self = .hadith(collection: parts[1], number: n)
        case ("k", 2): guard !parts[1].isEmpty else { return nil }; self = .topic(parts[1])
        default: return nil
        }
    }

    /// Whether this key includes verse `a:s:a` – for ranges (tafsir, note).
    public func covers(surah s: Int, verse a: Int) -> Bool {
        switch self {
        case .verse(let ss, let aa): ss == s && aa == a
        case .verseRange(let ss, let first, let end): ss == s && (first...end).contains(a)
        case .word(let ss, let aa, _): ss == s && aa == a
        case .surah(let ss): ss == s
        default: false
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let a = ContentKey(text: text) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unbekannter Schlüssel \(text)")
        }
        self = a
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(text)
    }
}
