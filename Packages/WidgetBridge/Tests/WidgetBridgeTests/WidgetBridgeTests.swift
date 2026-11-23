import Foundation
import Testing

@testable import WidgetBridge

@Suite struct PrayerTimesSnapshotTests {
    let t0 = Date(timeIntervalSince1970: 1_792_300_000)

    func snapshot() -> PrayerTimesSnapshot {
        let names = ["imsak", "gunes", "ogle", "ikindi", "aksam", "yatsi"]
        var v: [PrayerTimesSnapshot.PrayerTime] = []
        for day in 0..<2 {
            for (i, a) in names.enumerated() {
                v.append(
                    .init(
                        identifier: a, name: a, time: t0 + Double(day * 86400 + (i + 1) * 3 * 3600),
                        prayer: a != "gunes"))
            }
        }
        let sunrise = v[1].time
        return PrayerTimesSnapshot(
            location: "Hamburg", timeZoneIdentifier: "Europe/Berlin", calculated: true, prayerTimes: v,
            karahatWindows: [.init(start: sunrise, end: sunrise + 45 * 60)], qiblaAngle: 131, created: t0)
    }

    @Test func timelineAtEveryBoundary() {
        let a = snapshot()
        let z = a.timeline(now: t0)
        #expect(z.first?.next.identifier == "imsak")
        // Start + 9 times in 36 h (day 1 every six, day 2 up to 33 h) + Karahat end.
        #expect(z.count == 1 + 9 + 1)
        let karahat = z.first { $0.karahatEnd != nil }
        #expect(karahat?.current?.identifier == "gunes")
        #expect(z.allSatisfy { $0.next.time > $0.date })
    }

    @Test func supplyExhausted() {
        #expect(snapshot().entry(time: t0 + 3 * 86400) == nil)
    }

    @Test func fileRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "anlik-\(UUID()).json")
        snapshot().save(url)
        #expect(PrayerTimesSnapshot.load(url) == snapshot())
    }
}

/// The time logic of the Nabız prayer widget on the Kıblegâh snapshot ().
@Suite struct PrayerStatusTests {
    let t0 = Date(timeIntervalSince1970: 1_792_300_000)

    /// Güneş 06:00, Öğle 12:00, Akşam 18:00 from t0; Karahat after Güneş 45 min, before Öğle 10 min, before Akşam 40 min.
    func snapshot() -> PrayerTimesSnapshot {
        let time: [(String, Double)] = [
            ("imsak", 4.5), ("gunes", 6), ("ogle", 12), ("ikindi", 15), ("aksam", 18), ("yatsi", 19.5),
        ]
        let v = time.map {
            PrayerTimesSnapshot.PrayerTime(
                identifier: $0.0, name: $0.0, time: t0 + $0.1 * 3600, prayer: $0.0 != "gunes")
        }
        let k: [PrayerTimesSnapshot.Karahat] = [
            .init(start: t0 + 6 * 3600, end: t0 + 6 * 3600 + 45 * 60),
            .init(start: t0 + 12 * 3600 - 10 * 60, end: t0 + 12 * 3600),
            .init(start: t0 + 18 * 3600 - 40 * 60, end: t0 + 18 * 3600),
        ]
        return PrayerTimesSnapshot(
            location: "L", timeZoneIdentifier: "Europe/Berlin", calculated: true, prayerTimes: v,
            karahatWindows: k,
            qiblaAngle: nil, created: t0)
    }

    @Test func trafficLightByMinutes() {
        let a = snapshot()
        // 10:00 → Öğle in 2 h, Zeval window only at 11:50: green, target Öğle.
        let d = PrayerStatus.status(a, now: t0 + 10 * 3600)
        #expect(d?.kind == .target && d?.name == "ogle" && d?.signal == .green)
        // 11:25 → Zeval window begins in 25 min (≤ 30) before Öğle: countdown to the start, orange.
        let w = PrayerStatus.status(a, now: t0 + 11 * 3600 + 25 * 60)
        #expect(w?.karahatKind == .zawal && w?.target == t0 + 12 * 3600 - 10 * 60 && w?.signal == .orange)
        // 11:40 → 10 min until the window: red.
        #expect(PrayerStatus.status(a, now: t0 + 11 * 3600 + 40 * 60)?.signal == .red)
    }

    @Test func inWindowAndPrayerTime() {
        let a = snapshot()
        let k = PrayerStatus.status(a, now: t0 + 6 * 3600 + 10 * 60)
        #expect(k?.kind == .karahat && k?.karahatKind == .sunrise && k?.target == t0 + 6 * 3600 + 45 * 60)
        let v = PrayerStatus.status(a, now: t0 + 15 * 3600 + 20)
        #expect(v?.kind == .prayerTime && v?.name == "ikindi")
        #expect(PrayerStatus.status(a, now: t0 + 15 * 3600 + 50)?.kind == .target)
    }

    @Test func exhaustedAndSwitch() {
        let a = snapshot()
        #expect(PrayerStatus.status(a, now: t0 + 20 * 3600) == nil)
        let w = PrayerStatus.changes(a, after: t0 + 10 * 3600)
        #expect(w.contains(t0 + 12 * 3600 - 10 * 60 - 30 * 60))  // Warning start before Zeval
        #expect(w.contains(t0 + 12 * 3600 + 45))  // End of „vakti“
        #expect(w == w.sorted() && w.allSatisfy { $0 > t0 + 10 * 3600 })
    }
}
