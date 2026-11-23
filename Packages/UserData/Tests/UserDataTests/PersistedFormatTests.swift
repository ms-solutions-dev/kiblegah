import Foundation
import SwiftData
import Testing

@testable import UserData

/// Golden test for the SwiftData schema (= CloudKit record types `CD_<class>` and fields `CD_<field>`),
/// the public duel database and the settings keys.
/// Model classes and stored fields are never renamed – not even during translation.
@Suite struct PersistedFormatTests {
    static let entities: [String: Set<String>] = [
        "Notum": ["anahtar", "metin", "arsiv", "olusturma", "degisiklik"],
        "Kayit": ["anahtar", "tarih"],
        "OkumaOturumu": ["ilkSira", "sonSira", "saniye", "tarih", "hatim"],
        "KaldiginYer": ["anahtar", "tarih", "hatim"],
        "Hatim": ["kimlik", "ad", "hedefTuru", "hedefDeger", "bitis", "baslangic"],
        "EzberKarti": ["anahtar", "eklenme", "sonraki", "aralik", "kolaylik", "tekrar"],
        "Koleksiyon": ["kimlik", "ad", "olusturma", "sira"],
        "KoleksiyonOgesi": ["koleksiyon", "anahtar", "tarih"],
        "ZikirGunu": ["gun", "zikir", "adet"],
        "KiSohbeti": ["kimlik", "baslik", "ayet", "oturum", "olusturma", "guncelleme", "mesajlar"],
        "SoruCevabi": ["gun", "secim", "dogru", "tarih", "soru", "tur", "sira", "sure", "alan"],
        "QuizTuru": [
            "kimlik", "gun", "tohum", "cesit", "alan", "uzunluk", "sorular", "baslangic", "bitis", "puan",
            "dogruSayisi", "cevapSayisi", "kod",
        ],
        "TekrarKarti": ["soru", "eklenme", "sonraki", "aralik", "kolaylik", "tekrar"],
        "AlanSeviyesi": ["alan", "seviye", "guncelleme"],
        "Duello": ["kod", "alan", "uzunluk", "tarih", "tur", "benimDogru", "karsiAd", "karsiDogru"],
        "KitapIsareti": [
            "kimlik", "kitap", "tur", "konum", "metin", "not", "anteil", "bolum", "ayetSure", "ayetIlk",
            "ayetSon",
            "tarih",
        ],
        "KitapKonumu": ["kitap", "konum", "anteil", "tarih"],
    ]

    @Test func swiftDataEntitiesAndAttributes() {
        let schema = Schema(UserDataSchema.models)
        let actual = Dictionary(
            uniqueKeysWithValues: schema.entities.map { e in
                (e.name, Set(e.attributes.map(\.name)).union(e.relationships.map(\.name)))
            })
        #expect(Set(actual.keys) == Set(Self.entities.keys))
        for (name, fields) in Self.entities {
            #expect(actual[name] == fields, "Entität \(name): \(actual[name].map { $0.sorted() } ?? [])")
        }
    }

    @Test func containerAndGroup() {
        #expect(AppSettings.appGroup == "group.dev.ms-solutions.kiblegah")
        expectLiterals(["Kiblegah", "iCloud.dev.ms-solutions.kiblegah"], in: goldenSourceText())
    }

    /// Public CloudKit database (duel zone).
    @Test func duelRecord() {
        #expect(DuelRoom.kind == "Duello")
        expectLiterals(["kod", "ad", "cevaplar", "bitti"], in: goldenSourceText())
        #expect(Set(DuelRoom.Side.allCases.map(\.rawValue)) == ["A", "B"])
    }

    @Test func rawValuesInStoredStrings() {
        #expect(Set(GoalKind.allCases.map(\.rawValue)) == ["ayet", "sayfa", "dakika", "bitis"])
        #expect(
            Set(QuizScoring.Tier.allCases.map(\.rawValue)) == [
                "baslangic", "temel", "orta", "ileri", "derin",
            ])
    }
}

/// UserDefaults keys of the settings (App Group).
@Suite struct StorageKeysTests {
    @Test func settingsKeys() {
        let keys = [
            "gorunum", "buyukVeSade", "sekmeler", "kerahatDakika", "palet", "icloud", "ilkAcilis", "konum",
            "otomatikKonum", "vakitSunucusu", "bildirimler", "vakitHesabi", "bildirimSesi",
            "arapcaBoyut", "okunusBoyut", "mealBoyut", "okunusGoster", "mealler", "tecvid", "mushafTecvid",
            "mushafFassung", "mushaftaAc", "okunusDili", "tefsirDili", "kari", "aktifHatim", "canliEtkinlik",
            "kelimeMeali", "pusulaStili", "kibleBaslangici", "kibleSonGorunum", "quizHedef", "quizNiyet",
            "sohbetDublaj", "duelloAdi", "kerahatHatirlat",
        ].map { "ayar." + $0 }
        expectLiterals(keys + ["varsayilan", "alafasy"], in: goldenSourceText())
    }

    /// A freshly written state ends up under exactly these keys.
    @MainActor @Test func writtenKeys() {
        let name = "kiblegah.test.storagekeys"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        let a = AppSettings(defaults: d)
        a.palette = .night
        a.reciter = "husary"
        #expect(d.string(forKey: "ayar.palet") == "gece")
        #expect(d.string(forKey: "ayar.kari") == "husary")
        d.removePersistentDomain(forName: name)
    }
}
