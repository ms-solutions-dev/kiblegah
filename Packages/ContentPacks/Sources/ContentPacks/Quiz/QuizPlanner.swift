import Core
import Foundation

/// Assembles rounds.
///
/// The daily round depends only on the day number and the packs: it is the same for all users on
/// the same day, so it uses a fixed level 2 instead of the user's own. Personal adjustment
/// happens only in Alıştırma.
public enum QuizPlanner {
    /// One slot of the curve.
    public enum Position: Sendable, Hashable {
        /// The daily question (daily round only, slot 1).
        case ofTheDay
        /// Mandatory fundamentals slot (İlmihal bank; without verified questions, easy generator questions).
        case basic
        /// A question of the level; `hard` marks the slots above the level.
        case level(Int, hard: Bool)
    }

    /// Fixed level of the daily round (like the starting value per area).
    public static let dailyLevel = 2

    /// The curve: slot 1 easy, 2 and 10 fundamentals, 6/8/9 one level above the level,
    /// 7 breather. With 15 questions the middle repeats; Alıştırma has no mandatory slots.
    public static func curve(length: Int, level n: Int, daily: Bool) -> [Position] {
        let intermediate = min(5, max(1, n))
        let hard = min(5, intermediate + 1)
        let first: Position = daily ? .ofTheDay : .level(min(2, intermediate), hard: false)
        let basic: Position = daily ? .basic : .level(intermediate, hard: false)
        var e: [Position] = [
            first, basic, .level(intermediate, hard: false), .level(intermediate, hard: false),
            .level(intermediate, hard: false),
            .level(hard, hard: true), .level(1, hard: false), .level(hard, hard: true),
            .level(hard, hard: true),
            basic,
        ]
        if length > 10 {
            e.insert(
                contentsOf: [
                    .level(intermediate, hard: false), .level(hard, hard: true), .level(1, hard: false),
                    .level(hard, hard: true), .level(intermediate, hard: false),
                ], at: 9)
        }
        return Array(e.prefix(length))
    }

    /// The slot of the daily round (index) filled by a verified question from Siyer, Sahâbe, Peygamberler
    /// or a later bank – a normal level in the middle, not the breather.
    static let extraBankSlot = 4

    /// The daily round of a day: question 1 is the daily question, 2 and 10 fundamentals (İlmihal). If
    /// the remaining banks contain verified questions, one of them goes into slot 5 – chosen via the
    /// daily seed, hence the same for everyone.
    ///
    /// - Parameters:
    ///   - gunNo: days since 1970 (like ``QuestionGenerator``).
    ///   - gunun: the daily question of this day, already as a quiz question.
    ///   - banka: all banks (empty in the Store edition); only approved ones count.
    public static func daily(
        dayNumber: Int, ofTheDay: QuizQuestion?, generator: QuizGenerator, bank: [BankQuestion]
    ) -> [QuizQuestion] {
        var z = SplitMix64(seed: UInt64(bitPattern: Int64(dayNumber)) &* 0x9E37_79B9_7F4A_7C15 &+ 0x5155_495A)
        return plan(
            curve(length: 10, level: dailyLevel, daily: true), area: nil, ofTheDay: ofTheDay,
            generator: generator,
            bank: bank, level: { _ in dailyLevel }, seen: .empty, rng: &z)
    }

    /// A practice round (or a duel, then with a fixed level, without banks and without history, so
    /// both devices get the same questions).
    ///
    /// - Parameters:
    ///   - alan: one area (also a bank) or `nil` for "Karışık".
    ///   - niveau: level per area (1…5); with a chosen level the same for all areas.
    ///   - gorulme: when each question last appeared; unseen first, then the longest-unseen.
    public static func practice(
        seed: UInt64, area: QuizArea?, length: Int, generator: QuizGenerator, bank: [BankQuestion],
        level: (QuizArea) -> Int, seen: QuizSeen = .empty
    ) -> [QuizQuestion] {
        var z = SplitMix64(seed: seed &* 0xD6E8_FEB8_6659_FD93 &+ 0x414C_4953)
        let n = area.map(level) ?? dailyLevel
        return plan(
            curve(length: length, level: n, daily: false), area: area, ofTheDay: nil, generator: generator,
            bank: bank, level: level, seen: seen, rng: &z)
    }

    /// Question kinds per area (V1).
    static func kinds(_ area: QuizArea) -> [QuizQuestionKind] {
        switch area {
        case .quran: [.verseCount, .surahJuz, .medinanSurah, .meccanSurah, .firstRevealed, .wordGap]
        case .translation: [.translationSurah]
        case .divineName: [.divineNameMeaning, .meaningDivineName]
        case .hadith: [.hadithCollection, .hadithCategory]
        case .dua: [.duaCategory, .duaSurah]
        default: []
        }
    }

    private static func plan(
        _ curve: [Position], area fixed: QuizArea?, ofTheDay: QuizQuestion?, generator: QuizGenerator,
        bank: [BankQuestion], level: (QuizArea) -> Int, seen: QuizSeen, rng z: inout SplitMix64
    ) -> [QuizQuestion] {
        let valid = bank.filter(\.available).sorted { ($0.bank, $0.id) < ($1.bank, $1.id) }
        // Fundamentals: İlmihal only. Fixed bank: only its questions. Extra slot of the daily round: all other banks.
        let baseBank = valid.filter { $0.bank == QuizArea.ilmihal.rawValue }
        let fixedBank = fixed.map { a in valid.filter { $0.bank == a.rawValue } } ?? []
        let ekBank = curve.first == .ofTheDay ? valid.filter { $0.bank != QuizArea.ilmihal.rawValue } : []
        let existing = QuizArea.generated.filter { generator.pool.areas.contains($0) }
        var result: [QuizQuestion] = []
        var used: Set<String> = []
        var areaCount: [QuizArea: Int] = [:]
        var bankUsed: Set<String> = []

        func add(_ s: QuizQuestion, topic: String) {
            result.append(s)
            used.insert(topic)
            areaCount[s.area, default: 0] += 1
        }

        /// Areas for the next slot: mix (at most three times per area, not twice in a row),
        /// until at least four areas have appeared.
        func areaOrder(remaining: Int) -> [QuizArea] {
            if let fixed, !fixed.isBank { return [fixed] }
            var l = QuestionGenerator.shuffle(existing, &z).filter { (areaCount[$0] ?? 0) < 3 }
            let end = result.last?.area
            l.sort { a, b in (a == end ? 1 : 0, areaCount[a] ?? 0) < (b == end ? 1 : 0, areaCount[b] ?? 0) }
            // If areas are still missing up to four and slots run out: new ones first.
            let missing = 4 - areaCount.filter { $0.value > 0 }.count
            if missing > 0 && remaining <= missing {
                l.sort { (areaCount[$0] ?? 0) < (areaCount[$1] ?? 0) }
            }
            return l.isEmpty ? existing : l
        }

        func generate(level goal: Int, remaining: Int) -> QuizQuestion? {
            for a in areaOrder(remaining: remaining) {
                let n = goal
                // First unseen ones in the area, only once the area is exhausted the longest-unseen.
                // Without history there is only the first pass (daily round, duel: as before).
                for fresh in seen.isEmpty ? [true] : [true, false] {
                    // First the desired level, then the next lower, then the next higher.
                    for sv in [n, n - 1, n + 1, n - 2, n + 2].filter({ (1...5).contains($0) }) {
                        for t in QuestionGenerator.shuffle(kinds(a), &z) {
                            if let s = generator.question(
                                t, level: sv, excluding: used, seen: seen, fresh: fresh, rng: &z)
                            {
                                return s
                            }
                        }
                    }
                }
            }
            return nil
        }

        /// A bank question from `list` that has not yet appeared in this round: unseen first, then the
        /// longest-unseen; `kolay` prefers level 1–2 (early slots).
        func fromBank(_ list: [BankQuestion], kolay: Bool = false) -> BankQuestion? {
            let candidates = list.filter { !bankUsed.contains("\($0.bank):\($0.id)") }
            guard !candidates.isEmpty else { return nil }
            let key: (BankQuestion) -> String = { "\($0.bank):\($0.id)" }
            var pool = seen.pick(candidates, fresh: true, key: key)
            if pool.isEmpty { pool = seen.pick(candidates, fresh: false, key: key) }
            if kolay, pool.contains(where: { $0.level <= 2 }) { pool = pool.filter { $0.level <= 2 } }
            let b = pool[z.pick(pool.count)]
            bankUsed.insert(key(b))
            return b
        }

        for (i, place) in curve.enumerated() {
            let remaining = curve.count - i
            switch place {
            case .ofTheDay:
                if let ofTheDay {
                    add(ofTheDay, topic: ofTheDay.identifier)
                } else if let s = generate(level: 1, remaining: remaining) {
                    add(s, topic: QuizID.parse(s.identifier)?.key ?? s.identifier)
                }
            case .basic:
                if let b = fromBank(baseBank, kolay: i < 5) {
                    add(b.question(seed: z.next() % 1_000_000), topic: "\(b.bank):\(b.id)")
                } else if let s = generate(level: 1 + z.pick(2), remaining: remaining) {
                    // As long as there is no verified question: easy generator question (level 1–2).
                    add(s, topic: QuizID.parse(s.identifier)?.key ?? s.identifier)
                }
            case .level(let sv, let hard):
                if fixed?.isBank == true {
                    guard let b = fromBank(fixedBank) else { continue }
                    add(b.question(seed: z.next() % 1_000_000), topic: "\(b.bank):\(b.id)")
                    continue
                }
                // Daily round: one slot for the other banks (level ≤ 3 preferred), only if they contain
                // approved questions – otherwise the seed draws as before.
                if i == extraBankSlot, !ekBank.isEmpty {
                    let suitable = ekBank.filter { $0.level <= 3 }
                    if let b = fromBank(suitable.isEmpty ? ekBank : suitable) {
                        add(b.question(seed: z.next() % 1_000_000), topic: "\(b.bank):\(b.id)")
                        continue
                    }
                }
                // In Alıştırma the area's level determines the level; zor slots one above.
                var goal = sv
                if ofTheDay == nil, let fixed {
                    let n = level(fixed)
                    goal = sv == 1 ? 1 : min(5, n + (hard ? 1 : 0))
                }
                if let s = generate(level: goal, remaining: remaining) {
                    add(s, topic: QuizID.parse(s.identifier)?.key ?? s.identifier)
                }
            }
        }
        return result
    }
}

/// The code of a duel: six characters without lookalikes (no 0/O, 1/I), containing seed,
/// area and length. Whoever has the code gets the same questions in the same order.
public enum DuelCode {
    static let alphabet = Array("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")
    /// 26 bits seed, 3 bits area (0 = Karışık), 1 bit length = 30 bits = 6 characters of 5 bits each.
    public static let seedTop: UInt64 = 1 << 26

    public static func create(seed: UInt64, area: QuizArea?, length: Int) -> String {
        let a = UInt64(area.flatMap { QuizArea.allCases.firstIndex(of: $0) }.map { $0 + 1 } ?? 0)
        var value = ((seed % seedTop) << 4) | (a << 1) | (length > 10 ? 1 : 0)
        var k: [Character] = []
        for _ in 0..<6 {
            k.append(alphabet[Int(value & 31)])
            value >>= 5
        }
        return String(k.reversed())
    }

    /// Reads a code; hyphen, spaces and lowercase letters are allowed.
    public static func parse(_ code: String) -> (seed: UInt64, area: QuizArea?, length: Int)? {
        let cleaned = code.uppercased().filter { $0 != "-" && $0 != " " }
        guard cleaned.count == 6 else { return nil }
        var value: UInt64 = 0
        for c in cleaned {
            guard let i = alphabet.firstIndex(of: c) else { return nil }
            value = value << 5 | UInt64(i)
        }
        let a = Int((value >> 1) & 7)
        guard a <= QuizArea.allCases.count else { return nil }
        return (value >> 4, a == 0 ? nil : QuizArea.allCases[a - 1], value & 1 == 1 ? 15 : 10)
    }

    /// "K7R-4MQ" – readable in two halves.
    public static func formatted(_ code: String) -> String {
        let t = code.uppercased().filter { $0 != "-" && $0 != " " }
        guard t.count == 6 else { return code }
        return "\(t.prefix(3))-\(t.suffix(3))"
    }
}
