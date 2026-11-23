import Foundation

/// Text rules that otherwise silently break with Turkish.
///
/// `"istanbul".uppercased()` yields "ISTANBUL" instead of "İSTANBUL", and a search for
/// "ilik" does not find "ılık". Therefore case conversion and search comparison
/// always go through here.
public enum TurkishText {
    public static let turkish = Locale(identifier: "tr_TR")

    /// Uppercasing according to the language of the text.
    public static func uppercased(_ text: String, language: Locale = turkish) -> String {
        text.uppercased(with: language)
    }

    /// Lowercasing according to the language of the text.
    public static func lowercased(_ text: String, language: Locale = turkish) -> String {
        text.lowercased(with: language)
    }

    /// The search form: lowercase, without accents and circumflexes, ı and i equal, ş/ç/ğ/ö/ü folded.
    ///
    /// So "sabir", "sabır" and "SABIR" find the same thing, and "ayetel kursi" finds
    /// "Âyete'l-Kürsî".
    public static func searchForm(_ text: String) -> String {
        var s = text.lowercased(with: turkish)
        s = s.replacingOccurrences(of: "ı", with: "i")
        s = s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: turkish)
        let annotations = CharacterSet(charactersIn: "'’‘`´-")
        s = String(s.unicodeScalars.map { annotations.contains($0) ? " " : Character($0) })
        return s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
