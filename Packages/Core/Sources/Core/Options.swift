/// Light, dark, or by prayer time.
public enum Appearance: String, CaseIterable, Sendable, Codable {
    case system = "sistem"
    case light = "acik"
    case dark = "koyu"
    /// Dark from Isha until Imsak, light otherwise.
    case byPrayerTime = "vakteGore"
}

/// What the device uses to calculate the prayer times (Ayarlar "Vakit hesabı").
public enum PrayerTimeMethod: String, CaseIterable, Sendable, Codable {
    /// With the own location (GPS or chosen city); in the Takdir summer Imsak/Isha deviate
    /// by up to 7 minutes already 700 m from Diyanet's point.
    case location = "konum"
    /// With Diyanet's coordinate of the İlçe – identical to the minute with the mosque's calendar; the default.
    /// Without a known İlçe it also calculates with the location.
    case diyanet
}

/// An area that can appear as a tab.
///
/// The first four tabs are selectable; `kesfet` is always in fifth place.
public enum AppTab: String, CaseIterable, Sendable, Codable, Identifiable {
    case prayerTimes = "vakit"
    case qibla = "kible"
    case quran = "kuran"
    case duas = "dualar"
    case dhikr = "zikir"
    case divineNames = "esma"
    case hadith = "hadis"
    case talks = "sohbet"
    /// Quiz area (V1); default entry via Bugün and Keşfet, selectable as a tab.
    case quiz
    case discover = "kesfet"

    public var id: String { rawValue }

    /// What may appear in the first four slots.
    public static let selectable: [AppTab] = [
        .prayerTimes, .qibla, .quran, .duas, .dhikr, .divineNames, .hadith, .talks, .quiz,
    ]
    public static let standard: [AppTab] = [.prayerTimes, .qibla, .quran, .talks]

    /// Turns a stored list into four valid, unique tabs.
    /// If something is missing or duplicated, it is filled up with the default. `allowed`: only areas that
    /// the app target brings along – the stored list itself stays untouched.
    public static func normalized(_ list: [AppTab], allowed: (AppTab) -> Bool = { _ in true }) -> [AppTab] {
        var result: [AppTab] = []
        for s in list + standard + selectable where s != .discover && allowed(s) && !result.contains(s) {
            result.append(s)
            if result.count == 4 { break }
        }
        return result
    }
}

/// Color scheme, selectable in Ayarlar. Seher is the default; "Büyük ve sade" selects Sakin.
public enum Palette: String, Sendable, CaseIterable, Codable {
    case dawn = "seher", sky = "gokyuzu", ornament = "nakis", emerald = "zumrut", night = "gece", rose = "gul"
}

/// What the Qibla compass looks like.
///
/// As with "Kıble Bul" the dial is selectable; the degree ring is the default.
public enum CompassStyle: String, CaseIterable, Sendable, Codable {
    /// Fine degree ring, Kaaba on the ring, pointer from the center, rotation hint below (variant C).
    case degreeRing = "gradHalkasi"
    /// Large Kaaba and needle, golden glow and green confirmation on a hit (variant A).
    case largeNeedle = "buyukIgne"
}

/// What the Qibla tab opens with.
public enum QiblaStart: String, CaseIterable, Sendable, Codable {
    case compass = "pusula"
    /// The map with hearts first; needs network, therefore not the default.
    case map = "harita"
    /// The last chosen view, including the camera.
    case lastChoice = "sonSecim"
}
