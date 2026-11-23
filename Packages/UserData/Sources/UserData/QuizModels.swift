import Foundation
import SwiftData

// Quiz V1 (concept „Kıblegâh Quiz“, data model sketch). Like all models CloudKit-compatible: every
// field has a default or is optional, no uniqueness rules, no relationships – references go
// through identifiers (`kind`, `question`) so that two devices do not overwrite each other.

/// A quiz round: daily round, practice, repetition or duel.
@Model public final class QuizTuru {
    public var kimlik: String = UUID().uuidString
    /// `yyyy-MM-dd` of the day the round began (daily round: its day).
    public var gun: String = ""
    /// Seed of the round (daily round: day number, duel: from the code).
    public var tohum: Int = 0
    /// `daily`, `practice`, `repetition`, `duello`.
    public var cesit: String = ""
    /// Area, or empty for „Karışık“.
    public var alan: String = ""
    public var uzunluk: Int = 10
    /// The identifiers of the questions, one per line – so the round stays the same even if the level changes.
    public var sorular: String = ""
    public var baslangic: Date = Date.now
    public var bitis: Date?
    /// Points only in the daily round (10 per hit); otherwise `nil`.
    public var puan: Int?
    public var dogruSayisi: Int = 0
    public var cevapSayisi: Int = 0
    /// Duel code, if the round is a duel.
    public var kod: String = ""

    public init(
        kimlik: String = UUID().uuidString, gun: String, cesit: String, tohum: Int, alan: String, uzunluk: Int
    ) {
        self.kimlik = kimlik
        self.gun = gun
        self.cesit = cesit
        self.tohum = tohum
        self.alan = alan
        self.uzunluk = uzunluk
    }

    public var questionList: [String] {
        get { sorular.split(separator: "\n").map(String.init) }
        set { sorular = newValue.joined(separator: "\n") }
    }

    public var isFinished: Bool { bitis != nil }
}

/// A question in the repetition (Leitner with the EzberHesabi formula).
@Model public final class TekrarKarti {
    /// Identifier of the question (`gen:…`, `kur:…`).
    public var soru: String = ""
    public var eklenme: Date = Date.now
    public var sonraki: Date = Date.now
    public var aralik: Double = 1
    public var kolaylik: Double = 2.5
    public var tekrar: Int = 0

    public init(soru: String) { self.soru = soru }
}

/// Level per area (1.0…5.0, start 2.0), private.
@Model public final class AlanSeviyesi {
    public var alan: String = ""
    public var seviye: Double = 2
    public var guncelleme: Date = Date.now

    public init(alan: String, seviye: Double = 2) {
        self.alan = alan
        self.seviye = seviye
    }
}

/// A duel from „Düellolarım“: own score and – entered by hand – the opponent's.
@Model public final class Duello {
    public var kod: String = ""
    public var alan: String = ""
    public var uzunluk: Int = 10
    public var tarih: Date = Date.now
    /// The own round (``QuizTuru/identifier``).
    public var tur: String = ""
    public var benimDogru: Int?
    public var karsiAd: String = ""
    public var karsiDogru: Int?

    public init(kod: String, alan: String, uzunluk: Int) {
        self.kod = kod
        self.alan = alan
        self.uzunluk = uzunluk
    }
}
