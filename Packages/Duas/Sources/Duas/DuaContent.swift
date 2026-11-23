import ContentPacks
import Core
import Foundation

/// Text of a dua from the Quran packages – Arabic from the address word onward, Okunuş and translation.
public enum DuaContent {
    /// The words of a verse that belong to the dua: in the first from `firstWord`, in the last up to `lastWord`.
    static func kes<T>(_ words: [T], verse n: Int, _ d: Dua) -> [T] {
        var k = words
        if n == d.end, d.lastWord > 0 { k = Array(k.prefix(d.lastWord)) }
        if n == d.first { k = Array(k.dropFirst(d.firstWord - 1)) }
        return k
    }

    /// Arabic: first verse from `firstWord`, last up to `lastWord`.
    public static func arabic(_ d: Dua, _ contentProvider: any ContentProvider) -> String {
        contentProvider.verses(d.source).enumerated().map { i, a in
            kes(a.words, verse: d.first + i, d).map(\.text).joined(separator: " ")
        }.joined(separator: " ")
    }

    /// Okunuş over the same word span.
    public static func transliteration(
        _ d: Dua, _ contentProvider: any ContentProvider, language: String
    ) -> String? {
        let parts = (d.first...d.end).compactMap { n -> String? in
            guard
                let o = contentProvider.transliteration(.verse(surah: d.surah, verse: n), language: language)
            else {
                return nil
            }
            return kes(o.words, verse: n, d).joined(separator: " ")
        }
        guard !parts.isEmpty else { return nil }
        let text = parts.joined(separator: " ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// Meal of the whole verses (a meal cannot be cut word-exactly). If a meal translates
    /// two verses together, the same text stands at both (Diyanet 10:85–86); then only once.
    public static func translation(_ d: Dua, _ contentProvider: any ContentProvider, pack: String) -> String?
    {
        var l: [String] = []
        for a in d.first...d.end {
            if let m = contentProvider.translation(.verse(surah: d.surah, verse: a), pack: pack)?.text,
                m != l.last
            {
                l.append(m)
            }
        }
        return l.isEmpty ? nil : l.joined(separator: " ")
    }

    /// One dua per day, for the Duas home screen.
    public static func ofTheDay(_ duas: [Dua], day: Date, calendar: Calendar = .current) -> Dua? {
        guard !duas.isEmpty else { return nil }
        let n = calendar.ordinality(of: .day, in: .era, for: day) ?? 0
        return duas[n % duas.count]
    }

    /// Search over meal text, transliteration and surah name (Turkish-folded).
    public static func search(
        _ text: String, _ duas: [Dua], _ contentProvider: any ContentProvider, pack: String, language: String
    ) -> [Dua] {
        let k = TurkishText.searchForm(text)
        guard !k.isEmpty else { return duas }
        return duas.filter { d in
            let areas = [
                translation(d, contentProvider, pack: pack) ?? "",
                transliteration(d, contentProvider, language: language) ?? "",
                contentProvider.surah(d.surah).map {
                    "\($0.nameTurkish) \($0.nameLatin) \(d.surah):\(d.first)"
                } ?? "",
            ]
            return areas.contains { TurkishText.searchForm($0).contains(k) }
        }
    }
}
