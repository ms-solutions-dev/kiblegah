import Core
import Foundation
import Testing

@testable import PrayerTimes

@Suite struct DayTests {
    @Test func textAndOrder() {
        let g = Day(text: "2026-10-18")
        #expect(g?.description == "2026-10-18")
        #expect(g?.weekday == 1)  // Sunday
        #expect(g?.added(14) == Day(year: 2026, month: 11, day: 1))
        #expect(Day(text: "2026-13-01") == nil)
        #expect(Day(year: 2026, month: 12, day: 31) < Day(year: 2027, month: 1, day: 1))
    }

    @Test func hijriDiyanetSpelling() {
        #expect(HijriDate(diyanet: "7 Cemaziyelevvel 1448") == HijriDate(day: 7, month: 5, year: 1448))
        #expect(HijriDate(diyanet: "1 Şaban 1447")?.month == 8)
        #expect(HijriDate(diyanet: "1 SABAN 1447")?.month == 8)
        #expect(HijriDate(diyanet: "Unsinn") == nil)
    }

    @Test func hijriCorrectionMatchesDiyanet() throws {
        let ham =
            try JSONSerialization.jsonObject(
                with: Data(
                    contentsOf: try #require(
                        Bundle.module.url(forResource: "Veri/diyanet-hicri", withExtension: "json")))
            ) as! [String: Any]
        let hijri = ham["_hicri"] as! [String: [String: String]]
        var days: [DailyPrayerTimes] = []
        for (t, h) in hijri {
            let month = HijriDate.months.firstIndex(of: h["month"]!)! + 1
            days.append(
                DailyPrayerTimes(
                    day: Day(text: t)!, times: [:],
                    hijri: HijriDate(day: Int(h["day"]!)!, month: month, year: Int(h["year"]!)!),
                    source: .diyanet))
        }
        let table = PrayerTimeTable(location: .sample, fetchedAt: .now, days: days)
        let d = HijriDate.adjustment(table)
        let hits = table.days.filter { HijriDate.calculate($0.day, adjustment: d) == $0.hijri }.count
        #expect(hits >= table.days.count * 2 / 3, "\(hits) of \(table.days.count), correction \(d)")
        // Never more than one day off (month change: the 30th ↔ the 1st counts as one day).
        for g in table.days {
            let h = HijriDate.calculate(g.day, adjustment: d)
            let difference = abs(h.dayCount - g.hijri!.dayCount)
            #expect(difference <= 1 || (difference <= 2 && (h.day >= 29 || g.hijri!.day >= 29)), "\(g.day)")
        }
    }
}

@Suite struct SourceTests {
    let sample = Data(
        """
        {"kaynak":"diyanet","ilce":10001,"gunler":[
          {"tarih":"2026-10-24","imsak":"06:03","gunes":"07:45","ogle":"13:05","ikindi":"15:41","aksam":"18:15","yatsi":"19:44","hicri":"13 Cemaziyelevvel 1448"},
          {"tarih":"2026-10-25","imsak":"05:04","gunes":"06:46","ogle":"12:05","ikindi":"14:39","aksam":"17:13","yatsi":"18:42","hicri":"14 Cemaziyelevvel 1448"}]}
        """.utf8)

    @Test func serverResponseDSTChange() throws {
        let t = try ServerSource.parse(sample, location: .sample, fetchedAt: .now)
        #expect(t.source == .diyanet)
        #expect(t.days.count == 2)
        let f = ISO8601DateFormatter()
        // UTC+2 before the clock change, UTC+1 after.
        #expect(f.string(from: t.days[0][.imsak]) == "2026-10-24T04:03:00Z")
        #expect(f.string(from: t.days[1][.imsak]) == "2026-10-25T04:04:00Z")
        #expect(t.days[0].hijri?.day == 13)
    }

    @Test func invalidResponse() {
        #expect(throws: PrayerTimeError.invalidResponse) {
            try ServerSource.parse(Data("{}".utf8), location: .sample, fetchedAt: .now)
        }
    }

    struct Broken: PrayerTimeSource {
        func table(location: Location, start: Day, dayCount: Int) async throws -> PrayerTimeTable {
            throw PrayerTimeError.server(503)
        }
    }

    @Test func fallbackIsCalculated() async throws {
        let k = HybridSource(server: Broken())
        let t = try await k.table(
            location: .sample, start: Day(year: 2026, month: 10, day: 18), dayCount: 30)
        #expect(t.source == .calculated)
        #expect(t.days.count == 30)
        #expect(t.days.allSatisfy { $0.source == .calculated && $0.hijri != nil })
    }

    @Test func noServerWithoutDistrict() async throws {
        var k = Location.sample
        k.diyanetDistrict = nil
        await #expect(throws: PrayerTimeError.noDistrict) {
            try await ServerSource(address: URL(string: "http://127.0.0.1:9")!).table(
                location: k, start: Day(year: 2026, month: 1, day: 1), dayCount: 1)
        }
    }
}

@Suite struct StoreTests {
    final class Counter: PrayerTimeSource, @unchecked Sendable {
        var source: PrayerTimeSourceKind
        var calls = 0
        init(_ k: PrayerTimeSourceKind) { source = k }
        func table(location: Location, start: Day, dayCount: Int) async throws -> PrayerTimeTable {
            calls += 1
            let t = try await OnDeviceSource().table(location: location, start: start, dayCount: dayCount)
            return PrayerTimeTable(
                location: location, fetchedAt: .now,
                days: t.days.map {
                    DailyPrayerTimes(day: $0.day, times: $0.times, hijri: $0.hijri, source: source)
                })
        }
    }

    func folder() -> URL { FileManager.default.temporaryDirectory.appending(path: "vakit test \(UUID())") }

    @Test func stockLastsThirtyDays() async {
        let k = Counter(.diyanet)
        let d = PrayerTimesStore(folder: folder(), source: k)
        let now = Date(timeIntervalSince1970: 1_792_300_000)
        let t = await d.update(location: .sample, now: now)
        #expect(
            (t?.daysRemaining(today: Day(now, timeZoneIdentifier: Location.sample.timeZone)) ?? 0) >= 30)
        await d.update(location: .sample, now: now)
        #expect(k.calls == 1)
        // Eleven days later the stock is below the threshold → fetch more.
        await d.update(location: .sample, now: now + 11 * 86400)
        #expect(k.calls == 2)
    }

    @Test func locationChangeReloads() async {
        let k = Counter(.diyanet)
        let d = PrayerTimesStore(folder: folder(), source: k)
        await d.update(location: .sample)
        var actual = Location.sample
        actual.name = "Bamberg"
        actual.latitude = 49.89
        await d.update(location: actual)
        #expect(k.calls == 2)
    }

    @Test func calculatedDaysDoNotReplaceDiyanet() async {
        let k = Counter(.diyanet)
        let folderURL = folder()
        let now = Date(timeIntervalSince1970: 1_792_300_000)
        let d = PrayerTimesStore(folder: folderURL, source: k)
        await d.update(location: .sample, now: now)
        k.source = .calculated
        let t = await d.update(location: .sample, now: now + 12 * 86400)
        let today = Day(now + 12 * 86400, timeZoneIdentifier: Location.sample.timeZone)
        #expect(t?.day(today)?.source == .diyanet)
        #expect(t?.days.last?.source == .calculated)
        #expect((t?.daysRemaining(today: today) ?? 0) >= 30)
        // Even after a restart (new instance) the stock is on disk.
        let yeni = PrayerTimesStore(folder: folderURL, source: k)
        #expect(await yeni.stored()?.days.count == t?.days.count)
    }
}

@Suite struct DerivedTests {
    let table: PrayerTimeTable = {
        let days = (0..<3).map { i -> DailyPrayerTimes in
            let g = Day(year: 2026, month: 10, day: 16 + i)
            let v = PrayerTimeCalculator().day(g, location: .sample)
            return DailyPrayerTimes(
                day: g, times: v.times, hijri: HijriDate.calculate(g), source: .calculated)
        }
        return PrayerTimeTable(location: .sample, fetchedAt: .now, days: days)
    }()

    @Test func karahatWindow() throws {
        let g = table.days[1]
        let a = DayTimeline(today: g, tomorrow: table.days[2], karahatMinutes: 45)
        #expect(a.karahatWindows.count == 3)
        #expect(a.karahat(g[.sunrise] + 60)?.kind == .atSunrise)
        // Diyanet fatwa against the real sun position: Güneş + 7 Temkin + 45.
        #expect(a.karahat(g[.sunrise] + 51 * 60)?.kind == .atSunrise)
        #expect(a.karahat(g[.sunrise] + 53 * 60) == nil)
        #expect(a.karahat(g[.dhuhr] - 60)?.kind == .zawal)
        #expect(a.karahat(g[.maghrib] - 51 * 60)?.kind == .atSunset)
        #expect(a.karahat(g[.maghrib] - 53 * 60) == nil)
        #expect(a.ishraq == g[.sunrise] + 52 * 60)
        #expect(DayTimeline(today: g, tomorrow: nil, karahatMinutes: 0).karahatWindows.count == 2)
    }

    @Test func urgencyKarahatBeforeNextPrayer() throws {
        let g = table.days[1]
        let a = DayTimeline(today: g, tomorrow: table.days[2], karahatMinutes: 45)
        let status = { (time: Date) in try #require(PrayerTimeStatus(table: table, time: time)) }
        // In the middle of İkindi: the deadline is the start of the evening Karahat, not Akşam.
        let asr = g[.asr] + 10 * 60
        let r = Urgency.calculate(try status(asr), timeline: a, time: asr)
        #expect(r.level == .relaxed && r.lastDate == g[.maghrib] - 52 * 60 && r.karahat?.kind == .atSunset)
        // 20 minutes before this Karahat: tight.
        let tight = g[.maghrib] - 72 * 60
        #expect(Urgency.calculate(try status(tight), timeline: a, time: tight).level == .az)
        // In the Karahat.
        let ker = g[.maghrib] - 30 * 60
        #expect(Urgency.calculate(try status(ker), timeline: a, time: ker).level == .karahat)
        // Morning: the deadline is Güneş.
        let morning = g[.sunrise] - 20 * 60
        let s = Urgency.calculate(try status(morning), timeline: a, time: morning)
        #expect(s.level == .az && s.lastDate == g[.sunrise])
        // After the morning Karahat no prayer is running: calm, no deadline.
        let duha = g[.sunrise] + 90 * 60
        #expect(
            Urgency.calculate(try status(duha), timeline: a, time: duha)
                == Urgency(level: .relaxed, lastDate: nil, karahat: nil))
    }

    @Test func nightAndFriday() throws {
        let g = table.days[0]  // Friday, 16.10.2026
        let a = DayTimeline(today: g, tomorrow: table.days[1])
        #expect(a.isFriday)
        let midnightTime = try #require(a.midnight)
        let sonUc = try #require(a.lastThird)
        #expect(g[.maghrib] < midnightTime && midnightTime < sonUc && sonUc < table.days[1][.imsak])
        #expect(DayTimeline(today: g, tomorrow: nil).midnight == nil)
    }

    @Test func statusAndCountdown() throws {
        let g = table.days[1]
        let afterDhuhr = g[.dhuhr] + 60
        let d = try #require(PrayerTimeStatus(table: table, time: afterDhuhr))
        #expect(d.current == .dhuhr && d.next == .asr)
        #expect(d.progress(afterDhuhr) > 0 && d.progress(afterDhuhr) < 0.1)
        // After Yatsı it counts down to tomorrow's İmsak.
        let night = try #require(PrayerTimeStatus(table: table, time: g[.isha] + 60))
        #expect(night.next == .imsak && night.nextTime == table.days[2][.imsak])
        // Before İmsak, yesterday's Yatsı is still running.
        let morning = try #require(PrayerTimeStatus(table: table, time: g[.imsak] - 60))
        #expect(morning.current == .isha && morning.currentStart == table.days[0][.isha])
        // Outside the table there is no situation.
        #expect(PrayerTimeStatus(table: table, time: table.days[2][.isha] + 60) == nil)
    }

    @Test func religiousDays2027() {
        let l = ReligiousDay.calculate(year: 2027)
        for t in [
            ReligiousDay.Kind.ramadanStart, .eidAlFitr, .eidAlAdha, .laylatAlQadr, .raghaibKandil,
            .mirajKandil, .baratKandil, .mawlidKandil, .hijriNewYear, .ashura,
        ] {
            #expect(l.contains { $0.kind == t }, "\(t)")
        }
        // 2027 is in Diyanet's Hijri table (exact), 2030 is not (calculated).
        #expect(
            l.filter { $0.day < Day(year: 2027, month: 12, day: 31) }.allSatisfy { $0.source == .diyanet })
        #expect(ReligiousDay.calculate(year: 2030).allSatisfy { $0.source == .calculated })
        // Regaib is the night leading into a Friday (the evening of a Thursday).
        #expect(l.first { $0.kind == .raghaibKandil }?.day.weekday == 5)
        let ramadan = l.first { $0.kind == .ramadanStart }!.day
        let eid = l.first { $0.kind == .eidAlFitr }!.day
        #expect(eid > ramadan.added(27) && eid < ramadan.added(31))
    }
}

@Suite struct ReligiousDayListTests {
    @Test func diyanetNames() throws {
        let veri = Data(
            """
            [{"ad":"Regaip Kandili","tarih":"2027-01-07"},{"ad":"Ramazan Bayramı Arefe","tarih":"2027-03-09"},
             {"ad":"Ramazan Bayramı (1. Gün)","tarih":"2027-03-10"},{"ad":"Ramazan Bayramı (2. Gün)","tarih":"2027-03-11"},
             {"ad":"Bilinmeyen Gün","tarih":"2027-05-01"}]
            """.utf8)
        let l = try ServerSource.decodeReligiousDays(veri)
        #expect(l.map(\.kind) == [.raghaibKandil, .eidAlFitrEve, .eidAlFitr])
        #expect(l.allSatisfy { $0.source == .diyanet })
        #expect(l[0].isNight)
    }
}

@Suite struct HijriDiyanetTests {
    /// Spot checks from Diyanet's annual table (namazvakitleri.diyanet.gov.tr, retrieved 18.10.2026).
    @Test func diyanetTableExact() {
        #expect(
            HijriDate.calculate(Day(year: 2026, month: 10, day: 18))
                == HijriDate(day: 7, month: 5, year: 1448))
        #expect(
            HijriDate.calculate(Day(year: 2027, month: 12, day: 31))
                == HijriDate(day: 3, month: 8, year: 1449))
        #expect(
            HijriDate.calculate(Day(year: 2027, month: 2, day: 8)) == HijriDate(day: 1, month: 9, year: 1448))
        #expect(HijriDate.exact(Day(year: 2027, month: 6, day: 1)))
        #expect(!HijriDate.exact(Day(year: 2030, month: 1, day: 1)))
    }

    @Test func ramadan1448ReligiousDay() {
        let l = ReligiousDay.calculate(year: 2027)
        let r = l.first { $0.kind == .ramadanStart }
        #expect(r?.day == Day(year: 2027, month: 2, day: 8))
        #expect(r?.source == .diyanet)
    }

    /// Recep 1448 begins in December 2026; 2027 must not get a second Regaip.
    @Test func raghaibOnlyOnceAcrossNewYear() {
        let r26 = ReligiousDay.calculate(year: 2026).filter { $0.kind == .raghaibKandil }
        let r27 = ReligiousDay.calculate(year: 2027).filter { $0.kind == .raghaibKandil }
        #expect(r26.count == 1)
        #expect(r27.allSatisfy { $0.day.month >= 11 })
    }
}
