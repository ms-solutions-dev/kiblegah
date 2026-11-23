import Foundation

/// Content sources that require permission, switched by the build.
///
/// The values come from the Info key `KiblegahOzellikler` (comma-separated) and are never switchable
/// by the user. Without the key everything is off: the function is missing or falls back to a free
/// source, and no network call goes to a disabled service.
public struct FeatureFlags: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Prayer time table and religious days from an own prayer time service. Off: the device
    /// calculates itself (`OnDeviceSource` with the 45° rule) and religious days come from
    /// `ReligiousDay.calculate`.
    public static let diyanet = FeatureFlags(rawValue: 1 << 0)
    /// Reciters outside the Quran.com catalog (require permission). Off: only the Quran.com catalog.
    public static let extraReciters = FeatureFlags(rawValue: 1 << 1)

    public static let all: FeatureFlags = [.diyanet, .extraReciters]
    public static let free: FeatureFlags = []

    /// Names in the Info key.
    public static let names: [String: FeatureFlags] = ["diyanet": .diyanet, "ekKariler": .extraReciters]
    public static let infoKey = "KiblegahOzellikler"

    /// From the Info value, e.g. "diyanet,ekKariler"; unknown entries and an unreplaced `$(…)` don't count.
    public static func parse(_ text: String?) -> FeatureFlags {
        var o = FeatureFlags.free
        for part in (text ?? "").split(separator: ",") {
            if let x = names[part.trimmingCharacters(in: .whitespaces)] { o.insert(x) }
        }
        return o
    }

    /// The switches of this app; without `load()` everything off (Store default).
    nonisolated(unsafe) public static var enabled: FeatureFlags = .free

    /// Once at startup, before the first `AppSettings()`.
    public static func load(_ pack: Bundle = .main) {
        enabled = parse(pack.object(forInfoDictionaryKey: infoKey) as? String)
    }
}
