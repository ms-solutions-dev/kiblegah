import Core
import Foundation
import PrayerTimes
import Qibla
import UserData
import WidgetBridge

#if os(iOS)
    import ActivityKit
    import WidgetKit
#endif

/// Writes the widget snapshot and keeps the Live Activity up to date.
enum WidgetWriter {
    /// Days in the snapshot after today: widget and Watch thus keep showing times for two weeks without
    /// an app launch instead of "App öffnen".
    static let daysAhead = 14

    @MainActor static func save(_ t: PrayerTimeTable, settings: AppSettings) {
        let today = Day(.now, timeZoneIdentifier: t.location.timeZone)
        var prayerTimes: [PrayerTimesSnapshot.PrayerTime] = []
        var karahatWindows: [PrayerTimesSnapshot.Karahat] = []
        for g in t.days where g.day >= today.added(-1) && g.day <= today.added(daysAhead) {
            let friday = DayTimeline(today: g, tomorrow: nil).isFriday
            for n in Prayer.allCases {
                prayerTimes.append(
                    .init(
                        identifier: n.rawValue, name: n.name(friday: friday && n == .dhuhr), time: g[n],
                        prayer: n.isPrayer))
            }
            for k in DayTimeline(today: g, tomorrow: nil, karahatMinutes: settings.karahatMinutes)
                .karahatWindows
            {
                karahatWindows.append(.init(start: k.start, end: k.end))
            }
        }
        let a = PrayerTimesSnapshot(
            location: t.location.name, timeZoneIdentifier: t.location.timeZoneIdentifier,
            calculated: t.source == .calculated,
            prayerTimes: prayerTimes, karahatWindows: karahatWindows,
            qiblaAngle: QiblaCalculation.angle(t.location),
            created: .now,
            latitude: t.location.latitude, longitude: t.location.longitude)
        a.save()
        #if os(iOS)
            WidgetCenter.shared.reloadAllTimelines()
            WatchSender.shared.gonder(a)
            Task { await liveActivity(a, light: settings.liveActivity) }
        #endif
    }

    #if os(iOS)
        /// Ends old activities and starts one that lasts until the next prayer (at most 8 h per iOS).
        static func liveActivity(_ a: PrayerTimesSnapshot, light: Bool) async {
            for e in Activity<VakitEtkinligi>.activities { await e.end(nil, dismissalPolicy: .immediate) }
            guard light, ActivityAuthorizationInfo().areActivitiesEnabled, let g = a.entry(time: .now) else {
                return
            }
            let status = VakitEtkinligi.ContentState(
                nextName: g.next.name, nextTime: g.next.time, karahatEnd: g.karahatEnd)
            _ = try? Activity.request(
                attributes: VakitEtkinligi(location: a.location),
                content: .init(state: status, staleDate: g.next.time.addingTimeInterval(60)))
        }
    #endif
}
