import Foundation

public enum GroupDefaults {
    /// The shared suite; without an App Group (e.g. `swift test` without entitlement) `standard`.
    public static var d: UserDefaults { UserDefaults(suiteName: AppLanguage.appGroup) ?? .standard }

    /// Formerly stored in `standard`. Never change names – otherwise stored values are lost.
    public static let migratedKeys = [
        "tefsir.kaynak",  // tafsir choice in the verse sheet
        "kuranNuzulSirasi", "kuranKayitTarihe",  // Quran list
        "ezberDuzeni",  // memorization view
        "mushafOlcek", "mushafZoomIpucu",  // Mushaf
        "okuma.baslangic", "okuma.bitis", "okuma.tekrar",  // Okuma seçenekleri
        "quizKontrolcu",  // Soru kontrolü
        "sohbetTanitimGoruldu",  // introduction card of a plugin area
    ]

    /// Once at startup: take over from `source` whatever is still missing in `target`. Existing values in the group
    /// win; the old values remain (a rollback to an older build still finds them).
    public static func migrate(
        source: UserDefaults = .standard, target: UserDefaults = d, keys: [String] = migratedKeys
    ) {
        guard source !== target else { return }
        for k in keys where target.object(forKey: k) == nil {
            if let v = source.object(forKey: k) { target.set(v, forKey: k) }
        }
    }
}
