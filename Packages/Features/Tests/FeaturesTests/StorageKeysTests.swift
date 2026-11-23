import Foundation
import Testing

@testable import Features

/// Golden test for keys, raw values, asset packs, caches and service paths of the screens
///. The URL scheme is checked by `RouterTests`.
/// Only adjust type/field names, never the strings.
@Suite struct StorageKeysTests {
    @Test func userDefaultsKeys() {
        expectLiterals(
            [
                "tefsir.kaynak", "kuranNuzulSirasi", "kuranKayitTarihe", "ezberDuzeni", "mushafOlcek",
                "mushafZoomIpucu", "okuma.baslangic", "okuma.bitis", "okuma.tekrar",
                "paylasStili", "paylasRengi", "paylasAnlam", "paylasYer", "kaydedilen",
            ], in: goldenSourceText())
    }

    /// Launch arguments from scripts and screenshot recipes (stay in phase B).
    @Test func launchArguments() {
        expectLiterals(
            [
                "quizOtoCevap", "quizOtoSec", "quizAsagi", "kuranListe",
                "ayetReiter", "testCal", "testTakipKapali", "mushafRuckfall", "pusulaSahte",
                "kibleKadraj", "kibleGorunum", "hadisAra", "saatKaydir",
            ], in: goldenSourceText())
    }

    @Test func rawValuesAndAssetPacks() {
        #expect(Set(ReadingOptions.Start.allCases.map(\.rawValue)) == ["ayet", "sayfa", "sure", "cuz"])
        #expect(Set(ReadingOptions.End.allCases.map(\.rawValue)) == ["ayet", "sayfa", "sure", "cuz"])
        #expect(Set(MushafEdition.allCases.map(\.packID)) == ["mushaf-v1", "mushaf-v2", "mushaf-v4"])
        #expect(Set(MemorizationLayout.allCases.map(\.rawValue)) == ["alt", "deste"])
        #expect(Set(ShareStyle.allCases.map(\.rawValue)) == ["renk", "gok"])
        #expect(
            Set(AppIcon.allCases.map(\.rawValue)) == [
                "kalpPusula", "kaf", "kabe", "mihrap", "yildiz", "ufuk", "kef", "ummet",
            ])
        for r in ["pusula", "kamera", "harita"] { #expect(QiblaScreen.QiblaMode(rawValue: r) != nil, "\(r)") }
        expectLiterals(["duzen.json"], prefixes: ["AppIcon", "Ikon"], in: goldenSourceText())
    }

    @Test func mushafLayoutJSON() throws {
        try goldenRoundTrip(
            MushafPageLayout.self,
            #"""
            {"sayfa":1,"yazi":"v1","satirlar":[{"no":1,"ilk":"1:1:1","son":"1:1:4",
              "kelimeler":[{"k":"1:1:1","c":"ﭑ","son":false}]}]}
            """#)
    }

    /// Caches, Watch context, catalog prefixes from raw values and service paths.
    @Test func cachesContextCatalogPaths() {
        expectLiterals(
            [
                "MushafDuzeni", "MushafYazi", "anlik", "okuma",
                "url",
            ],
            prefixes: [
                "esma-ayetler-", "v1/mushaf/", "dini.", "dua.kategori.", "tecvid.",
                "arama.tur.",
            ],
            in: goldenSourceText())
    }
}
