import Foundation

/// Searches an Arabic word in the verses, independent of case ending, article and the prefixes
/// و ف ب ل ك.
///
/// Comparison keeps the short vowels in the interior of the word so that مَلِك (king) does not match مُلْك
/// (dominion). Dropped are shadda, sukun, the Quran marks, long-vowel doublings
/// (َا → ا) and the ending; the hamza carriers become ء, the small alif becomes ا.
public enum WordSearch {
    typealias Letters = [Unicode.Scalar]

    static let fatha: Unicode.Scalar = "\u{064E}"
    static let damme: Unicode.Scalar = "\u{064F}"
    static let kasra: Unicode.Scalar = "\u{0650}"
    static let vowels: Set<Unicode.Scalar> = ["\u{064B}", "\u{064C}", "\u{064D}", fatha, damme, kasra]
    static let migrate: [Unicode.Scalar: Unicode.Scalar] = [
        "\u{0670}": "ا", "ٱ": "ا", "أ": "ء", "إ": "ء", "ؤ": "ء", "ئ": "ء", "ى": "ي", "ة": "ه",
    ]

    /// On Unicode scalars instead of characters: a letter with a vowel is a single character in Swift,
    /// „ؤ“ alone would otherwise not be found in „ؤُ“. This also saves time over 6236 verses.
    static func normal(_ s: Substring.UnicodeScalarView) -> Letters {
        var t: Letters = []
        t.reserveCapacity(s.count)
        for u in s {
            let v = u.value
            if (0x06D6...0x06ED).contains(v) || (0x0653...0x0655).contains(v) || v == 0x0640 || v == 0x0651
                || v == 0x0652
            {
                continue
            }
            if u == "آ" {
                t += ["ء", "ا"]
                continue
            }
            let h = migrate[u] ?? u
            // Long vowel: a short vowel before the identical letter is dropped (َا → ا).
            if let end = t.last,
                (end == fatha && h == "ا") || (end == kasra && h == "ي") || (end == damme && h == "و")
            {
                t.removeLast()
            }
            t.append(h)
        }
        if t.count >= 2, t[t.count - 1] == "ا", t[t.count - 2] == "\u{064B}" { t.removeLast() }
        while let end = t.last, vowels.contains(end) { t.removeLast() }
        return t
    }

    public static func normal(_ s: String) -> String {
        var u = String.UnicodeScalarView()
        u.append(contentsOf: normal(Substring(s).unicodeScalars))
        return String(u)
    }

    static func letters(_ s: String) -> Letters { Array(s.unicodeScalars) }

    /// The searched word from an Esmâ name: last word, without article.
    public static func goal(_ arabic: String) -> String {
        let end = arabic.split(separator: " ").last ?? Substring(arabic)
        var w = normal(end.unicodeScalars)
        // „Allah“ itself is not article plus word.
        if w.starts(with: letters("ال")) && w != letters("الله") { w.removeFirst(2) }
        var u = String.UnicodeScalarView()
        u.append(contentsOf: w)
        return String(u)
    }

    static let first = [letters("و\u{064E}"), letters("ف\u{064E}"), letters("و"), letters("ف")]
    static let second = [
        letters("ب\u{0650}"), letters("ل\u{0650}"), letters("ل\u{064E}"), letters("ك\u{064E}"),
    ]
    static let third = [letters("ال"), letters("ل\u{0650}ل")]

    /// All readings of a verse word without prefixes and article.
    static func candidates(_ word: Substring) -> [Letters] {
        var out = [normal(word.unicodeScalars)]
        for prefixes in [first, second, third] {
            for x in out {
                for o in prefixes where x.starts(with: o) { out.append(Array(x.dropFirst(o.count))) }
            }
        }
        // لِلّٰه = li + Allah: the lam of the article has merged with the prefix.
        for x in out where x.starts(with: third[1]) { out.append(letters("ال") + x.dropFirst(2)) }
        return out
    }

    /// If the name has no vowel sign at all (as with „الله“), only the skeleton counts.
    public static func occurs(_ goal: String, verse: String) -> Bool {
        let h = letters(goal)
        let skeleton = !h.contains { vowels.contains($0) }
        return verse.split(separator: " ").contains { w in
            candidates(w).contains { skeleton ? $0.filter { !vowels.contains($0) } == h : $0 == h }
        }
    }
}
