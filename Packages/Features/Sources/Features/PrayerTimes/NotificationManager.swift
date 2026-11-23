import Core
import DesignSystem
import Foundation
import Observation
import PrayerTimes
import UserData
import UserNotifications

#if canImport(AlarmKit) && os(iOS)
    import AlarmKit
    import SwiftUI
#endif

/// Schedules notifications and adhan alarms from the table.
///
/// Every call of `schedule` completely replaces everything pending of this app; the
/// planner delivers stable identifiers, so there are no duplicates.
@MainActor @Observable public final class NotificationManager {
    /// Scheduled up to this day („X tarihine kadar planlı“).
    public private(set) var lastDay: Day?
    public private(set) var allowed: UNAuthorizationStatus = .notDetermined
    public private(set) var alarmPermission = false

    public init() {}

    static func settings(_ a: AppSettings) -> [Prayer: NotificationSetting] {
        let ham =
            a.notificationData.flatMap {
                try? JSONDecoder().decode([String: NotificationSetting].self, from: $0)
            }
            ?? [:]
        return Dictionary(
            uniqueKeysWithValues: Prayer.allCases.map { ($0, ham[$0.rawValue] ?? .standard($0)) })
    }

    static func save(_ setting: [Prayer: NotificationSetting], _ a: AppSettings) {
        let ham = Dictionary(uniqueKeysWithValues: setting.map { ($0.key.rawValue, $0.value) })
        a.notificationData = try? JSONEncoder().encode(ham)
    }

    public func readPermissionStatus() async {
        allowed = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        #if canImport(AlarmKit) && os(iOS)
            alarmPermission = AlarmManager.shared.authorizationState == .authorized
        #endif
    }

    public func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [
            .alert, .sound, .badge,
        ])
        await readPermissionStatus()
    }

    public func requestAlarmPermission() async {
        #if canImport(AlarmKit) && os(iOS)
            _ = try? await AlarmManager.shared.requestAuthorization()
        #endif
        await readPermissionStatus()
    }

    /// Reschedule: at launch, in the background, after a location change or changed setting.
    public func schedule(table: PrayerTimeTable?, settings: AppSettings, now: Date = .now) async {
        await readPermissionStatus()
        guard let table else { return }
        let center = UNUserNotificationCenter.current()
        let setting = Self.settings(settings)
        let plan = NotificationPlan.schedule(
            table: table, settings: setting, now: now, karahatBefore: settings.karahatReminder ? 15 : 0,
            karahatMinutes: settings.karahatMinutes)
        let pending = await center.pendingNotificationRequests().map(\.identifier)
            .filter { $0.hasPrefix(NotificationPlan.prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        lastDay = plan.lastDay
        guard allowed == .authorized || allowed == .provisional else { return }
        let tz = table.location.timeZone
        for b in plan.notifications {
            let content = UNMutableNotificationContent()
            content.title = Self.title(b, table: table)
            content.body = Self.text(b, tz: tz, lastDay: plan.lastDay)
            content.sound =
                settings.notificationSound == "kisaEzan" && b.kind == .atTime
                ? UNNotificationSound(named: UNNotificationSoundName("ezan-kisa.caf")) : .default
            content.interruptionLevel = b.kind == .atTime || b.kind == .karahat ? .timeSensitive : .active
            content.userInfo = ["url": "kiblegah://vakit"]
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = tz
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents(
                    [.timeZone, .year, .month, .day, .hour, .minute], from: b.time),
                repeats: false)
            try? await center.add(
                UNNotificationRequest(identifier: b.identifier, content: content, trigger: trigger))
        }
        await scheduleAlarms(table: table, setting: setting, now: now)
    }

    static func title(_ b: ScheduledNotification, table: PrayerTimeTable) -> String {
        if b.kind == .karahat { return localized("bildirim.kerahat.baslik \(b.minutes)") }
        guard let n = b.prayer else { return localized("bildirim.hatirlatma.baslik") }
        let friday =
            table.day(Day(b.time, timeZoneIdentifier: table.location.timeZone)).map {
                DayTimeline(today: $0, tomorrow: nil).isFriday
            }
            ?? false
        let name = n.name(friday: friday && n == .dhuhr)
        return b.kind == .atTime
            ? localized("bildirim.vakti_girdi \(name)") : localized("bildirim.onceden \(name) \(b.minutes)")
    }

    static func text(_ b: ScheduledNotification, tz: TimeZone, lastDay: Day?) -> String {
        switch b.kind {
        case .atTime: localized("bildirim.vaktinde.metin \(b.time.timeText(tz))")
        case .minutesBefore:
            localized(
                "bildirim.onceden.metin \(b.time.addingTimeInterval(Double(b.minutes * 60)).timeText(tz))")
        case .reminder: localized("bildirim.hatirlatma.metin")
        case .karahat:
            if let k = b.karahat {
                localized(
                    "bildirim.kerahat.metin \(karahatName(k.kind)) \(k.start.timeText(tz)) \(k.end.timeText(tz))"
                )
            } else {
                ""
            }
        }
    }

    static func karahatName(_ t: KarahatWindow.Kind) -> String {
        switch t {
        case .atSunrise: localized("kerahat.tur.dogus")
        case .zawal: localized("kerahat.tur.zeval")
        case .atSunset: localized("kerahat.tur.batis")
        }
    }

    /// Full adhan as alarm for the chosen prayer times, seven days ahead.
    /// Fixed identifier per prayer and minute: if a second pass schedules the same prayer, it fails
    /// on the existing identifier instead of setting a second adhan.
    nonisolated static func alarmID(_ n: Prayer, _ time: Date) -> UUID {
        let i = Prayer.allCases.firstIndex(of: n) ?? 0
        let minutes = UInt64(max(0, time.timeIntervalSince1970 / 60))
        return UUID(uuidString: String(format: "6B69626C-%04X-4000-8000-%012llX", i, minutes))!
    }

    private func scheduleAlarms(
        table: PrayerTimeTable, setting: [Prayer: NotificationSetting], now: Date
    ) async {
        #if canImport(AlarmKit) && os(iOS)
            let motionManager = AlarmManager.shared
            for alarm in (try? motionManager.alarms) ?? [] { try? motionManager.cancel(id: alarm.id) }
            guard alarmPermission, setting.values.contains(where: \.fullAdhan) else { return }
            let end = now.addingTimeInterval(7 * 86400)
            for g in table.days {
                for n in Prayer.allCases where setting[n]?.fullAdhan == true {
                    let time = g[n]
                    guard time > now, time < end else { continue }
                    let presentation = AlarmPresentation(
                        alert: .init(
                            title: LocalizedStringResource(
                                stringLiteral: localized("bildirim.vakti_girdi \(n.name())")),
                            stopButton: AlarmButton(
                                text: LocalizedStringResource(
                                    stringLiteral: localized("bildirim.ezan.durdur")),
                                textColor: .white, systemImageName: "stop.fill")))
                    let attributes = AlarmAttributes<AdhanAlarm>(
                        presentation: presentation, metadata: AdhanAlarm(), tintColor: .orange)
                    _ = try? await motionManager.schedule(
                        id: Self.alarmID(n, time),
                        configuration: .alarm(
                            schedule: .fixed(time), attributes: attributes, sound: .named("ezan-tam.caf")))
                }
            }
        #endif
    }
}

#if canImport(AlarmKit) && os(iOS)
    struct AdhanAlarm: AlarmMetadata {}
#endif
