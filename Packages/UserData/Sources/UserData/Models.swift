import Foundation
import SwiftData

// All user data hangs only on keys. Fields have defaults and
// no uniqueness rules, because the CloudKit mirroring of SwiftData requires both.

/// Note on an ayet or range (V1: „Notum“ in the verse sheet).
@Model public final class Notum {
    public var anahtar: String = ""
    public var metin: String = ""
    public var arsiv: Bool = false
    public var olusturma: Date = Date.now
    public var degisiklik: Date = Date.now

    public init(anahtar: String, metin: String) {
        self.anahtar = anahtar
        self.metin = metin
    }
}

/// „Kaydedilen“: a remembered verse (later also dua, hadith …).
@Model public final class Kayit {
    public var anahtar: String = ""
    public var tarih: Date = Date.now

    public init(anahtar: String) {
        self.anahtar = anahtar
    }
}

/// A reading event instead of a counter: khatm, week bar and streak
/// are derived from it. The Siras are the consecutive verse numbers 1…6236.
@Model public final class OkumaOturumu {
    public var ilkSira: Int = 0
    public var sonSira: Int = 0
    public var saniye: Double = 0
    public var tarih: Date = Date.now
    /// Multiple reading positions: empty = the default khatm.
    public var hatim: String = ""

    public init(ilkSira: Int, sonSira: Int, saniye: Double, tarih: Date = .now, hatim: String = "") {
        self.ilkSira = ilkSira
        self.sonSira = sonSira
        self.saniye = saniye
        self.tarih = tarih
        self.hatim = hatim
    }
}

/// Kaldığın yer: the most recently read verse per reading position.
@Model public final class KaldiginYer {
    public var anahtar: String = ""
    public var tarih: Date = Date.now
    public var hatim: String = ""

    public init(anahtar: String, hatim: String = "") {
        self.anahtar = anahtar
        self.hatim = hatim
    }
}

/// A reading position with a goal. `kimlik == ""` is the default khatm, which exists without an
/// entry; an entry with an empty kimlik only carries its goal.
@Model public final class Hatim {
    public var kimlik: String = UUID().uuidString
    public var ad: String = ""
    /// `GoalKind.rawValue`; empty = no goal.
    public var hedefTuru: String = ""
    public var hedefDeger: Int = 0
    public var bitis: Date?
    public var baslangic: Date = Date.now

    public init(kimlik: String = UUID().uuidString, ad: String) {
        self.kimlik = kimlik
        self.ad = ad
    }

    public var goal: ReadingGoal? {
        GoalKind(rawValue: hedefTuru).map { ReadingGoal(kind: $0, value: hedefDeger, end: bitis) }
    }
}

public enum GoalKind: String, Sendable, CaseIterable {
    /// Daily `value` verses / pages / minutes.
    case verses = "ayet", pages = "sayfa", minutes = "dakika"
    /// Khatm by `end`: the daily goal is derived from the remainder.
    case finishDate = "bitis"
}

public struct ReadingGoal: Sendable, Equatable {
    public var kind: GoalKind
    public var value: Int
    public var end: Date?

    public init(kind: GoalKind, value: Int, end: Date? = nil) {
        self.kind = kind
        self.value = value
        self.end = end
    }
}

/// A memorization card: a verse or verse range with a repetition schedule.
@Model public final class EzberKarti {
    /// `a:67:1-5` or `a:112:1`
    public var anahtar: String = ""
    public var eklenme: Date = Date.now
    /// Next due repetition.
    public var sonraki: Date = Date.now
    /// Current interval in days.
    public var aralik: Double = 0
    /// Ease factor (SM-2), 1.3 … 3.0.
    public var kolaylik: Double = 2.5
    public var tekrar: Int = 0

    public init(anahtar: String) { self.anahtar = anahtar }
}

/// A collection. Entries are attached only by key; a verse can be in several collections.
@Model public final class Koleksiyon {
    public var kimlik: String = UUID().uuidString
    public var ad: String = ""
    public var olusturma: Date = Date.now
    public var sira: Int = 0

    public init(ad: String, sira: Int) {
        self.ad = ad
        self.sira = sira
    }
}

@Model public final class KoleksiyonOgesi {
    public var koleksiyon: String = ""
    public var anahtar: String = ""
    public var tarih: Date = Date.now

    public init(koleksiyon: String, anahtar: String) {
        self.koleksiyon = koleksiyon
        self.anahtar = anahtar
    }
}

/// Dhikr count per day and dhikr (for „Bugün 147 · Hafta 912“).
@Model public final class ZikirGunu {
    public var gun: String = ""
    public var zikir: String = ""
    public var adet: Int = 0

    public init(gun: String, zikir: String, adet: Int) {
        self.gun = gun
        self.zikir = zikir
        self.adet = adet
    }
}

/// An AI conversation for the history under Ayarlar → Sorular.
/// The messages are stored as JSON in the record so that a conversation stays one CloudKit record.
@Model public final class KiSohbeti {
    public var kimlik: String = UUID().uuidString
    /// The first question, shortened.
    public var baslik: String = ""
    /// Verse key if the question was asked from the reader (`a:2:255`), otherwise empty.
    public var ayet: String = ""
    public var oturum: String = ""
    public var olusturma: Date = Date.now
    public var guncelleme: Date = Date.now
    public var mesajlar: Data = Data()

    public init(kimlik: String) { self.kimlik = kimlik }
}

/// The answer to the question of the day (daily item „Soru“). One entry per day; duplicate
/// entries from two devices are harmless, only whether the day has one is counted.
@Model public final class SoruCevabi {
    /// `yyyy-MM-dd` of the day the question applied to.
    public var gun: String = ""
    /// Index of the chosen answer.
    public var secim: Int = -1
    public var dogru: Bool = false
    public var tarih: Date = Date.now
    /// Quiz (V1): identifier of the question (`gen:…`, `kur:…`, `day:<n>`); empty for old entries that
    /// only knew the daily question. New fields have defaults so that migration stays easy.
    public var soru: String = ""
    /// Identifier of the round (``QuizTuru/identifier``); empty for the daily question from the home screen.
    public var tur: String = ""
    /// Position in the round (1…15), 0 without a round.
    public var sira: Int = 0
    /// Thinking time in seconds – shown, but does not count (no time bonus).
    public var sure: Double = 0
    /// Area of the question (`quran`, `divineName` …) for the level per area.
    public var alan: String = ""

    public init(
        gun: String, secim: Int, dogru: Bool, soru: String = "", tur: String = "", sira: Int = 0,
        sure: Double = 0,
        alan: String = ""
    ) {
        self.gun = gun
        self.secim = secim
        self.dogru = dogru
        self.soru = soru
        self.tur = tur
        self.sira = sira
        self.sure = sure
        self.alan = alan
    }

    /// Whether this entry answers the daily question (old entry or question 1 of the daily round).
    public var isQuestionOfTheDay: Bool { soru.isEmpty || soru.hasPrefix("gun:") }
}

@Model public final class KitapIsareti {
    public var kimlik: String = ""
    /// Book identifier: file name of the EPUB without extension.
    public var kitap: String = ""
    /// `yerimi`, `yellow`, `green`, `pink`
    public var tur: String = ""
    public var konum: String = ""
    public var metin: String = ""
    public var not: String = ""
    public var anteil: Double = 0
    public var bolum: String = ""
    public var ayetSure: Int = 0
    public var ayetIlk: Int = 0
    public var ayetSon: Int = 0
    public var tarih: Date = Date.now

    public init(kimlik: String, kitap: String, tur: String, konum: String, metin: String, anteil: Double) {
        self.kimlik = kimlik
        self.kitap = kitap
        self.tur = tur
        self.konum = konum
        self.metin = metin
        self.anteil = anteil
    }
}

/// The reading position per book – mirrored like the Kaldığın yer in the Quran.
@Model public final class KitapKonumu {
    public var kitap: String = ""
    public var konum: String = ""
    public var anteil: Double = 0
    public var tarih: Date = Date.now

    public init(kitap: String, konum: String, anteil: Double) {
        self.kitap = kitap
        self.konum = konum
        self.anteil = anteil
    }
}

public enum UserDataSchema {
    public static let models: [any PersistentModel.Type] = [
        Notum.self, Kayit.self, OkumaOturumu.self, KaldiginYer.self, ZikirGunu.self, Koleksiyon.self,
        KoleksiyonOgesi.self, Hatim.self, EzberKarti.self, KiSohbeti.self, SoruCevabi.self,
        QuizTuru.self, TekrarKarti.self, AlanSeviyesi.self, Duello.self, KitapIsareti.self, KitapKonumu.self,
    ]

    /// The container: local, or with iCloud mirroring if the user chose it
    ///. `inMemory` for tests and previews.
    public static func container(iCloud: Bool, inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(models)
        let setting = ModelConfiguration(
            "Kiblegah", schema: schema, isStoredInMemoryOnly: inMemory,
            groupContainer: inMemory ? .none : .identifier(AppSettings.appGroup),
            cloudKitDatabase: iCloud && !inMemory ? .private("iCloud.dev.ms-solutions.kiblegah") : .none)
        return try ModelContainer(for: schema, configurations: setting)
    }
}
