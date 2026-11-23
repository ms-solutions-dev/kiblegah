import Foundation
import Synchronization

/// The language of the app, independent of the iPhone language.
///
/// Stored in the App Group (`ayar.language`, "" = like the iPhone), so that widgets and watch
/// speak the same language. All UI texts look up in `bundle`; a change
/// takes effect immediately because the root view rebuilds itself with the language.
public enum AppLanguage {
    public static let key = "ayar.dil"
    public static let appGroup = "group.dev.ms-solutions.kiblegah"
    public static let languages = ["tr", "de", "en"]

    private struct LoadStatus: @unchecked Sendable {
        var selection: String
        var bundle: Bundle
    }

    private static let status = Mutex<LoadStatus?>(nil)

    /// The chosen language; "" = like the iPhone.
    public static var selection: String { load().selection }

    /// The language bundle in which all texts are looked up.
    public static var bundle: Bundle { load().bundle }

    /// The language actually shown: choice, otherwise iPhone, otherwise English.
    public static var code: String {
        let s = selection
        if !s.isEmpty { return s }
        let system = Bundle.main.preferredLocalizations.first ?? "en"
        return languages.contains(system) ? system : "en"
    }

    public static var locale: Locale { Locale(identifier: code) }

    /// For clock times: the app language with the iPhone's 12/24-hour setting. `locale` alone
    /// („en“) would always mean 12 hours, also for someone in Germany who reads the app in English.
    public static var clockLocale: Locale {
        let system = Locale.autoupdatingCurrent
        var c = Locale.Components(locale: system)
        c.languageComponents = Locale.Language.Components(identifier: code)
        c.hourCycle = system.hourCycle
        return Locale(components: c)
    }

    /// Adopt a new choice (Ayarlar writes it into the App Group itself).
    public static func configure(_ selection: String) {
        status.withLock { $0 = LoadStatus(selection: selection, bundle: Self.bundle(selection)) }
    }

    private static func load() -> LoadStatus {
        status.withLock { d in
            if let d { return d }
            let s = UserDefaults(suiteName: appGroup)?.string(forKey: key) ?? ""
            let new = LoadStatus(selection: s, bundle: Self.bundle(s))
            d = new
            return new
        }
    }

    private static func bundle(_ selection: String) -> Bundle {
        guard !selection.isEmpty, let path = Bundle.main.path(forResource: selection, ofType: "lproj"),
            let b = Bundle(path: path)
        else { return .main }
        return b
    }
}
