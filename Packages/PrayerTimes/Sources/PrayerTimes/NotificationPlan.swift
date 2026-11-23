import Core
import Foundation

/// Setting for a prayer time: notify at the time and/or remind beforehand.
public struct NotificationSetting: Codable, Sendable, Hashable {
    enum CodingKeys: String, CodingKey {
        case atTime = "vaktinde"
        case minutesBefore = "onceden"
        case fullAdhan = "tamEzan"
    }

    public var atTime: Bool
    /// Minutes beforehand; 0 means off. Selectable: 10, 15, 20, 30, 45, 60.
    public var minutesBefore: Int
    /// Full adhan as an alarm (AlarmKit), rings even in silent mode.
    public var fullAdhan: Bool

    public init(atTime: Bool, minutesBefore: Int = 0, fullAdhan: Bool = false) {
        self.atTime = atTime
        self.minutesBefore = minutesBefore
        self.fullAdhan = fullAdhan
    }

    public static let minutesBeforeOptions = [0, 10, 15, 20, 30, 45, 60]

    /// Five prayers on, Güneş off - „5 vakit açık“.
    public static func standard(_ n: Prayer) -> NotificationSetting {
        NotificationSetting(atTime: n.isPrayer)
    }
}

/// A scheduled notification.
public struct ScheduledNotification: Hashable, Sendable {
    public enum Kind: String, Sendable {
        case atTime = "vaktinde", minutesBefore = "onceden", reminder = "hatirlatma", karahat = "kerahat"
    }

    /// Stable per event, so rescheduling does not duplicate the same notification.
    public let identifier: String
    public let time: Date
    public let prayer: Prayer?
    public let kind: Kind
    public let minutes: Int
    /// For `.karahat`: which window and when it ends.
    public var karahat: KarahatWindow? = nil
}

/// Rolling scheduling within the iOS limit of 64 pending notifications.
///
/// Scheduling runs from now in chronological order until the limit is reached; one slot is kept
/// for the reminder „open the app once“, two days before the last scheduled day.
/// Every rescheduling (launch, background, location change) moves the window further.
public enum NotificationPlan {
    public static let limit = 64
    public static let prefix = "vakit."

    public struct Outcome: Sendable {
        public let notifications: [ScheduledNotification]
        /// Everything up to this day (inclusive) is scheduled - „X tarihine kadar planlı“.
        public let lastDay: Day?
    }

    /// - Parameters:
    ///   - kerahatOnce: minutes before each Karahat window to remind; 0 = off.
    ///   - kerahatDakika: duration of the Karahat after sunrise as in Ayarlar.
    public static func schedule(
        table: PrayerTimeTable, settings: [Prayer: NotificationSetting], now: Date,
        limit: Int = NotificationPlan.limit,
        karahatBefore: Int = 0, karahatMinutes: Int = 45
    ) -> Outcome {
        var all: [ScheduledNotification] = []
        for g in table.days where karahatBefore > 0 {
            for k in DayTimeline(today: g, tomorrow: nil, karahatMinutes: karahatMinutes).karahatWindows {
                all.append(
                    .init(
                        identifier: "\(prefix)\(g.day).kerahat.\(k.kind.rawValue)",
                        time: k.start.addingTimeInterval(-Double(karahatBefore * 60)), prayer: nil,
                        kind: .karahat,
                        minutes: karahatBefore, karahat: k))
            }
        }
        for g in table.days {
            for n in Prayer.allCases {
                let a = settings[n] ?? .standard(n)
                let time = g[n]
                if a.atTime {
                    all.append(
                        .init(
                            identifier: "\(prefix)\(g.day).\(n.rawValue).0", time: time, prayer: n,
                            kind: .atTime,
                            minutes: 0))
                }
                if a.minutesBefore > 0 {
                    all.append(
                        .init(
                            identifier: "\(prefix)\(g.day).\(n.rawValue).\(a.minutesBefore)",
                            time: time.addingTimeInterval(-Double(a.minutesBefore * 60)), prayer: n,
                            kind: .minutesBefore,
                            minutes: a.minutesBefore))
                }
            }
        }
        let upcoming = all.filter { $0.time > now }.sorted { $0.time < $1.time }
        guard !upcoming.isEmpty else { return Outcome(notifications: [], lastDay: nil) }

        // Schedule whole days only: half a day would make „scheduled until X“ a lie.
        let tz = table.location.timeZone
        var selected = Array(upcoming.prefix(limit - 1))
        var lastDay = Day(selected.last!.time, timeZoneIdentifier: tz)
        if selected.count < upcoming.count {
            let firstOutside = Day(upcoming[selected.count].time, timeZoneIdentifier: tz)
            if firstOutside == lastDay {
                selected.removeAll { Day($0.time, timeZoneIdentifier: tz) == lastDay }
                lastDay = lastDay.added(-1)
            }
        } else {
            lastDay = table.lastDay ?? lastDay
        }
        // Reminder two days before the end, in the evening after Akşam, so it does not disturb the prayer.
        let reminderDay = lastDay.added(-2)
        if let g = table.day(reminderDay) {
            let time = g[.maghrib].addingTimeInterval(30 * 60)
            if time > now {
                selected.append(
                    .init(
                        identifier: "\(prefix)hatirlatma", time: time, prayer: nil, kind: .reminder,
                        minutes: 0))
            }
        }
        return Outcome(
            notifications: selected.sorted { $0.time < $1.time }, lastDay: selected.isEmpty ? nil : lastDay)
    }
}
