import Foundation
import Testing

@testable import PrayerTimes

/// Golden test for stored and transmitted names: `vakit.json` in the
/// App Group, notification identifiers, prayer time service. Only adjust type/field names, never the strings.
/// Does not test any calculation (that stays untouched).
@Suite struct WireFormatTests {
    @Test func prayerTimeTableJSON() throws {
        try goldenRoundTrip(
            PrayerTimeTable.self,
            #"""
            {"konum":{"ad":"Hamburg","enlem":53.55,"boylam":9.99,"saatDilimi":"Europe/Berlin","diyanetIlce":10002},
             "alinma":800000000,
             "gunler":[{"gun":"2026-10-31",
               "saatler":{"imsak":800000001,"gunes":800000002,"ogle":800000003,"ikindi":800000004,"aksam":800000005,"yatsi":800000006},
               "hicri":{"gun":19,"ay":5,"yil":1448},"kaynak":"diyanet"}]}
            """#)
    }

    @Test func notificationSettingAndReligiousDayJSON() throws {
        try goldenRoundTrip(NotificationSetting.self, #"{"vaktinde":true,"onceden":15,"tamEzan":false}"#)
        try goldenRoundTrip(
            ReligiousDay.self, #"{"tur":"kadirGecesi","gun":"2027-03-04","kaynak":"hesaplanan"}"#)
    }

    @Test func rawValues() {
        #expect(
            Set(Prayer.allCases.map(\.rawValue)) == ["imsak", "gunes", "ogle", "ikindi", "aksam", "yatsi"])
        #expect(
            PrayerTimeSourceKind(rawValue: "diyanet") != nil
                && PrayerTimeSourceKind(rawValue: "hesaplanan") != nil)
        #expect(
            Set(ReligiousDay.Kind.allCases.map(\.rawValue)) == [
                "hicriYilbasi", "asure", "mevlidKandili", "uclerAylarBaslangici", "regaibKandili",
                "miracKandili",
                "beratKandili", "ramazanBaslangici", "kadirGecesi", "ramazanArefesi", "ramazanBayrami",
                "kurbanArefesi", "kurbanBayrami",
            ])
        #expect(NotificationPlan.prefix == "vakit.")
    }

    /// File names, resources and paths of the prayer time service.
    @Test func literals() {
        expectLiterals(
            ["vakit.json", "hicri-diyanet", "v1/vakit", "v1/bul", "v1/dini-gunler"], in: goldenSourceText())
    }
}
