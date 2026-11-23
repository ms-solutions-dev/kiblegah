import Foundation
import Testing

@testable import WidgetBridge

/// Golden test for the snapshots in the App Group and in the watch context.
/// App, widget and watch of an older build read the same files. Only adjust type/field names.
@Suite struct WireFormatTests {
    @Test func prayerSnapshotJSON() throws {
        try goldenRoundTrip(
            PrayerTimesSnapshot.self,
            #"""
            {"konum":"Hamburg","saatDilimi":"Europe/Berlin","hesaplanan":false,
             "vakitler":[{"kimlik":"imsak","ad":"İmsak","an":800000000,"namaz":true}],
             "kerahatler":[{"bas":800000100,"son":800000200}],
             "kibleAcisi":135.5,"olusturma":800000300,"enlem":53.55,"boylam":9.99}
            """#)
    }

    @Test func listenReadingVerseSnapshotJSON() throws {
        try goldenRoundTrip(
            ListenSnapshot.self,
            #"{"sure":94,"ayet":5,"sureAdi":"İnşirah","ayetSayisi":8,"kari":"alafasy","caliyor":true,"tarih":800000000}"#
        )
        try goldenRoundTrip(
            ReadingSnapshot.self,
            #"""
            {"gun":800000000,"bugunAyet":12,"bugunDakika":9,"haftaBasi":799900000,"haftaDakika":[1,2,3,4,5,6,7],
             "haftaAyet":80,"seri":4,"hatimAyet":1200,"kaldiginYer":"a:2:255","link":"kiblegah://kuran/2:255",
             "hedef":{"tur":"ayet","ist":12,"ziel":20}}
            """#)
        try goldenRoundTrip(
            VerseSnapshot.self,
            #"""
            {"gunler":[{"gun":800000000,"baslik":"Bakara 255","arapca":"ٱللَّهُ","meal":"Allah","kaynak":"Diyanet",
              "link":"kiblegah://kuran/2:255"}]}
            """#)
    }

    @Test func fileNamesKindsAndGroup() {
        #expect(PrayerTimesSnapshot.appGroup == "group.dev.ms-solutions.kiblegah")
        #expect(PrayerTimesSnapshot.fileName == "anlik.json")
        #expect(ReadingSnapshot.fileName == "okuma.json" && ReadingSnapshot.kind == "kuran-okuma")
        #expect(VerseSnapshot.fileName == "ayet.json" && VerseSnapshot.kind == "gunun-ayeti")
        #expect(ListenSnapshot.fileName == "dinle.json" && ListenSnapshot.kind == "kuran-dinle")
        for r in ["gunes", "zeval", "aksam", "diger"] {
            #expect(PrayerStatus.KarahatKind(rawValue: r) != nil, "\(r)")
        }
    }

    /// Live Activity and App Intents exist only on iOS; hence checked here via the source text.
    @Test func iOSOnlyLiterals() {
        let text = goldenSourceText()
        expectLiterals(["acilisHedefi"], in: text)
        for name in ["siradakiAd", "siradakiAn", "kerahatSonu", "KibleAcNiyeti", "KuranDinleNiyeti"] {
            #expect(text.contains(name), "\(name) fehlt (ContentState-Feld bzw. App-Intent-Identität)")
        }
    }
}
