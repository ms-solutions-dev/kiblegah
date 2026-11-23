import Foundation

/// Address of the own relay (a Cloudflare Worker).
///
/// API credentials (e.g. Quran Foundation OAuth) live only there; the app knows only this address.
/// It comes from the build (Info key `VermittlerAdresi`) and is not a secret. Empty means: without a
/// relay – features that need it fall back (the mushaf without a pack shows the reflowed text).
public enum Relay {
    public static let infoKey = "VermittlerAdresi"

    /// From the Info value: `host` (then https) or a full address; empty and an unreplaced
    /// `$(…)` mean "no relay".
    public static func parse(_ text: String?) -> URL? {
        let d = (text ?? "").trimmingCharacters(in: .whitespaces)
        if d.isEmpty || d.hasPrefix("$(") { return nil }
        guard let u = URL(string: d.contains("://") ? d : "https://" + d), u.host() != nil else { return nil }
        return u
    }

    /// The address of this app; without `load()` none.
    nonisolated(unsafe) public static var address: URL?

    /// Once at startup, before the first network call.
    public static func load(_ pack: Bundle = .main) {
        address = parse(pack.object(forInfoDictionaryKey: infoKey) as? String)
    }

    public static var qfBase: String { address?.appending(path: "qf").absoluteString ?? "" }
}
