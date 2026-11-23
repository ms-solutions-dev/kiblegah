import Foundation
import Testing

@testable import Quran

/// Golden test for reciter identifiers (= folder under `Sesler/` and value of `ayar.reciter`), caches and
/// service paths. Only adjust type/field names, never the strings.
@Suite struct WireFormatTests {
    @Test func reciterJSONAndIds() throws {
        try goldenRoundTrip(
            Reciter.self,
            #"""
            {"id":"alafasy","ad":"Mishary Alafasy","stil":"Murattal","klasor":"Alafasy/mp3","storeTauglich":true,
             "qcId":7,"tamSure":"https://example.org/{s}.mp3","kiraat":"Hafs"}
            """#)
        let ids = Set(Reciter.catalog.map(\.id))
        for id in [
            "alafasy", "abdulbasit", "abdulbasit-mucevved", "minshawi", "minshawi-mucevved", "sudais",
            "shatri",
            "rifai", "shuraym", "husary", "husary-muallim", "tablawi",
        ] {
            #expect(ids.contains(id), "Kâri-Kennung \(id)")
        }
        #expect(Reciter.standard.id == "alafasy")
    }

    @Test func cacheJSON() throws {
        try goldenRoundTrip([WordTimings.Word].self, #"[{"sira":1,"bas":0,"son":420}]"#)
        try goldenRoundTrip(WordMeaning.self, #"{"metin":"Rahman","yedek":false}"#)
    }

    @Test func foldersAndPaths() {
        expectLiterals(
            [
                "Sesler", "Library/Application Support/Sesler", "SesOnbellek", "KelimeZamanlari",
                "KelimeMeali",
            ], in: goldenSourceText())
    }
}
