import Foundation
import Testing

@testable import ContentPacks

@Suite struct WireFormatTests {
    @Test func manifestJSON() throws {
        try goldenRoundTrip(
            PackManifest.self,
            #"""
            {"id":"meal-xx-example","art":"meal","sprache":"tr","titel":"Example","yazar":"Example",
             "quelle":"Example","quelle_url":"https://example.org","lizenz":"CC0","store_tauglich":false,
             "version":"1","textstand":"2026-10-01","inceleme":"2026-10-02"}
            """#)
    }

    @Test func questionBankJSON() throws {
        try goldenRoundTrip(
            QuizBank.self,
            #"{"banka":"ilmihal","ad":{"tr":"İlmihal","de":"Ilmihal","en":"Ilmihal"},"sayi":120,"onayli":80}"#
        )
        try goldenRoundTrip(
            BankQuestion.Citation.self,
            #"{"eser":"ilmihal","cilt":1,"sayfa":12,"pdf_sayfa":14,"ayet":"a:2:255","alinti":"…"}"#)
        try goldenRoundTrip(
            BankQuestion.Review.self, #"{"kim":"Reviewer","tarih":"2026-10-30","onay":true,"not":"ok"}"#)
    }

    @Test func rawValues() {
        for r in ["dortSecenek", "dogruYanlis", "kelimeKacheln"] {
            #expect(QuizFormat(rawValue: r) != nil, "\(r)")
        }
        #expect(
            Set(QuizQuestionKind.allCases.map(\.rawValue)) == [
                "gununSorusu", "mealSure", "ayetSayisi", "sureCuzu", "medeniSure", "mekkiSure", "ilkNazil",
                "kelimeBosluk", "esmaAnlami", "anlamEsma", "hadisKoleksiyon", "hadisKategori", "duaKategori",
                "duaSure", "banka",
            ])
        #expect(
            Set(HadithCollection.allCases.map(\.rawValue)) == [
                "muttefekunAleyh", "buhari", "muslim", "ebuDavud", "tirmizi", "nesai", "ibnMace", "ahmed",
            ])
    }

    @Test func packFilesIdsAndTables() {
        let text = goldenSourceText()
        expectLiterals(["manifest.json", "veri.sqlite", "ilce", "kuran-text", "medine-604"], in: text)
        let tables = [
            "ayet", "sure", "meal", "tefsir", "okunus", "kelime", "kelime_okunus", "tecvid", "sayfa", "cuz",
            "bag",
            "benzer", "dua", "esma", "hadis", "kategori", "bilgi", "belge", "parca", "ilce",
            "ulke", "eyalet", "merkez",
        ]
        for t in tables {
            let found = ["FROM ", "JOIN ", "INTO "].contains { text.contains($0 + t) }
            #expect(found, "SQL table \(t) no longer in the source")
        }
    }
}
