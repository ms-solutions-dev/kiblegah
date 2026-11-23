import Foundation

/// A text in the three app languages.
public struct Multilingual: Sendable, Hashable {
    public let tr: String
    public let de: String
    public let en: String

    public init(tr: String, de: String, en: String) {
        self.tr = tr
        self.de = de
        self.en = en
    }

    public func text(_ language: String) -> String {
        switch language {
        case "tr": tr
        case "de": de
        default: en
        }
    }
}

/// A short dhikr formula. The formulas are commonly transmitted and short; Arabic,
/// Okunuş and meaning are set by hand here and carried as „ungeprüft“.
public struct Dhikr: Sendable, Hashable, Identifiable {
    public let id: String
    public let arabic: String
    public let transliteration: Multilingual
    public let meaning: Multilingual
    public let goal: Int

    public init(id: String, arabic: String, transliteration: Multilingual, meaning: Multilingual, goal: Int) {
        self.id = id
        self.arabic = arabic
        self.transliteration = transliteration
        self.meaning = meaning
        self.goal = goal
    }

    public static let subhanallah = Dhikr(
        id: "subhanallah", arabic: "سُبْحَانَ اللّٰهِ",
        transliteration: Multilingual(tr: "Sübhânallâh", de: "Subhanallah", en: "Subhanallah"),
        meaning: Multilingual(
            tr: "Allah'ı her türlü eksiklikten tenzih ederim.", de: "Gepriesen und erhaben ist Allah.",
            en: "Glory be to Allah."), goal: 33)
    public static let alhamdulillah = Dhikr(
        id: "elhamdulillah", arabic: "اَلْحَمْدُ لِلّٰهِ",
        transliteration: Multilingual(tr: "Elhamdülillâh", de: "Alhamdulillah", en: "Alhamdulillah"),
        meaning: Multilingual(
            tr: "Hamd Allah'a mahsustur.", de: "Alles Lob gebührt Allah.", en: "All praise is due to Allah."),
        goal: 33)
    public static let allahuAkbar = Dhikr(
        id: "allahuekber", arabic: "اَللّٰهُ اَكْبَرُ",
        transliteration: Multilingual(tr: "Allâhü ekber", de: "Allahu akbar", en: "Allahu akbar"),
        meaning: Multilingual(
            tr: "Allah en büyüktür.", de: "Allah ist am größten.", en: "Allah is the Greatest."),
        goal: 33)

    /// Tesbihat after the prayer: 33 / 33 / 33, advances automatically.
    public static let tasbihat = [subhanallah, alhamdulillah, allahuAkbar]

    public static let others: [Dhikr] = [
        Dhikr(
            id: "tevhid", arabic: "لَا اِلٰهَ اِلَّا اللّٰهُ",
            transliteration: Multilingual(
                tr: "Lâ ilâhe illallâh", de: "La ilaha illallah", en: "La ilaha illallah"),
            meaning: Multilingual(
                tr: "Allah'tan başka ilah yoktur.", de: "Es gibt keinen Gott außer Allah.",
                en: "There is no god but Allah."), goal: 100),
        Dhikr(
            id: "istigfar", arabic: "اَسْتَغْفِرُ اللّٰهَ",
            transliteration: Multilingual(tr: "Estağfirullâh", de: "Astaghfirullah", en: "Astaghfirullah"),
            meaning: Multilingual(
                tr: "Allah'tan bağışlanma dilerim.", de: "Ich bitte Allah um Vergebung.",
                en: "I seek Allah's forgiveness."), goal: 100),
        Dhikr(
            id: "salavat", arabic: "اَللّٰهُمَّ صَلِّ عَلٰى مُحَمَّدٍ",
            transliteration: Multilingual(
                tr: "Allâhümme salli alâ Muhammed", de: "Allahumma salli ala Muhammad",
                en: "Allahumma salli ala Muhammad"),
            meaning: Multilingual(
                tr: "Allah'ım, Muhammed'e salât et.", de: "O Allah, segne Muhammad.",
                en: "O Allah, send blessings upon Muhammad."), goal: 100),
        Dhikr(
            id: "subhanallahivebihamdihi", arabic: "سُبْحَانَ اللّٰهِ وَبِحَمْدِهِ",
            transliteration: Multilingual(
                tr: "Sübhânallâhi ve bihamdihî", de: "Subhanallahi wa bihamdihi",
                en: "Subhanallahi wa bihamdihi"),
            meaning: Multilingual(
                tr: "Allah'ı hamd ile tesbih ederim.", de: "Gepriesen sei Allah, und Ihm gebührt das Lob.",
                en: "Glory be to Allah and praise be to Him."), goal: 100),
    ]

    public static func find(_ id: String) -> Dhikr? { (tasbihat + others).first { $0.id == id } }
}

/// Counter state in the Zikirmatik: count, Tur and Tesbihat progress.
public struct DhikrCounter: Sendable, Equatable {
    public enum Event: Equatable, Sendable { case counted, roundFinished, tasbihatFinished }

    public let index: [Dhikr]
    public private(set) var position = 0
    public private(set) var number = 0
    public private(set) var kind = 1
    /// A free counter without a target (sira empty) simply keeps counting.
    public let withoutGoal: Bool

    public init(index: [Dhikr]) {
        self.index = index
        withoutGoal = index.isEmpty
    }

    public var dhikr: Dhikr? { index.indices.contains(position) ? index[position] : nil }
    public var goal: Int? { dhikr?.goal }

    /// One tap. At the target: Tesbihat jumps to the next dhikr, otherwise a new Tur begins.
    public mutating func count() -> Event {
        number += 1
        guard let h = goal, number >= h else { return .counted }
        if index.count > 1 {
            if position + 1 < index.count {
                position += 1
                number = 0
                return .roundFinished
            }
            position = 0
            number = 0
            kind += 1
            return .tasbihatFinished
        }
        number = 0
        kind += 1
        return .roundFinished
    }

    public mutating func undo() {
        if number > 0 { number -= 1 }
    }

    public mutating func reset() {
        position = 0
        number = 0
        kind = 1
    }
}
