import Foundation
import Testing

@testable import Core

/// Golden test for stored names. When translating, only adapt
/// type and field names, never the strings: they appear like this in UserDefaults and JSON.
@Suite struct PersistedFormatTests {
    @Test func appGroupAndInfoKeys() {
        #expect(AppLanguage.appGroup == "group.dev.ms-solutions.kiblegah")
        #expect(AppLanguage.key == "ayar.dil")
        #expect(FeatureFlags.infoKey == "KiblegahOzellikler")
        #expect(Set(FeatureFlags.names.keys) == ["diyanet", "ekKariler"])
        #expect(Relay.infoKey == "VermittlerAdresi")
    }

    @Test func migratedGroupKeys() {
        #expect(
            GroupDefaults.migratedKeys == [
                "tefsir.kaynak", "kuranNuzulSirasi", "kuranKayitTarihe", "ezberDuzeni", "mushafOlcek",
                "mushafZoomIpucu", "okuma.baslangic", "okuma.bitis", "okuma.tekrar", "quizKontrolcu",
                "sohbetTanitimGoruldu",
            ])
    }

    /// Raw values live in `ayar.*` (Ayarlar); a renamed case needs `= "old"`.
    @Test func optionRawValues() {
        #expect(Set(Appearance.allCases.map(\.rawValue)) == ["sistem", "acik", "koyu", "vakteGore"])
        #expect(Set(PrayerTimeMethod.allCases.map(\.rawValue)) == ["konum", "diyanet"])
        #expect(
            Set(AppTab.allCases.map(\.rawValue)) == [
                "vakit", "kible", "kuran", "dualar", "zikir", "esma", "hadis", "sohbet", "quiz", "kesfet",
            ])
        #expect(
            Set(Palette.allCases.map(\.rawValue)) == ["seher", "gokyuzu", "nakis", "zumrut", "gece", "gul"])
        #expect(Set(CompassStyle.allCases.map(\.rawValue)) == ["gradHalkasi", "buyukIgne"])
        #expect(Set(QiblaStart.allCases.map(\.rawValue)) == ["pusula", "harita", "sonSecim"])
    }

    @Test func locationJSON() throws {
        try goldenRoundTrip(
            Location.self,
            #"{"ad":"Hamburg","enlem":53.55,"boylam":9.99,"saatDilimi":"Europe/Berlin","diyanetIlce":10002}"#
        )
    }

    /// Key texts (SwiftData, links, notes) as JSON strings.
    @Test func contentKeyJSON() throws {
        try goldenRoundTrip(
            [ContentKey].self,
            #"["s:2","a:2:255","a:2:255-257","w:1:5:2","p:604","j:30","d:sabah","e:99","h:buhari:1","k:sabir"]"#
        )
    }
}
