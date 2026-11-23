import Core
import Foundation
import Testing

@testable import ContentPacks

/// Quiz against the real packs: distractor rules per question kind, curve, same daily round, duel code.
@Suite(.enabled(if: contentPacksAvailable && hadithPackAvailable, "content packs missing: run tools/content/fetch.sh"))
struct QuizTests {
    static let pool = QuizPool(contentProvider: ContentProviderTests.contentProvider)
    var pool: QuizPool { Self.pool }
    var generator: QuizGenerator { QuizGenerator(pool: pool) }

    /// Every question kind, many subjects and seeds: no rule violation, correct answer from the data.
    @Test(arguments: QuizQuestionKind.allCases.filter { $0 != .questionOfTheDay && $0 != .bank })
    func distractorRules(kind: QuizQuestionKind) throws {
        let topics = pool.topics(kind)
        #expect(!topics.isEmpty, "no topics for \(kind)")
        var generated = 0
        for (i, k) in topics.enumerated() where i % max(1, topics.count / 150) == 0 {
            for seed: UInt64 in [1, 77, 4242] {
                guard let s = generator.question(kind, key: k.key, seed: seed) else { continue }
                generated += 1
                #expect(QuizRules.violations(s, pool: pool) == [], "\(s.identifier)")
                #expect(isCorrect(s), "\(s.identifier): correct answer does not match the data")
                // Reproducible from the identifier.
                #expect(generator.question(identifier: s.identifier) == s)
            }
        }
        #expect(generated > 0)
    }

    func isCorrect(_ s: QuizQuestion) -> Bool {
        let d = s.options[s.correct]
        switch (s.kind, s.topic, d) {
        case (.translationSurah, .verse(.verse(let n, _)), .surah(let x)): return n == x
        case (.verseCount, .surah(let n), .number(let x)): return pool.surahByNumber[n]?.verseCount == x
        case (.surahJuz, .surah(let n), .juz(let x)): return pool.singleJuz[n] == x
        case (.medinanSurah, _, .surah(let x)):
            return pool.surahByNumber[x]?.revelationPlace == .medinan
                && s.options.filter {
                    if case .surah(let n) = $0 {
                        pool.surahByNumber[n]?.revelationPlace == .medinan
                    } else {
                        false
                    }
                }
                .count == 1
        case (.meccanSurah, _, .surah(let x)):
            return pool.surahByNumber[x]?.revelationPlace == .meccan
                && s.options.filter {
                    if case .surah(let n) = $0 {
                        pool.surahByNumber[n]?.revelationPlace == .meccan
                    } else {
                        false
                    }
                }
                .count == 1
        case (.firstRevealed, _, .surah(let x)):
            let index = s.options.compactMap { o -> Int? in
                if case .surah(let n) = o { pool.surahByNumber[n]?.revelationOrder } else { nil }
            }
            return pool.surahByNumber[x]?.revelationOrder == index.min()
        case (.wordGap, .word(let k), .word(let x)): return k == x
        case (.divineNameMeaning, .divineName(let n), .divineNameMeaning(let x)),
            (.meaningDivineName, .divineName(let n), .divineNameLabel(let x)):
            return n == x
        case (.hadithCollection, .hadith(let n), .collection(let k)): return pool.hadiths[n]?.collection == k
        case (.hadithCategory, .hadith(let n), .hadithCategory(let k)):
            return pool.hadiths[n]?.topCategory == k
        case (.duaCategory, .dua(let slug), .duaCategory(let k)):
            return pool.duas.first { $0.slug == slug }?.category == k
        case (.duaSurah, .dua(let slug), .surah(let n)):
            return pool.duas.first { $0.slug == slug }?.surah == n
        default: return false
        }
    }

    @Test func muttafaqAlayhWithoutBukhariMuslim() throws {
        #expect(HadithCollection.parse("Muttefekun Aleyh") == .muttafaqAlayh)
        #expect(HadithCollection.parse("Buhârî rivayet etmiştir.") == .bukhari)
        #expect(HadithCollection.parse("Müslim rivayet etmiştir - Muttefekun Aleyh") == nil)
        #expect(HadithCollection.parse("İbn Mâce rivayet etmiştir") == .ibnMajah)
        let mk = pool.topics(.hadithCollection).filter {
            guard case .hadith(_, let n)? = ContentKey(text: $0.key) else { return false }
            return pool.hadiths[n]?.collection == .muttafaqAlayh
        }
        #expect(!mk.isEmpty)
        for k in mk.prefix(60) {
            let s = try #require(generator.question(.hadithCollection, key: k.key, seed: 9))
            #expect(
                !s.options.contains(.collection(.bukhari)) && !s.options.contains(.collection(.muslim)))
        }
    }

    @Test func divineNameSynonymsNeverTogether() throws {
        // Rahmân and Rahîm have the same meaning in the TR pack.
        #expect(QuizRules.divineNameOverlaps(2, 3, divineNames: pool.divineNameNumber))
        #expect(QuizRules.divineNameOverlaps(20, 32, divineNames: pool.divineNameNumber))
        #expect(QuizRules.divineNameOverlaps(69, 70, divineNames: pool.divineNameNumber))  // same TR meaning
        #expect(!QuizRules.divineNameOverlaps(47, 5, divineNames: pool.divineNameNumber))
        for seed: UInt64 in 0..<40 {
            for kind in [QuizQuestionKind.divineNameMeaning, .meaningDivineName] {
                let s = try #require(generator.question(kind, key: "e:2", seed: seed))
                #expect(
                    !s.options.contains(.divineNameMeaning(3)) && !s.options.contains(.divineNameLabel(3)))
            }
        }
    }

    @Test func disputedNeverAsked() {
        for k in pool.topics(.medinanSurah) + pool.topics(.meccanSurah) {
            guard case .surah(let n)? = ContentKey(text: k.key) else { continue }
            #expect(!QuestionGenerator.revelationPlaceDisputed.contains(n))
        }
        var b = BankQuestion(
            id: "x", text: .init(tr: "?"), options: .init(tr: ["2", "4", "3"]), correct: 0,
            review: .init(approval: true))
        #expect(b.available)
        b.disputed = true
        #expect(!b.available)
        b.disputed = false
        b.review = nil
        #expect(b.available)  // unverified may be included
        b.review = .init(approval: false)
        #expect(!b.available)
    }

    @Test func duaGroupsWithoutOverlap() throws {
        for k in pool.topics(.duaCategory) {
            let s = try #require(generator.question(.duaCategory, key: k.key, seed: 3))
            #expect(
                !s.options.contains(.duaCategory("peygamber"))
                    || s.options[s.correct] == .duaCategory("peygamber"))
        }
        // 2:127 (Rabbenâ, spoken by İbrâhîm) never asks for "Peygamber".
        let s = try #require(generator.question(.duaCategory, key: "d:2-127", seed: 1))
        #expect(!s.options.contains(.duaCategory("peygamber")))
    }

    /// The same daily round on "two devices": two separately built pools, same day.
    @Test func dailyRoundSameOnTwoDevices() throws {
        let secondOne = QuizGenerator(
            pool: QuizPool(contentProvider: try PackRegistry(folders: [ContentProviderTests.packs])))
        for day in [20_745, 20_746, 21_000] {
            let g = QuestionGenerator.generate(
                dayNumber: day, surahs: pool.surahs,
                divineNames: ContentProviderTests.contentProvider.divineNames(),
                verses: [.verse(surah: 94, verse: 5)], language: "tr"
            ).map { QuizQuestion(ofTheDay: $0, dayNumber: day) }
            let a = QuizPlanner.daily(dayNumber: day, ofTheDay: g, generator: generator, bank: [])
            let b = QuizPlanner.daily(dayNumber: day, ofTheDay: g, generator: secondOne, bank: [])
            #expect(a.map(\.identifier) == b.map(\.identifier))
            #expect(a.count == 10)
            #expect(a.first?.identifier == QuizID.ofTheDay(day))
            #expect(
                a.map(\.identifier)
                    != QuizPlanner.daily(dayNumber: day + 1, ofTheDay: g, generator: generator, bank: []).map(
                        \.identifier))
            #expect(Set(a.map(\.identifier)).count == 10)
            for s in a.dropFirst() { #expect(QuizRules.violations(s, pool: pool) == [], "\(s.identifier)") }
            // Mix: at least four areas, none more than three times.
            let areas = Dictionary(grouping: a, by: \.area).mapValues(\.count)
            #expect(areas.count >= 4, "\(areas)")
            #expect(areas.values.allSatisfy { $0 <= 3 }, "\(areas)")
        }
    }

    /// Curve: 2 and 10 fundamentals, 7 breather, 6/8/9 above the level.
    @Test func curve() {
        let e = QuizPlanner.curve(length: 10, level: 2, daily: true)
        #expect(e[0] == .ofTheDay && e[1] == .basic && e[9] == .basic)
        #expect(e[6] == .level(1, hard: false))
        for i in [5, 7, 8] { #expect(e[i] == .level(3, hard: true)) }
        #expect(QuizPlanner.curve(length: 15, level: 3, daily: false).count == 15)
        #expect(!QuizPlanner.curve(length: 10, level: 3, daily: false).contains(.basic))
    }

    /// Without a verified bank: slots 2 and 10 easy generator questions; with a bank: İlmihal.
    @Test func basicsSlots() {
        let day = 20_800
        let without = QuizPlanner.daily(dayNumber: day, ofTheDay: nil, generator: generator, bank: [])
        #expect(without[1].level <= 2 && without[9].level <= 2)
        let bank = (1...5).map {
            BankQuestion(
                id: "namaz-\($0)", level: 1, text: .init(tr: "Soru \($0)"),
                options: .init(tr: ["2", "3", "4", "5"]), correct: 0,
                review: .init(reviewer: "Reviewer", approval: true))
        }
        let withBank = QuizPlanner.daily(dayNumber: day, ofTheDay: nil, generator: generator, bank: bank)
        #expect(
            withBank[1].kind == .bank && withBank[9].kind == .bank
                && withBank[1].identifier != withBank[9].identifier)
        // The bank sorts numbers, the correct one comes first: shuffling happens per seed.
        let positions = Set((0..<20).map { bank[0].question(seed: UInt64($0)).correct })
        #expect(positions.count > 1)
        let s = bank[0].question(seed: 5)
        #expect(s.options[s.correct] == .text(0))
        #expect(bank[0].question(seed: 5) == s)
        // Rejected ones stay out.
        let draft = bank.map {
            var b = $0; b.review = .init(approval: false); return b
        }
        #expect(
            !QuizPlanner.daily(dayNumber: day, ofTheDay: nil, generator: generator, bank: draft).contains {
                $0.kind == .bank
            })
    }

    @Test func practiceAreaAndLevel() {
        for area in QuizArea.generated {
            let r = QuizPlanner.practice(
                seed: 99, area: area, length: 15, generator: generator, bank: [], level: { _ in 3 })
            #expect(r.count == 15, "\(area): \(r.count)")
            #expect(r.allSatisfy { $0.area == area })
            #expect(Set(r.map(\.identifier)).count == r.count)
        }
        let a = QuizPlanner.practice(
            seed: 5, area: nil, length: 10, generator: generator, bank: [], level: { _ in 2 })
        let b = QuizPlanner.practice(
            seed: 5, area: nil, length: 10, generator: generator, bank: [], level: { _ in 2 })
        #expect(a.map(\.identifier) == b.map(\.identifier) && a.count == 10)
    }

    @Test func duelCode() throws {
        for (seed, area, length) in [
            (UInt64(0), QuizArea?.none, 10), (12_345_678, .hadith, 15),
            (DuelCode.seedTop - 1, .ilmihal, 10),
        ] {
            let k = DuelCode.create(seed: seed, area: area, length: length)
            #expect(
                k.count == 6 && !k.contains("0") && !k.contains("O") && !k.contains("I") && !k.contains("1"))
            let c = try #require(DuelCode.parse(k))
            #expect(c.seed == seed && c.area == area && c.length == length)
            #expect(DuelCode.parse(DuelCode.formatted(k).lowercased())?.seed == seed)
        }
        #expect(DuelCode.parse("K7R-4M") == nil)
        #expect(DuelCode.parse("K0R4MQ") == nil)
        #expect(DuelCode.formatted("k7r4mq") == "K7R-4MQ")
    }

    @Test func identifiers() {
        #expect(QuizID.parse("gen:mealSure:a:112:1:8812")?.key == "a:112:1")
        #expect(QuizID.parse("gen:mealSure:a:112:1:8812")?.seed == 8812)
        #expect(QuizID.parse("kur:quiz-ilmihal:x:1") == nil)
        #expect(QuizID.decodeBank("kur:quiz-ilmihal:namaz-0042:17")?.id == "namaz-0042")
        let s = QuizID.decodeBank("kur:quiz-siyer:siyer-0007:31")
        #expect(s != nil)
        #expect(s?.bank == "siyer" && s?.id == "siyer-0007" && s?.seed == 31)
        #expect(QuizID.decodeBank("kur:quiz-:x:1") == nil)
        #expect(QuizID.topicKey("gen:mealSure:a:112:1:8812") == "mealSure:a:112:1")
        #expect(QuizID.topicKey("kur:quiz-sahabe:sahabe-0001:9") == "sahabe:sahabe-0001")
        #expect(QuizID.topicKey("gun:20745") == nil)
        #expect(QuizID.dayNumber("gun:20745") == 20_745)
    }

    @Test func readIlmihalBank() throws {
        let json = """
            {"sorular":[{"id":"abdest-0001","alan":"ilmihal","konu":"abdest","bicim":"dortSecenek","seviye":1,
            "ihtilafli":false,"metin":{"tr":"Abdestin farzları kaç tanedir?","de":"Wie viele?","en":"How many?"},
            "secenekler":{"tr":["3","4","5","6"],"de":["3","4","5","6"],"en":["3","4","5","6"]},"dogru":1,
            "beleg":{"eser":"ilmihal1","cilt":1,"sayfa":197,"pdf_sayfa":227,"alinti":"…"},"kontrol":null},
            {"id":"abdest-0012","bicim":"dogruYanlis","seviye":2,"ihtilafli":false,"metin":{"tr":"…"},
            "secenekler":{"tr":["Doğru","Yanlış"]},"dogru":0,"kontrol":{"kim":"Reviewer","onay":true}},
            {"kaputt":true}]}
            """
        let l = try BankQuestion.parse(Data(json.utf8), bank: "ilmihal")
        #expect(l.count == 2)
        #expect(l[0].citation?.pdfPage == 227 && !l[0].approved)
        #expect(l[1].available && l[1].question(seed: 1).options == [.correct, .wrong])
        #expect(l[0].question(seed: 3).identifier == "kur:quiz-ilmihal:abdest-0001:3")
    }

    /// Bank list and questions of the new banks: second source (work or translation verse), bank from the path.
    @Test func readBanks() throws {
        let list = try QuizBank.parse(
            Data(
                """
                {"bankalar":[{"banka":"siyer","ad":{"tr":"Siyer","de":"Prophetenbiografie (Siyer)","en":"Seerah"},
                "sayi":40,"onayli":3},{"banka":"peygamber","sayi":40},{"banka":"../x"}]}
                """.utf8))
        #expect(list.map(\.bank) == ["siyer", "peygamber"])
        #expect(list[0].name.text("de") == "Prophetenbiografie (Siyer)" && list[0].approved == 3)
        let json = """
            {"sorular":[{"id":"peygamber-0001","alan":"peygamber","konu":"adem","bicim":"dortSecenek","seviye":1,
            "ihtilafli":false,"metin":{"tr":"Kim secde etmedi?"},"secenekler":{"tr":["Cebrâil","İblis","Mîkâil","İsrâfil"]},
            "dogru":1,"beleg":{"eser":"kissalar","cilt":null,"sayfa":11,"pdf_sayfa":12,"alinti":"İblis …"},
            "beleg2":{"eser":"meal-tr-diyanet","ayet":"2:34","alinti":"İblis müstesna …"},
            "kontrol":{"kim":"Reviewer","onay":true}},
            {"id":"siyer-0001","metin":{"tr":"?"},"secenekler":{"tr":["a","b","c","d"]},"dogru":1,
            "beleg":{"eser":"sallabi1","cilt":1,"sayfa":61},"beleg2":{"eser":"hisam2","cilt":2,"sayfa":"x"}}]}
            """
        let l = try BankQuestion.parse(Data(json.utf8), bank: "peygamber")
        #expect(l.count == 2 && l.allSatisfy { $0.bank == "peygamber" })
        #expect(l[0].citation2?.verseKey == .verse(surah: 2, verse: 34))
        #expect(l[0].citation?.workName == "kissalar" && l[1].citation2?.workName == "hisam")
        #expect(l[1].citation2?.volume == 2 && l[1].citation2?.page == nil)
        let s = l[0].question(seed: 4)
        #expect(s.area == QuizArea(bank: "peygamber") && s.area.isBank && s.kind == .bank)
        #expect(s.topic == .bank("peygamber", "peygamber-0001"))
        #expect(QuizID.decodeBank(s.identifier)?.bank == "peygamber")
    }

    static func bankQuestions(_ bank: String, _ n: Int, approval: Bool? = true) -> [BankQuestion] {
        (1...n).map {
            BankQuestion(
                id: "\(bank)-\(String(format: "%04d", $0))", bank: bank, level: 1 + $0 % 3,
                text: .init(tr: "Soru \($0)"), options: .init(tr: ["a", "b", "c", "d"]), correct: $0 % 4,
                review: approval.map { .init(reviewer: "Reviewer", approval: $0) })
        }
    }

    /// Daily round: fundamentals remain İlmihal, slot 5 comes from one of the other banks – the same on
    /// every device; without anything verified there, the round stays as without banks.
    @Test func dailyRoundWithMoreBanks() {
        let day = 20_811
        let ilmihal = Self.bankQuestions("ilmihal", 6)
        let ek = Self.bankQuestions("siyer", 12) + Self.bankQuestions("sahabe", 12)
        let a = QuizPlanner.daily(dayNumber: day, ofTheDay: nil, generator: generator, bank: ilmihal + ek)
        let b = QuizPlanner.daily(
            dayNumber: day, ofTheDay: nil, generator: generator, bank: ek.reversed() + ilmihal)
        #expect(a.map(\.identifier) == b.map(\.identifier))
        #expect(a[1].area == .ilmihal && a[9].area == .ilmihal)
        let p = QuizPlanner.extraBankSlot
        #expect(["siyer", "sahabe"].contains(a[p].area.rawValue), "\(a[p].identifier)")
        #expect(a.filter { $0.area.isBank && $0.area != .ilmihal }.count == 1)
        // Only rejected ones in the other banks: round as without them.
        let draft = Self.bankQuestions("siyer", 12, approval: false)
        #expect(
            QuizPlanner.daily(dayNumber: day, ofTheDay: nil, generator: generator, bank: ilmihal + draft).map(
                \.identifier)
                == QuizPlanner.daily(dayNumber: day, ofTheDay: nil, generator: generator, bank: ilmihal).map(
                    \.identifier))
    }

    /// Practice in a bank: only its approved questions, each at most once.
    @Test func practiceInOneBank() {
        let rejected = (1...3).map {
            BankQuestion(
                id: "sahabe-900\($0)", bank: "sahabe", text: .init(tr: "?"),
                options: .init(tr: ["a", "b", "c", "d"]), correct: 0, review: .init(approval: false))
        }
        let bank = Self.bankQuestions("sahabe", 12) + rejected + Self.bankQuestions("siyer", 12)
        let r = QuizPlanner.practice(
            seed: 7, area: QuizArea(bank: "sahabe"), length: 10, generator: generator, bank: bank,
            level: { _ in 2 })
        #expect(r.count == 10)
        #expect(r.allSatisfy { QuizID.decodeBank($0.identifier)?.bank == "sahabe" })
        #expect(!r.contains { QuizID.decodeBank($0.identifier)?.id.hasPrefix("sahabe-9") == true })
        #expect(Set(r.map { QuizID.topicKey($0.identifier) }).count == 10)
    }

    /// Avoid seen questions: first unseen per area, only then the longest-unseen.
    @Test func avoidSeenQuestions() throws {
        // Bank: 12 questions, 9 of them seen → the three unseen come first.
        let bank = Self.bankQuestions("siyer", 12)
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        var dates: [String: Date] = [:]
        for (i, b) in bank.prefix(9).enumerated() {
            dates["siyer:\(b.id)"] = now.addingTimeInterval(Double(i) * 3600)
        }
        let r = QuizPlanner.practice(
            seed: 3, area: QuizArea(bank: "siyer"), length: 10, generator: generator, bank: bank,
            level: { _ in 2 }, seen: QuizSeen(dates: dates))
        let ids = r.compactMap { QuizID.decodeBank($0.identifier)?.id }
        #expect(Set(ids.prefix(3)) == Set(bank.suffix(3).map(\.id)), "\(ids)")
        // Then the longest-unseen (the one seen first) before the most recently seen.
        #expect(ids[3] == bank[0].id || ids[3] == bank[1].id || ids[3] == bank[2].id, "\(ids)")

        // Generator: all Esmâ subjects of the level seen except one → that one comes.
        let topics = pool.topics(.divineNameMeaning).filter { $0.level == 2 }
        let free = try #require(topics.last)
        var g: [String: Date] = [:]
        for k in pool.topics(.divineNameMeaning) + pool.topics(.meaningDivineName) where k.key != free.key {
            g["esmaAnlami:\(k.key)"] = now
            g["anlamEsma:\(k.key)"] = now
        }
        let e = QuizPlanner.practice(
            seed: 11, area: .divineName, length: 10, generator: generator, bank: [], level: { _ in 2 },
            seen: QuizSeen(dates: g))
        #expect(e.count == 10)
        let first = try #require(e.first.flatMap { QuizID.parse($0.identifier) })
        #expect(first.key == free.key, "\(e.map(\.identifier))")
        // Without history the round stays as it was (duel, daily round).
        #expect(
            QuizPlanner.practice(
                seed: 11, area: .divineName, length: 10, generator: generator, bank: [], level: { _ in 2 }
            ).map(\.identifier)
                == QuizPlanner.practice(
                    seed: 11, area: .divineName, length: 10, generator: generator, bank: [],
                    level: { _ in 2 },
                    seen: .empty
                ).map(\.identifier))
    }

    @Test func seenFromIdentifiers() {
        let a = Date(timeIntervalSince1970: 100)
        let b = Date(timeIntervalSince1970: 200)
        let g = QuizSeen(ids: [
            ("gen:esmaAnlami:e:5:11", b), ("gen:esmaAnlami:e:5:99", a), ("kur:quiz-siyer:siyer-0001:4", a),
            ("gun:20000", b),
        ])
        #expect(g.dates == ["esmaAnlami:e:5": b, "siyer:siyer-0001": a])
    }
}
