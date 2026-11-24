#if DEBUG
    import ContentPacks
    import Core
    import DesignSystem
    import SwiftUI
    import WidgetBridge

    /// Debug only: `-widgetGaleri 22` or `23` lays the large widgets out like the canvas boards, because screenshots
    /// cannot place widgets on the Home Screen. `-widgetAmpel orange|red` sets the traffic light,
    /// `-widgetVers 2:255` picks another verse. Sample values as on the boards, verse text from the packs.
    struct WidgetGallery: ViewModifier {
        let contentProvider: (any ContentProvider)?
        private let board = UserDefaults.standard.integer(forKey: "widgetGaleri")

        func body(content: Content) -> some View {
            content.overlay {
                if board != 0 { gallery.ignoresSafeArea() }
            }
        }

        private var now: Date { .now }

        private func today(_ hour: Int, _ minute: Int) -> Date {
            Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
        }

        /// The boards show the state at 14:36, whatever the clock of the simulator says.
        private var shown: Date { today(14, 36) }

        private var status: PrayerStatus {
            let target = now.addingTimeInterval(3981)
            let signal: PrayerStatus.Signal =
                switch UserDefaults.standard.string(forKey: "widgetAmpel") {
                case "orange": .orange
                case "red": .red
                default: .green
                }
            return PrayerStatus(
                kind: .target, name: "Asr", karahatKind: nil, time: today(15, 42), target: target,
                start: now.addingTimeInterval(-6500), end: target, signal: signal)
        }

        private var snapshot: PrayerTimesSnapshot {
            let times: [(String, String, Int, Int, Bool)] = [
                ("imsak", "Fajr", 6, 0, true), ("gunes", "Sonnenaufgang", 7, 26, false),
                ("ogle", "Dhuhr", 12, 53, true), ("ikindi", "Asr", 15, 42, true),
                ("aksam", "Maghrib", 18, 9, true), ("yatsi", "Isha", 19, 30, true),
            ]
            return PrayerTimesSnapshot(
                location: "Köln", timeZoneIdentifier: TimeZone.current.identifier, calculated: true,
                prayerTimes: times.map {
                    .init(identifier: $0.0, name: $0.1, time: today($0.2, $0.3), prayer: $0.4)
                }, karahatWindows: [], qiblaAngle: nil, created: now)
        }

        private var reading: ReadingSnapshot {
            ReadingSnapshot(
                day: Calendar.current.startOfDay(for: now), todayVerses: 24, todayMinutes: 7,
                weekStart: Calendar.current.dateInterval(of: .weekOfYear, for: now)?.start ?? now,
                weekMinutes: [18, 42, 0, 27, 32, 0, 0], weekVerses: 96, streak: 2, khatmVerses: 1450,
                lastPosition: "Al-Baqara 6", link: URL(string: "kiblegah://kuran/2:6"))
        }

        private let goal = PadQuranGoal(
            surah: 2, verse: 6, title: "Al-Baqara 6", bottom: nil, isPlaying: false)

        private var verse: VerseSnapshot.DailyEntry? {
            let parts = (UserDefaults.standard.string(forKey: "widgetVers") ?? "2:2").split(separator: ":")
                .compactMap { Int($0) }
            guard parts.count == 2, let contentProvider else { return nil }
            let key = ContentKey.verse(surah: parts[0], verse: parts[1])
            guard let text = contentProvider.verse(key), let surah = contentProvider.surah(parts[0]) else {
                return nil
            }
            let pack = contentProvider.translations(language: "de").first
            return .init(
                day: now, title: "\(surah.name(language: "de")) \(parts[1])", arabic: text.text,
                translation: pack.flatMap { contentProvider.translation(key, pack: $0.id) }?.text ?? "",
                source: pack?.title ?? "", link: URL(string: "kiblegah://kuran/\(parts[0]):\(parts[1])"))
        }

        private func frame<V: View>(_ extraLarge: Bool, @ViewBuilder _ v: () -> V) -> some View {
            v()
                .padding(16)
                .frame(width: extraLarge ? 690 : 330, height: extraLarge ? 330 : 345)
                .background {
                    RoundedRectangle(cornerRadius: 24).fill(WidgetColor.background)
                        .shadow(color: .black.opacity(0.28), radius: 15, y: 10)
                }
        }

        private func prayer(_ extraLarge: Bool) -> some View {
            frame(extraLarge) {
                PadPrayerWidget(date: shown, status: status, snapshot: snapshot, extraLarge: extraLarge)
            }
        }

        private func quran(_ extraLarge: Bool) -> some View {
            frame(extraLarge) {
                PadQuranWidget(date: shown, goal: goal, reading: reading, extraLarge: extraLarge)
            }
        }

        @ViewBuilder private func verseWidget(_ extraLarge: Bool) -> some View {
            if let verse {
                frame(extraLarge) { PadVerseWidget(verse: verse, extraLarge: extraLarge) }
            }
        }

        private var gallery: some View {
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: PadColor.galleryBackdrop,
                    startPoint: .topLeading, endPoint: .bottomTrailing)
                if board == 22 {
                    HStack(spacing: 40) {
                        prayer(false)
                        quran(false)
                        verseWidget(false)
                    }
                    .offset(x: 40, y: 49)
                    prayer(true).offset(x: 40, y: 445)
                } else {
                    quran(true).offset(x: 245, y: 61)
                    verseWidget(true).offset(x: 245, y: 445)
                }
            }
        }
    }
#endif
