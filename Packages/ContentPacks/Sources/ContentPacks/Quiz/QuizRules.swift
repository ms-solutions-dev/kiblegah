import Core
import Foundation

/// The four distractor rules of the concept as code.
///
/// The generator picks distractors only via these functions; the tests check every generated
/// question once more from outside with ``violations(_:pool:)``.
///
/// 1. No distractor is an invented religious sentence: options are metadata (surah, number,
///    collection, category, name) or real content (word from the word table, meaning from the
///    Esma pack). Free text exists only in the verified İlmihal bank.
/// 2. Same class, same spacing: all options of the same kind, numbers at least 2 apart.
/// 3. No partially correct options: "Muttefekun aleyh" excludes Buhârî and Müslim (and
///    vice versa), Esma synonym groups never appear together, Dua groups with overlap never.
/// 4. Nothing disputed: no surahs from ``QuestionGenerator/revelationPlaceDisputed`` for Meccan/Medinan, revelation
///    order only with 20 places apart, `disputed` questions never in a round.
public enum QuizRules {
    /// Minimum distance between number options (verse count, Juz).
    public static let numberRange = 2
    /// Minimum distance in revelation order.
    public static let revelationRange = 20

    /// Curated Esma synonym groups (Tirmidhi numbers). Names of one group never appear together
    /// in one question, because one meaning also covers the other. In addition: two names with
    /// the same meaning in any language of the pack never appear together
    /// (``divineNameOverlaps(_:_:divineNames:)``).
    public static let divineNameGroups: [Set<Int>] = [
        [2, 3, 79, 83],  // Rahmân, Rahîm, Berr, Raûf – in the TR pack, Rahmân and Rahîm have the same meaning
        [20, 27, 28, 32],  // Alîm, Semî', Basîr, Habîr
        [15, 35, 82, 80],  // Gaffâr, Gafûr, Afüvv, Tevvâb
        [9, 10, 11, 16],  // Azîz, Cebbâr, Mütekebbir, Kahhâr
        [12, 13, 14, 59, 95],  // Hâlık, Bâri', Musavvir, Mübdi', Bedî'
        [18, 40],  // Rezzâk, Mukît
        [23, 26],  // Hâfıd, Müzill
        [24, 25],  // Râfi', Muiz
        [34, 38, 42, 85],  // Azîm, Kebîr, Celîl, Zü'l-celâli ve'l-ikrâm
        [37, 78],  // Aliyy, Müteâlî
        [49, 66],  // Mecîd, Mâcid
        [54, 55, 69, 70],  // Kavî, Metîn, Kâdir, Muktedir
        [74, 96, 97],  // Âhir, Bâkî, Vâris
        [29, 30, 86],  // Hakem, Adl, Muksit
        [56, 77, 53],  // Velî, Vâlî, Vekîl
        [4, 84],  // Melik, Mâlikü'l-mülk
        [94, 98],  // Hâdî, Reşîd
        [50, 60, 61],  // Bâis, Muîd, Muhyî
        [7, 8, 39, 44],  // Mü'min, Müheymin, Hafîz, Rakîb
        [17, 43],  // Vehhâb, Kerîm
        [33, 99],  // Halîm, Sabûr
        [41, 58],  // Hasîb, Muhsî
        [88, 89],  // Ganî, Mugnî
        [90, 91],  // Mâni', Dârr
    ]

    /// Whether two names may not appear in one question.
    public static func divineNameOverlaps(_ a: Int, _ b: Int, divineNames: [Int: DivineName]) -> Bool {
        if a == b { return true }
        if divineNameGroups.contains(where: { $0.contains(a) && $0.contains(b) }) { return true }
        guard let x = divineNames[a], let y = divineNames[b] else { return false }
        for language in ["tr", "de", "en"] {
            let p = x.meaning(language).map(normal)
            let q = y.meaning(language).map(normal)
            if let p, let q, !p.isEmpty, p == q { return true }
        }
        return false
    }

    /// Collections that must never stand next to `correct` as a distractor (partially correct).
    public static func excludedCollections(_ correct: HadithCollection) -> Set<HadithCollection> {
        switch correct {
        case .muttafaqAlayh: [.bukhari, .muslim]
        case .bukhari, .muslim: [.muttafaqAlayh]
        default: []
        }
    }

    public static func duaDistractors(_ d: Dua) -> [String] {
        let familyRelated: Set<String> = ["2-128", "14-41", "25-74", "40-7-9", "14-40", "66-8"]
        let scholarlyRelated: Set<String> = ["12-101", "20-25-28"]
        switch d.category {
        case "rabbena": return familyRelated.contains(d.slug) ? ["ilim"] : ["aile", "ilim"]
        case "peygamber": return scholarlyRelated.contains(d.slug) ? ["rabbena"] : ["rabbena", "ilim"]
        case "aile": return ["rabbena", "ilim"]
        case "ilim": return ["rabbena", "aile"]
        default: return []
        }
    }

    /// Lowercase without edges and trailing punctuation – for comparing meanings.
    static func normal(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).lowercased()
    }

    /// The consonant skeleton of an Arabic word: without harakat, tatweel and Quran marks, alif
    /// forms unified. Two tiles with the same skeleton would look confusingly similar.
    public static func skeleton(_ word: String) -> String {
        var s = String.UnicodeScalarView()
        for c in word.unicodeScalars {
            switch c.value {
            case 0x064B...0x065F, 0x0670, 0x0640, 0x06D6...0x06ED, 0x08D3...0x08FF: continue
            case 0x0671, 0x0622, 0x0623, 0x0625: s.append("\u{0627}")
            case 0x0649: s.append("\u{064A}")
            default: s.append(c)
            }
        }
        return String(s).trimmingCharacters(in: .whitespaces)
    }

    /// All rule violations of a question; empty means: the question may go into a round.
    public static func violations(_ s: QuizQuestion, pool: QuizPool) -> [String] {
        var h: [String] = []
        if s.disputed { h.append("ihtilafli") }
        if Set(s.options).count != s.options.count { h.append("doppelte Option") }
        if !s.options.indices.contains(s.correct) { h.append("correct answer missing") }
        let number = s.format == .trueFalse ? 2...2 : 3...4
        if !number.contains(s.options.count) { h.append("\(s.options.count) Optionen") }
        if Set(s.options.map(answerClass)).count > 1 { h.append("gemischte Klassen") }
        if s.kind != .bank, s.options.contains(where: { if case .text = $0 { true } else { false } }) {
            h.append("freier Text in einer generierten Frage")
        }
        let surahs = s.options.compactMap { o -> Int? in if case .surah(let n) = o { n } else { nil } }
        let numbers = s.options.compactMap { o -> Int? in
            switch o {
            case .number(let n), .juz(let n): n
            default: nil
            }
        }
        for (i, a) in numbers.enumerated() {
            for b in numbers.dropFirst(i + 1) where abs(a - b) < numberRange {
                h.append("numbers \(a) and \(b) too close")
            }
        }
        let divineNameNumber = s.options.compactMap { o -> Int? in
            switch o {
            case .divineNameLabel(let n), .divineNameMeaning(let n): n
            default: nil
            }
        }
        // The daily question stays as ``QuestionGenerator`` has been asking it for weeks (only same meaning
        // is excluded there); a change would shift answers already given.
        for (i, a) in divineNameNumber.enumerated() where s.kind != .questionOfTheDay {
            for b in divineNameNumber.dropFirst(i + 1)
            where divineNameOverlaps(a, b, divineNames: pool.divineNameNumber) {
                h.append("names \(a) and \(b) overlap")
            }
        }
        let dayKind = s.kind == .questionOfTheDay ? s.dayKind : nil
        switch (s.kind, dayKind) {
        case (.medinanSurah, _), (.meccanSurah, _), (.questionOfTheDay, .medinanSurah?):
            for n in surahs where QuestionGenerator.revelationPlaceDisputed.contains(n) {
                h.append("strittige Sure \(n)")
            }
        case (.firstRevealed, _), (.questionOfTheDay, .firstRevealed?):
            let index = surahs.compactMap { pool.surahByNumber[$0]?.revelationOrder }
            for (i, a) in index.enumerated() {
                for b in index.dropFirst(i + 1) where abs(a - b) < revelationRange {
                    h.append("Nüzul \(a)/\(b) zu nah")
                }
            }
        case (.hadithCollection, _):
            if case .collection(let d) = s.options[safe: s.correct] {
                let forbidden = excludedCollections(d)
                for case .collection(let k) in s.options where forbidden.contains(k) {
                    h.append("teilrichtig: \(k.rawValue) neben \(d.rawValue)")
                }
            }
        case (.duaCategory, _):
            if case .dua(let slug) = s.topic, let d = pool.duas.first(where: { $0.slug == slug }) {
                let allowed = Set(duaDistractors(d) + [d.category])
                for case .duaCategory(let k) in s.options where !allowed.contains(k) {
                    h.append("dua group \(k) overlaps with \(d.category)")
                }
            }
        case (.wordGap, _):
            let skeletons = s.options.compactMap { o -> String? in
                if case .word(let a) = o { pool.wordText(a).map(skeleton) } else { nil }
            }
            if Set(skeletons).count != skeletons.count { h.append("Kacheln zum Verwechseln ähnlich") }
            if skeletons.count != s.options.count { h.append("unbekanntes Wort") }
        default: break
        }
        return h
    }

    /// The class of an option (rule 2).
    static func answerClass(_ o: QuizOption) -> String {
        switch o {
        case .surah: "sure"
        case .number: "sayi"
        case .juz: "cuz"
        case .divineNameMeaning: "esmaAnlami"
        case .divineNameLabel: "esmaAdi"
        case .collection: "koleksiyon"
        case .hadithCategory: "hadisKategorisi"
        case .duaCategory: "duaKategorisi"
        case .word: "kelime"
        case .correct, .wrong: "dogruYanlis"
        case .text: "metin"
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
