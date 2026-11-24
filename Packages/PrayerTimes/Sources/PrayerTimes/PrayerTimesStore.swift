import Core
import Foundation

/// The stock in the App Group container: at least 30 days per location, so that the app, widgets
/// and Bildirimler keep working even without network.
public actor PrayerTimesStore {
    public static let targetDay = 30
    /// Below this many remaining days, more is fetched.
    public static let refreshThreshold = 25

    let file: URL
    let source: any PrayerTimeSource
    private var cache: PrayerTimeTable?

    public init(folder: URL, source: any PrayerTimeSource) {
        file = folder.appending(path: "vakit.json")
        self.source = source
    }

    /// The App Group folder, otherwise Application Support (tests, Mac).
    public static func defaultFolder(appGroup: String) -> URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? URL.applicationSupportDirectory
    }

    /// The stored table, without network.
    public func stored() -> PrayerTimeTable? {
        if let cache { return cache }
        guard let veri = try? Data(contentsOf: file) else { return nil }
        cache = try? JSONDecoder().decode(PrayerTimeTable.self, from: veri)
        return cache
    }

    /// Fetches more when the location changed, the stock runs low, or a Diyanet table
    /// is only available as calculated. If everything fails, the old stock stays.
    @discardableResult
    public func update(location: Location, now: Date = Date(), force: Bool = false) async -> PrayerTimeTable?
    {
        let today = Day(now, timeZoneIdentifier: location.timeZone)
        let old = stored()
        let samePlace = old?.location == location
        let enough = (old?.daysRemaining(today: today) ?? 0) >= Self.refreshThreshold
        let diyanetExpected = location.diyanetDistrict != nil && old?.source == .calculated
        // Knock on the server again at most every 6 hours if it was missing last time.
        let recent = old.map { now.timeIntervalSince($0.fetchedAt) < 6 * 3600 } ?? false
        // Without a Diyanet İlçe the device calculates anyway; calculating fresh costs nothing and
        // picks up an improved method immediately instead of only after 25 days.
        let calculatedOnly = location.diyanetDistrict == nil && old?.source == .calculated
        if !force, samePlace, enough, !calculatedOnly, !(diyanetExpected && !recent) { return old }
        // From yesterday on: between midnight and İmsak the current time is still yesterday's Yatsı, and
        // without that day its start fell back to 0:00 (iPad, 24.11.).
        guard
            let yeni = try? await source.table(
                location: location, start: today.added(-1), dayCount: Self.targetDay + 6)
        else { return old }
        // Calculated days only extend a Diyanet table of the same location at the end.
        let result =
            samePlace && yeni.source == .calculated && old?.source == .diyanet
            ? old!.complete(yeni, today: today) : yeni
        save(result)
        return result
    }

    func save(_ t: PrayerTimeTable) {
        cache = t
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let veri = try? JSONEncoder().encode(t) { try? veri.write(to: file, options: .atomic) }
    }
}
