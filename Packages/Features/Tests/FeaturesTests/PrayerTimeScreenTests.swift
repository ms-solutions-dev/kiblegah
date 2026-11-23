import ContentPacks
import Core
import Foundation
import PrayerTimes
import SwiftUI
import Testing

@testable import Features

@Suite struct CounterTests {
    @Test func decomposition() {
        let s = Counter(remaining: 5 * 3600 + 13 * 60 + 7.9)
        #expect(s == Counter(remaining: 5 * 3600 + 13 * 60 + 7))
        #expect(s.time == 5 && s.minutes == 13 && s.seconds == 7)
        #expect(Counter(remaining: -5).seconds == 0)
    }

    @Test func spokenRoundsUpNeverZero() {
        // Without an app catalog, ceviri returns the key including numbers - enough to check the numbers.
        #expect(Counter(remaining: 59).spoken.contains("1"))
        #expect(Counter(remaining: 3600 + 1).spoken.contains("1"))
        #expect(!Counter(remaining: 3 * 3600 + 20 * 60).spoken.contains("21"))
    }
}

@Suite struct VerseOfTheDayTests {
    @Test func oneVersePerDayAndChanges() {
        let a = VerseOfTheDay.key(Day(year: 2026, month: 10, day: 18))
        let b = VerseOfTheDay.key(Day(year: 2026, month: 10, day: 19))
        #expect(a != b)
        #expect(VerseOfTheDay.key(Day(year: 2026, month: 10, day: 18)) == a)
        #expect(Set(VerseOfTheDay.list).count == VerseOfTheDay.list.count)
    }
}

@MainActor @Suite struct PrayerTimeModelTests {
    @Test func isNight() async throws {
        let k = Location.sample
        let g = Day(year: 2026, month: 10, day: 18)
        let t = try await OnDeviceSource().table(location: k, start: g, dayCount: 2)
        let m = PrayerTimeModel(table: t)
        let day = try #require(t.day(g))
        #expect(m.isNight(day[.maghrib] + 60))
        #expect(!m.isNight(day[.dhuhr]))
        #expect(m.isNight(day[.imsak]))
    }
}

@MainActor @Suite struct LocationSearchTests {
    /// Diyanet places first; the same place from Apple Maps is dropped, a different place with the same name stays.
    @Test func diyanetPlacesFirstWithoutDuplicates() {
        let district = LocationService.PlaceResult(
            location: Location(
                name: "Hamburg", latitude: 53.5511, longitude: 9.9937, timeZoneIdentifier: "Europe/Berlin",
                diyanetDistrict: 10001),
            explanation: "Hamburg, Almanya")
        let mapResult = LocationService.PlaceResult(
            location: Location(
                name: "Hamburg", latitude: 53.5503, longitude: 9.9930,
                timeZoneIdentifier: "Europe/Berlin"),
            explanation: "Europe/Berlin")
        let hesse = LocationService.PlaceResult(
            location: Location(
                name: "Hamburg", latitude: 51.15, longitude: 8.80, timeZoneIdentifier: "Europe/Berlin"),
            explanation: "Europe/Berlin")
        #expect(LocationService.merge(local: [district], online: [mapResult, hesse]) == [district, hesse])
        #expect(LocationService(districts: nil).localSearch("hamburg").isEmpty)
    }
}

@Suite struct TajweedTests {
    @Test func colorsLandOnSpans() {
        let text = "ٱلْحَمْدُ لِلَّهِ"
        let a = tajweedText(
            text, spans: [TajweedSpan(rule: "hamzat_wasl", interval: 0..<1)], dark: false)
        let colored = a.runs.filter { $0.foregroundColor != nil }
        #expect(colored.count == 1)
        #expect(String(a[colored[0].range].characters).unicodeScalars.first == "ٱ".unicodeScalars.first)
    }
}

@Suite struct SearchViewTests {
    @Test func summaryAndHighlight() {
        let m =
            String(repeating: "x ", count: 60) + "Allah sabredenlerle beraberdir."
            + String(repeating: " y", count: 60)
        let o = summary(m, "sabır")
        #expect(o.contains("sabredenlerle") || o.contains("beraberdir"))
        #expect(o.hasPrefix("…"))
        let v = highlight("Sabır ve namazla yardım dileyin.", "sabir", color: .red)
        let emphasized = v.runs.filter { $0.inlinePresentationIntent == .stronglyEmphasized }.map {
            String(v[$0.range].characters)
        }
        #expect(emphasized == ["Sabır"])
    }
}

@Suite struct AlarmIdentifierTests {
    @Test func samePrayerSameID() {
        let time = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(NotificationManager.alarmID(.dhuhr, time) == NotificationManager.alarmID(.dhuhr, time))
        #expect(NotificationManager.alarmID(.dhuhr, time) != NotificationManager.alarmID(.asr, time))
        #expect(
            NotificationManager.alarmID(.dhuhr, time)
                != NotificationManager.alarmID(.dhuhr, time.addingTimeInterval(86_400)))
    }
}

@MainActor @Test func ishaAfterMidnightIsYesterday() throws {
    let tz = try #require(TimeZone(identifier: "Europe/Berlin"))
    let isha = Date(timeIntervalSince1970: 1_792_346_100)  // Oct 18, 2026 19:55 CEST
    #expect(NextPrayerCard.isYesterday(isha, time: isha + 5 * 3600, tz: tz))
    #expect(!NextPrayerCard.isYesterday(isha, time: isha + 2 * 3600, tz: tz))
}
