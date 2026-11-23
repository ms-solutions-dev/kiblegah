import Core
import SwiftUI

/// Further string tables next to `Localizable` that an app target ships (e.g. for a plugin's own
/// screens). A key missing in the main catalog is looked up there, in this order. Registered once
/// at startup by the plugins; without any, lookups go only to the main catalog.
public enum StringTables {
    nonisolated(unsafe) public static var extra: [String] = []

    /// Registers a table (idempotent).
    public static func register(_ table: String) {
        if !extra.contains(table) { extra.append(table) }
    }

    private static let missing = "\u{1}"

    /// The table holding `key` (also format keys like `"quiz.x %lld"`); `nil` = the main catalog.
    static func table(for key: String) -> String? {
        guard !extra.isEmpty else { return nil }
        let b = AppLanguage.bundle
        if b.localizedString(forKey: key, value: missing, table: nil) != missing { return nil }
        return extra.first { b.localizedString(forKey: key, value: missing, table: $0) != missing }
    }

    /// The key behind a `LocalizedStringKey` (format string for interpolations), if readable.
    static func table(for key: LocalizedStringKey) -> String? {
        guard !extra.isEmpty,
            let k = Mirror(reflecting: key).children.first(where: { $0.label == "key" })?.value as? String
        else { return nil }
        return table(for: k)
    }
}

extension Text {
    /// A translated text from the app catalog (`App/Resources/Localizable.xcstrings`).
    ///
    /// Inside a package, `Text("schlüssel")` looks in the package bundle and
    /// then silently shows the bare key – happened twice with CineLounge. That is why all
    /// UI texts go through here, so every key can be checked against the catalog.
    public init(app key: LocalizedStringKey) {
        self.init(key, tableName: StringTables.table(for: key), bundle: AppLanguage.bundle)
    }
}

/// A translated text as a `String`, e.g. for accessibility labels.
public func localized(_ key: String.LocalizationValue) -> String {
    let b = AppLanguage.bundle
    let value = String(localized: key, bundle: b)
    guard !StringTables.extra.isEmpty else { return value }
    // A table that does not exist yields what a missing key yields.
    let missing = String(localized: key, table: "-", bundle: b)
    if value != missing { return value }
    for t in StringTables.extra {
        let v = String(localized: key, table: t, bundle: b)
        if v != missing { return v }
    }
    return value
}

/// A catalog text for a key built at runtime, in the app language.
public func localized(key: String, fallback: String? = nil) -> String {
    AppLanguage.bundle.localizedString(forKey: key, value: fallback, table: StringTables.table(for: key))
}
