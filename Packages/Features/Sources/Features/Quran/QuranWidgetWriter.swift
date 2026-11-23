import ContentPacks
import Core
import Foundation
import PrayerTimes
import Quran
import UserData
import WidgetBridge

#if os(iOS)
    import WidgetKit
#endif

/// Writes the snapshots of the Quran widgets (reading statistics, Günün ayeti)
/// when the app comes to the foreground or goes to the background - not after every verse
/// read: WidgetKit allows only a quota of reloads per day.
enum QuranWidgetWriter {
    static let dayCount = 14

    @MainActor static func save(
        store: UserStore, settings: AppSettings, contentProvider: (any ContentProvider)?
    ) {
        reading(store: store, settings: settings, contentProvider: contentProvider).save()
        if let contentProvider { verses(contentProvider).save() }
        #if os(iOS)
            WidgetCenter.shared.reloadTimelines(ofKind: ReadingSnapshot.kind)
            WidgetCenter.shared.reloadTimelines(ofKind: VerseSnapshot.kind)
        #endif
    }

    @MainActor static func reading(
        store: UserStore, settings: AppSettings, contentProvider: (any ContentProvider)?
    ) -> ReadingSnapshot {
        let o = store.readingSummary()
        let k = settings.activeKhatm
        let place = (store.lastPosition(khatm: k) ?? store.lastPosition()).flatMap { ContentKey(text: $0) }
        var title: String?
        var link: URL?
        if case .verse(let s, let n)? = place, let surah = contentProvider?.surah(s) {
            title = "\(surah.name(language: translationLanguage())) \(n)"
            link = URL(string: "kiblegah://kuran/\(s):\(n)")
        }
        let readCount = store.versesReadCount(khatm: k)
        let goal = store.goal(k).map { h -> ReadingSnapshot.Goal in
            let today = ReadingStats.summary(
                store.sessions(khatm: k), day: .now, pageStarts: contentProvider.map(pageStarts) ?? [])
            return ReadingSnapshot.Goal(
                kind: h.kind.rawValue, actual: ReadingStats.value(today, h.kind),
                target: ReadingStats.dailyGoal(h, readCount: readCount, readToday: today.verse))
        }
        let a = ReadingSnapshot(
            day: Calendar.current.startOfDay(for: .now), todayVerses: o.todayVerses,
            todayMinutes: o.todayMinutes,
            weekStart: o.weekStart, weekMinutes: o.weekMinutes, weekVerses: o.weekVerses, streak: o.streak,
            khatmVerses: readCount, lastPosition: title,
            link: link, goal: goal)
        #if os(iOS)
            WatchSender.shared.gonder(reading: a)
        #endif
        return a
    }

    /// The same list as the card on Bugün (`VerseOfTheDay`), translation in the app language.
    static func verses(_ contentProvider: any ContentProvider, now: Date = .now) -> VerseSnapshot {
        let calendar = Calendar.current
        let pack = contentProvider.translations(language: translationLanguage()).first
        let days = (0..<dayCount).compactMap { i -> VerseSnapshot.DailyEntry? in
            guard let d = calendar.date(byAdding: .day, value: i, to: calendar.startOfDay(for: now)) else {
                return nil
            }
            let a = VerseOfTheDay.key(Day(d, timeZoneIdentifier: calendar.timeZone))
            guard case .verse(let s, let n) = a, let surah = contentProvider.surah(s),
                let verse = contentProvider.verse(a)
            else {
                return nil
            }
            let translation = pack.flatMap { contentProvider.translation(a, pack: $0.id) }?.text ?? ""
            return VerseSnapshot.DailyEntry(
                day: d, title: "\(surah.name(language: translationLanguage())) \(n)", arabic: verse.text,
                translation: translation,
                source: pack?.title ?? "", link: URL(string: "kiblegah://kuran/\(s):\(n)"))
        }
        return VerseSnapshot(days: days)
    }
}

/// Snapshot and button of the „Kur'an dinle“ widget ().
public enum ListenWidgetWriter {
    /// Records what is in the player; without a running Kuyruk the last state stays.
    @MainActor public static func save(_ o: RecitationPlayer, contentProvider: (any ContentProvider)?) {
        guard let s = o.current, let surah = contentProvider?.surah(s.surah) else { return }
        ListenSnapshot(
            surah: s.surah, verse: s.verse, surahName: surah.name(language: translationLanguage()),
            verseCount: surah.verseCount,
            reciter: o.reciter.name, isPlaying: o.isPlaying
        ).save()
        #if os(iOS)
            WidgetCenter.shared.reloadTimelines(ofKind: ReadingSnapshot.kind)
        #endif
    }

    /// Proves the path from the widget button into the player; the app calls this in `init`.
    @MainActor public static func connect(_ o: RecitationPlayer, contentProvider: (any ContentProvider)?) {
        ListenHandoff.toggle = { surah, verse in
            if let s = o.current, s.surah == surah {
                o.togglePause()
            } else {
                guard let su = contentProvider?.surah(surah) else { return false }
                // Without a scene there is no `AppSettings` object: read the values directly from the store.
                let d = UserDefaults(suiteName: AppSettings.appGroup)
                let on = "ayar" + "."
                o.reciter = Reciter.find(d?.string(forKey: on + "kari") ?? "")
                o.play(surah: surah, verseCount: su.verseCount, verse: verse)
            }
            save(o, contentProvider: contentProvider)
            return true
        }
    }
}
