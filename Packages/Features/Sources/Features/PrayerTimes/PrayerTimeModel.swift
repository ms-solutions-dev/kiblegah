import Core
import Foundation
import Observation
import PrayerTimes
import UserData

/// Holds the table for the UI package: load stock, reload, track place.
@MainActor @Observable public final class PrayerTimeModel {
    public private(set) var table: PrayerTimeTable?
    public private(set) var isLoading = false
    /// A place that differs significantly from the saved one - the banner asks.
    public private(set) var suggestedLocation: Location?
    /// Kandil and Eid of the current year (Diyanet preferred).
    public private(set) var religiousDays: [ReligiousDay] = []

    private var store: PrayerTimesStore?
    /// Server and calculation method with which `store` is built.
    private var storeSetting: String?
    /// Diyanet's place list without network (bundle `district`); `nil` if the bundle is missing.
    let districts: (any DistrictDirectory)?
    let locationService: LocationService
    /// Reschedules after every load.
    public let notification = NotificationManager()
    /// From this distance a location counts as a location change.
    static let locationChangeMeters = 15_000.0

    public init(districts: (any DistrictDirectory)? = nil) {
        self.districts = districts
        locationService = LocationService(districts: districts)
    }

    /// For previews and tests: a fixed table.
    init(table: PrayerTimeTable) {
        districts = nil
        locationService = LocationService()
        self.table = table
    }

    var noLocationPermission: Bool { locationService.status == .noPermission }

    /// No own prayer-time service in this build: times are calculated on the device.
    func server(_ settings: AppSettings) -> ServerSource? { nil }

    /// „Konumuma göre“ calculates with the location: then neither Diyanet coordinate nor server table.
    private func prepareStore(_ settings: AppSettings) -> PrayerTimesStore {
        let setting = settings.prayerTimeMethod.rawValue
        if let store, storeSetting == setting { return store }
        let diyanet = settings.prayerTimeMethod == .diyanet
        let yeni = PrayerTimesStore(
            folder: PrayerTimesStore.defaultFolder(appGroup: AppSettings.appGroup),
            source: HybridSource(
                server: diyanet ? server(settings) : nil,
                device: OnDeviceSource(districts: diyanet ? districts : nil)))
        store = yeni
        storeSetting = setting
        return yeni
    }

    /// After a change of calculation method, fetch the table again.
    func changeCalculation(_ settings: AppSettings) async {
        guard let k = settings.location else { return }
        await refresh(k, settings: settings, force: true)
    }

    /// At launch and when returning to the app.
    public func start(_ settings: AppSettings) async {
        let d = prepareStore(settings)
        if table == nil { table = await d.stored() }
        if let k = settings.location { await refresh(k, settings: settings) }
        // No system prompt before onboarding: there a custom screen explains first.
        if settings.onboardingDone, settings.automaticLocation, locationService.status != .noPermission {
            await checkLocation(settings)
        }
    }

    /// The running `refresh` pass; the next one waits for it, so that launch, foreground and
    /// location change do not reschedule notifications and alarms at the same time.
    private var refreshTask: Task<Void, Never>?

    func refresh(_ location: Location, settings: AppSettings, force: Bool = false) async {
        let previous = refreshTask
        let loadTask = Task {
            await previous?.value
            await refreshSequentially(location, settings: settings, force: force)
        }
        refreshTask = loadTask
        await loadTask.value
    }

    private func refreshSequentially(_ location: Location, settings: AppSettings, force: Bool) async {
        isLoading = true
        defer { isLoading = false }
        table = await prepareStore(settings).update(location: location, force: force)
        await loadReligiousDays(settings)
        await notification.schedule(table: table, settings: settings)
        if let table { WidgetWriter.save(table, settings: settings) }
    }

    private func loadReligiousDays(_ settings: AppSettings) async {
        guard let table else { return }
        let year = Day(.now, timeZoneIdentifier: table.location.timeZone).year
        if let s = server(settings), let l = try? await s.religiousDays(year: year), !l.isEmpty {
            religiousDays = l
        } else {
            religiousDays = ReligiousDay.calculate(year: year, adjustment: HijriDate.adjustment(table))
        }
    }

    /// Fetch GPS location; adopt it if there is no saved place, otherwise ask on location change.
    ///
    /// `requested`: the user tapped „Konumumu kullan“ – then the location applies at once, even
    /// when it is less than `locationChangeMeters` away from the saved place.
    /// - Returns: `false` when no location could be obtained.
    @discardableResult
    func checkLocation(_ settings: AppSettings, requested: Bool = false) async -> Bool {
        guard let place = await locationService.currentLocation() else { return false }
        let yeni = await locationService.location(place, server: server(settings))
        if requested {
            await selectLocation(yeni, settings: settings, automatic: true)
        } else if let old = settings.location {
            if old.distance(yeni) > Self.locationChangeMeters { suggestedLocation = yeni }
        } else {
            settings.location = yeni
            await refresh(yeni, settings: settings, force: true)
        }
        return true
    }

    func selectLocation(_ k: Location, settings: AppSettings, automatic: Bool) async {
        settings.location = k
        settings.automaticLocation = automatic
        suggestedLocation = nil
        await refresh(k, settings: settings, force: true)
    }

    func dismissSuggestion() { suggestedLocation = nil }

    /// For the theme „vakte göre“: between Maghrib and Sunrise it is night.
    public func isNight(_ time: Date = .now) -> Bool {
        guard let t = table else { return false }
        let today = Day(time, timeZoneIdentifier: t.location.timeZone)
        guard let g = t.day(today) else { return false }
        return time >= g[.maghrib] || time < g[.sunrise]
    }

    /// The next Kandil/Eid from today, at most `day` days ahead.
    func upcomingReligiousDay(today: Day, day: Int = 3) -> ReligiousDay? {
        religiousDays.first { $0.day >= today && $0.day <= today.added(day) }
    }
}
