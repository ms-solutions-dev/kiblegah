import BackgroundTasks
import ContentPacks
import Core
import CoreSpotlight
import DesignSystem
import Features
import Quran
import SwiftData
import SwiftUI
import UserData

#if DEBUG
    import CoreData
#endif

// Optional packages of other app targets.

/// Entry point: register fonts, provide settings and router, resolve the theme.
@main
struct KiblegahApp: App {
    @State private var settings = KiblegahApp.openSettings()
    @State private var router: Router
    /// Diyanet's place list from the bundle: offline place search and Diyanet's coordinate per İlçe.
    @State private var prayerTimes = PrayerTimeModel(
        districts: Bundle.main.url(forResource: "Paketler", withExtension: nil)
            .flatMap { DistrictPack.find(folders: [$0]) })
    @State private var store = KiblegahApp.openStore()
    @State private var audioStore: AudioStore
    @State private var player: RecitationPlayer
    private let wordByWord = WordTranslations()
    /// What this app target plugs in at the UI entry points (created before the first screen).
    private let plugins: Plugins
    /// The content packages in the bundle; without Quran text the app still starts (areas show empty states).
    private let contentProvider: (any ContentProvider)? = Bundle.main.url(
        forResource: "Paketler", withExtension: nil
    )
    .flatMap { url in
            // Only packs marked as freely distributable.
            try? PackRegistry(folders: [url], store: true)
    }

    init() {
        // Before anything else: older settings from `standard` into the App Group.
        GroupDefaults.migrate()
            let e = Plugins()
        plugins = e
        // Tabs and jump targets follow the areas this app target ships with.
        _router = State(initialValue: Router(tabFilter: { e.provides($0) }, routes: { e.route($0) }))
        Typography.save()
        let ses = AudioStore()
        _audioStore = State(initialValue: ses)
        let o = RecitationPlayer(store: ses)
        _player = State(initialValue: o)
        // Widget „Kur'an dinle“: the button must find the player even without a scene ().
        ListenWidgetWriter.connect(o, contentProvider: contentProvider)
        Self.registerSpotlight()
    }

    /// Spotlight finds apps only by display name, and the matching does not fold ı to i: „kiblegah“
    /// did not find „Kıblegâh“. A separate entry with ASCII keywords opens the app.
    static func registerSpotlight() {
        let attributes = CSSearchableItemAttributeSet(contentType: .application)
        attributes.title = "Kıblegâh"
        attributes.contentDescription = "Namaz vakitleri · Kıble · Kur'an"
        attributes.keywords = [
            "kiblegah", "kıblegah", "kible", "kıble", "qibla", "namaz", "vakit", "ezan", "kuran", "quran",
        ]
        let item = CSSearchableItem(
            uniqueIdentifier: "dev.ms-solutions.kiblegah.uygulama", domainIdentifier: "uygulama",
            attributeSet: attributes)
        item.expirationDate = .distantFuture
        CSSearchableIndex.default().indexSearchableItems([item])
    }

    /// Load settings; in the debug build first take over launch arguments `-ayar.<schlüssel>`
    /// (screenshots without taps) so that they apply from the very first read.
    @MainActor static func openSettings() -> AppSettings {
        // Sources that require permission, from the Info key.
        FeatureFlags.load()
        // Relay address from the Info key.
        Relay.load()
        #if DEBUG
            let launchArguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
            let group = UserDefaults(suiteName: AppSettings.appGroup)
            for (k, v) in launchArguments where k.hasPrefix("ayar.") {
                let s = "\(v)"
                group?.set(s == "YES" ? true : s == "NO" ? false : (Double(s) as Any? ?? v), forKey: k)
            }
        #endif
        let a = AppSettings()
        return a
    }


    /// User data: with iCloud only if chosen (takes effect after restart). If the store fails,
    /// the app continues with a transient one instead of crashing.
    @MainActor static func openStore() -> UserStore {
        #if DEBUG
            if CommandLine.arguments.contains("-cloudKitSemaKur") { setUpCloudKitSchema() }
            // Check the duel room (package 5): writes and reads `duello-PROBE01-A`.
            if CommandLine.arguments.contains("-duelloProbe") {
                Task {
                    do {
                        let t = try await DuelRoom.save(
                            code: "PROBE01", name: "Probe", answers: [true, false, nil], finished: false)
                        print("duelloProbe: yazildi \(t)")
                        print("duelloProbe: okundu \(try await DuelRoom.load(code: "PROBE01"))")
                    } catch {
                        print("duelloProbe: \(error)")
                    }
                }
            }
        #endif
        let iCloud = UserDefaults(suiteName: AppSettings.appGroup)?.bool(forKey: "ayar.icloud") ?? false
        let container =
            (try? UserDataSchema.container(iCloud: iCloud)) ?? (try? UserDataSchema.container(iCloud: false))
            ?? (try! UserDataSchema.container(iCloud: false, inMemory: true))
        return UserStore(container: container)
    }

    #if DEBUG
        /// Demo state for screenshots (`-ornekVeri YES`): reading on the last five days, today
        /// included, 20 verses each in Al-Baqara (sequential index 8 = 2:1), and dhikr on four days.
        @MainActor static func addSampleData(_ store: UserStore) {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: .now)
            for back in 0..<5 {
                guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { continue }
                // Today shortly before now, the other days in the evening.
                let time = back == 0 ? Date.now.addingTimeInterval(-600) : day.addingTimeInterval(20 * 3600)
                let first = 8 + (4 - back) * 20
                store.addReading(firstIndex: first, lastIndex: first + 19, seconds: 540, date: time)
                if back < 4 { store.addDhikr("serbest", 33 * (back + 1), date: time) }
            }
            store.saveLastPosition("a:2:101")
        }

        /// Creates all data types in the CloudKit development schema (`CD_Notum` … `CD_SoruCevabi`) so that
        /// they can be deployed to Production in the CloudKit console (). SwiftData otherwise creates
        /// types only when a record of that type is synced. Start with
        /// `-cloudKitSemaKur`, in the simulator with a signed-in Apple ID; separate throwaway store.
        @MainActor static func setUpCloudKitSchema() {
            guard let model = NSManagedObjectModel.makeManagedObjectModel(for: UserDataSchema.models)
            else { return print("cloudKitSchema: no model") }
            let storeDescription = NSPersistentStoreDescription(
                url: URL.temporaryDirectory.appending(path: "sema.sqlite"))
            storeDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: "iCloud.dev.ms-solutions.kiblegah")
            storeDescription.shouldAddStoreAsynchronously = false
            let container = NSPersistentCloudKitContainer(name: "Kiblegah", managedObjectModel: model)
            container.persistentStoreDescriptions = [storeDescription]
            container.loadPersistentStores { _, loadError in
                if let loadError { print("cloudKitSema: \(loadError)") }
            }
            do {
                try container.initializeCloudKitSchema()
                print("cloudKitSchema: done")
            } catch {
                print("cloudKitSema: \(error)")
            }
        }
    #endif

    var body: some Scene {
        WindowGroup {
            ThemedRoot()
                #if DEBUG
                    .modifier(WidgetGallery(contentProvider: contentProvider))
                #endif
                .environment(settings)
                .environment(router)
                .environment(prayerTimes)
                .environment(prayerTimes.notification)
                .environment(store)
                .environment(audioStore)
                .environment(player)
                .modelContainer(store.container)
                .environment(\.contentProvider, contentProvider)
                .environment(\.wordByWord, wordByWord)
                .plugins(plugins)
                .onOpenURL { url in
                    router.open(url: url, tabs: settings.tabs)
                }
                // Pages should no longer compute or load anything on opening ().
                .task { Prewarm.start(contentProvider: contentProvider, wordByWord: wordByWord) }
                #if DEBUG
                    // Screenshots without taps: `simctl launch … -acilis kiblegah://bildirimler`.
                    .task {
                        // Memorization card without tapping: `-ezberKart a:112:1-4`.
                        if let k = UserDefaults.standard.string(forKey: "ezberKart") {
                            store.addToMemorization(k)
                        }
                        // Saved verses without tapping: `-kayitEkle a:2:255,a:4:1`.
                        for k in (UserDefaults.standard.string(forKey: "kayitEkle") ?? "").split(
                            separator: ",")
                        where !store.isSaved(String(k)) {
                            store.toggleSaved(String(k))
                        }
                        // After screenshots: reset quiz history to empty (`-quizSifirla YES`).
                        if UserDefaults.standard.bool(forKey: "quizSifirla") { store.deleteQuizHistory() }
                        // Screenshots with a lived-in state instead of zeros: `-ornekVeri YES` adds
                        // five days of reading (Al-Baqara from the start) and dhikr, once, into an empty store.
                        if UserDefaults.standard.bool(forKey: "ornekVeri"), store.sessions().isEmpty {
                            Self.addSampleData(store)
                        }
                        if let m = UserDefaults.standard.string(forKey: "acilis"), let url = URL(string: m) {
                            router.open(url: url, tabs: settings.tabs)
                        }
                    }
                #endif
        }
        // Background: refresh the supply and roll the notifications forward.
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await BackgroundRefresh.run(prayerTimes: prayerTimes, settings: settings)
        }
    }
}

/// Resolves the theme from the setting and the system color scheme.
private struct ThemedRoot: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PrayerTimeModel.self) private var prayerTimes
    @Environment(\.colorScheme) private var system
    @Environment(\.scenePhase) private var phase

    var body: some View {
        RootView()
            // Language change in Ayarlar: rebuild everything, carry over system texts and date formats.
            .id(settings.language)
            .environment(\.locale, AppLanguage.locale)
            .theme(
                Theme.parse(
                    appearance: settings.appearance, largeAndSimple: settings.largeAndSimple,
                    systemDark: system == .dark, isNight: prayerTimes.isNight(), palette: settings.palette)
            )
            .task(id: phase) {
                if phase == .active { await prayerTimes.start(settings) }
                if phase == .background { BackgroundRefresh.schedule() }
            }
    }
}

/// Background refresh: iOS occasionally wakes the app; then renew the supply and the plan.
enum BackgroundRefresh {
    static let identifier = "dev.ms-solutions.kiblegah.yenile"

    @MainActor static func run(prayerTimes: PrayerTimeModel, settings: AppSettings) async {
        await prayerTimes.start(settings)
        schedule()
    }

    /// Schedule the next run for six hours from now at the earliest.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
}
