import Core
import Foundation
import Observation

/// The settings of the app, stored in the App Group so that widgets
/// can read them. Every change is written immediately.
@MainActor @Observable public final class AppSettings {
    public nonisolated static let appGroup = "group.dev.ms-solutions.kiblegah"

    public var appearance: Appearance { didSet { save(appearance.rawValue, Keys.appearance) } }
    public var largeAndSimple: Bool { didSet { save(largeAndSimple, Keys.largeAndSimple) } }
    public var tabs: [AppTab] {
        didSet {
            let flat = AppTab.normalized(tabs)
            if flat != tabs { tabs = flat; return }
            save(tabs.map(\.rawValue), Keys.tabs)
        }
    }
    /// Language of the app, independent of the iPhone; "" = same as the iPhone.
    public var language: String {
        didSet {
            save(language, AppLanguage.key)
            AppLanguage.configure(language)
        }
    }
    /// Color theme; has no effect while „Büyük ve sade“ is on.
    public var palette: Palette { didSet { save(palette.rawValue, Keys.palette) } }
    public var karahatMinutes: Int { didSet { save(karahatMinutes, Keys.karahat) } }
    public var iCloud: Bool { didSet { save(iCloud, Keys.iCloud) } }
    public var onboardingDone: Bool { didSet { save(onboardingDone, Keys.firstLaunch) } }
    /// The location for prayer time and Qibla; `nil` as long as none is chosen.
    public var location: Location? {
        didSet { defaults.set(location.flatMap { try? JSONEncoder().encode($0) }, forKey: Keys.location) }
    }
    /// Track the location via GPS; off when a city was chosen by hand.
    public var automaticLocation: Bool { didSet { save(automaticLocation, Keys.automaticLocation) } }
    /// Diyanet coordinate of the İlçe (default) or own location; without a known İlçe always location.
    public var prayerTimeMethod: PrayerTimeMethod {
        didSet { save(prayerTimeMethod.rawValue, Keys.prayerTimeMethod) }
    }
    /// Notification settings per prayer time as JSON; only the prayer-time package knows the format.
    public var notificationData: Data? {
        didSet { defaults.set(notificationData, forKey: Keys.notifications) }
    }
    /// Sound of the notifications: „varsayilan“ (system sound) or „kisaEzan“.
    public var notificationSound: String { didSet { save(notificationSound, Keys.notificationSound) } }
    /// Okuma ayarları (Q-Aa): three sizes, transliteration on/off, chosen translations (empty = one per language).
    public var arabicSize: Double { didSet { save(arabicSize, Keys.arabicSize) } }
    public var transliterationSize: Double { didSet { save(transliterationSize, Keys.transliterationSize) } }
    public var translationSize: Double { didSet { save(translationSize, Keys.translationSize) } }
    public var showTransliteration: Bool { didSet { save(showTransliteration, Keys.showTransliteration) } }
    public var selectedTranslations: [String] { didSet { save(selectedTranslations, Keys.translations) } }
    public var tajweedColors: Bool { didSet { save(tajweedColors, Keys.tajweed) } }
    /// Tajweed only for the mushaf page, via the switch in its title bar; independent of
    /// `tajweedColors` in list and reading settings.
    public var mushafTajweed: Bool { didSet { save(mushafTajweed, Keys.mushafTajweed) } }
    /// Mushaf edition on the device (): "v1" (1405 H), "v2" (1421 H), "v4" (1441 H with tajweed).
    /// Empty = not yet chosen; older states with `mushafTajweed` switched on count as "v4".
    public var mushafEdition: String { didSet { save(mushafEdition, Keys.mushafEdition) } }
    /// Open Quran targets (surah, juz, verse from lists, search, Bugün) directly as a mushaf page.
    public var openInMushaf: Bool { didSet { save(openInMushaf, Keys.openInMushaf) } }
    /// Language of transliteration and tafsir where there is none of its own (German): "" = automatic, "tr", "en".
    public var transliterationLanguage: String {
        didSet { save(transliterationLanguage, Keys.transliterationLanguage) }
    }
    public var tafsirLanguage: String { didSet { save(tafsirLanguage, Keys.tafsirLanguage) } }
    public var reciter: String { didSet { save(reciter, Keys.reciter) } }
    /// Active reading position: "" = default khatm, otherwise `Hatim.identifier`.
    public var activeKhatm: String { didSet { save(activeKhatm, Keys.activeKhatm) } }
    /// Live Activity „sıradaki vakit“ on the lock screen.
    public var liveActivity: Bool { didSet { save(liveActivity, Keys.live) } }
    /// Word-by-word translation: meaning under each word (Quran.com, online).
    public var wordByWord: Bool { didSet { save(wordByWord, Keys.word) } }
    /// Dial of the Qibla compass; degree ring is the default.
    public var compassStyle: CompassStyle { didSet { save(compassStyle.rawValue, Keys.compassStyle) } }
    /// What the Qibla tab opens with.
    public var qiblaStart: QiblaStart {
        didSet { save(qiblaStart.rawValue, Keys.qiblaStart) }
    }
    /// Last chosen Qibla view ("pusula", "kamera", "harita") for ``QiblaStart/sonSecim``.
    public var qiblaLastMode: String { didSet { save(qiblaLastMode, Keys.qiblaLastMode) } }

    /// Quiz: daily rounds per week as a goal (3…7, default 5).
    public var quizGoal: Int { didSet { save(min(7, max(3, quizGoal)), Keys.quizGoal) } }
    /// Quiz: the Niyet hint appears only on first open.
    public var quizIntentionSeen: Bool { didSet { save(quizIntentionSeen, Keys.quizIntention) } }
    /// Duel: the name under which the other side sees you (stored in the public duel room).
    public var duelName: String { didSet { save(duelName, Keys.duelName) } }
    /// Talks: allow automatic dubbing; off always means the original audio track.
    public var talksDubbing: Bool { didSet { save(talksDubbing, Keys.talksDubbing) } }
    /// Remind 15 minutes before every karahat.
    public var karahatReminder: Bool { didSet { save(karahatReminder, Keys.karahatReminder) } }

    public static let arabicDefault = 30.0
    public static let textDefault = 17.0

    public func resetReadingSizes() {
        arabicSize = Self.arabicDefault
        transliterationSize = Self.textDefault
        translationSize = Self.textDefault
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults? = nil) {
        let d = defaults ?? UserDefaults(suiteName: AppSettings.appGroup) ?? .standard
        self.defaults = d
        appearance = d.string(forKey: Keys.appearance).flatMap(Appearance.init(rawValue:)) ?? .system
        largeAndSimple = d.bool(forKey: Keys.largeAndSimple)
        tabs = AppTab.normalized(
            (d.stringArray(forKey: Keys.tabs) ?? []).compactMap(AppTab.init(rawValue:)))
        palette = d.string(forKey: Keys.palette).flatMap(Palette.init(rawValue:)) ?? .dawn
        let selectedLanguage = d.string(forKey: AppLanguage.key) ?? ""
        language = selectedLanguage
        AppLanguage.configure(selectedLanguage)
        let k = d.integer(forKey: Keys.karahat)
        karahatMinutes = k == 0 ? 45 : k
        // iCloud is off by default and is chosen deliberately.
        iCloud = d.bool(forKey: Keys.iCloud)
        onboardingDone = d.bool(forKey: Keys.firstLaunch)
        location = d.data(forKey: Keys.location).flatMap {
            try? JSONDecoder().decode(Location.self, from: $0)
        }
        automaticLocation = d.object(forKey: Keys.automaticLocation) as? Bool ?? true
        prayerTimeMethod =
            d.string(forKey: Keys.prayerTimeMethod).flatMap(PrayerTimeMethod.init(rawValue:)) ?? .diyanet
        notificationData = d.data(forKey: Keys.notifications)
        notificationSound = d.string(forKey: Keys.notificationSound) ?? "varsayilan"
        arabicSize = d.object(forKey: Keys.arabicSize) as? Double ?? Self.arabicDefault
        transliterationSize = d.object(forKey: Keys.transliterationSize) as? Double ?? Self.textDefault
        translationSize = d.object(forKey: Keys.translationSize) as? Double ?? Self.textDefault
        showTransliteration = d.object(forKey: Keys.showTransliteration) as? Bool ?? true
        selectedTranslations = d.stringArray(forKey: Keys.translations) ?? []
        tajweedColors = d.bool(forKey: Keys.tajweed)
        mushafTajweed = d.bool(forKey: Keys.mushafTajweed)
        openInMushaf = d.bool(forKey: Keys.openInMushaf)
        mushafEdition =
            d.string(forKey: Keys.mushafEdition) ?? (d.bool(forKey: Keys.mushafTajweed) ? "v4" : "")
        transliterationLanguage = d.string(forKey: Keys.transliterationLanguage) ?? ""
        tafsirLanguage = d.string(forKey: Keys.tafsirLanguage) ?? ""
        reciter = d.string(forKey: Keys.reciter) ?? "alafasy"
        activeKhatm = d.string(forKey: Keys.activeKhatm) ?? ""
        liveActivity = d.bool(forKey: Keys.live)
        wordByWord = d.bool(forKey: Keys.word)
        compassStyle =
            d.string(forKey: Keys.compassStyle).flatMap(CompassStyle.init(rawValue:)) ?? .degreeRing
        qiblaStart =
            d.string(forKey: Keys.qiblaStart).flatMap(QiblaStart.init(rawValue:)) ?? .compass
        qiblaLastMode = d.string(forKey: Keys.qiblaLastMode) ?? ""
        let h = d.integer(forKey: Keys.quizGoal)
        quizGoal = h == 0 ? 5 : min(7, max(3, h))
        quizIntentionSeen = d.bool(forKey: Keys.quizIntention)
        talksDubbing = d.bool(forKey: Keys.talksDubbing)
        duelName = d.string(forKey: Keys.duelName) ?? ""
        karahatReminder = d.object(forKey: Keys.karahatReminder) as? Bool ?? true
    }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }

    enum Keys {
        static let appearance = "ayar.gorunum"
        static let largeAndSimple = "ayar.buyukVeSade"
        static let tabs = "ayar.sekmeler"
        static let karahat = "ayar.kerahatDakika"
        static let palette = "ayar.palet"
        static let iCloud = "ayar.icloud"
        static let firstLaunch = "ayar.ilkAcilis"
        static let location = "ayar.konum"
        static let automaticLocation = "ayar.otomatikKonum"
        static let prayerTimeServer = "ayar.vakitSunucusu"
        static let notifications = "ayar.bildirimler"
        static let prayerTimeMethod = "ayar.vakitHesabi"
        static let notificationSound = "ayar.bildirimSesi"
        static let arabicSize = "ayar.arapcaBoyut"
        static let transliterationSize = "ayar.okunusBoyut"
        static let translationSize = "ayar.mealBoyut"
        static let showTransliteration = "ayar.okunusGoster"
        static let translations = "ayar.mealler"
        static let tajweed = "ayar.tecvid"
        static let mushafTajweed = "ayar.mushafTecvid"
        static let mushafEdition = "ayar.mushafFassung"
        static let openInMushaf = "ayar.mushaftaAc"
        static let transliterationLanguage = "ayar.okunusDili"
        static let tafsirLanguage = "ayar.tefsirDili"
        static let reciter = "ayar.kari"
        static let activeKhatm = "ayar.aktifHatim"
        static let live = "ayar.canliEtkinlik"
        static let word = "ayar.kelimeMeali"
        static let compassStyle = "ayar.pusulaStili"
        static let qiblaStart = "ayar.kibleBaslangici"
        static let qiblaLastMode = "ayar.kibleSonGorunum"
        static let quizGoal = "ayar.quizHedef"
        static let quizIntention = "ayar.quizNiyet"
        static let talksDubbing = "ayar.sohbetDublaj"
        static let duelName = "ayar.duelloAdi"
        static let karahatReminder = "ayar.kerahatHatirlat"
    }
}
