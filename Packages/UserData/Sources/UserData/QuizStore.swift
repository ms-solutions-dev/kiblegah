import Foundation
import SwiftData

/// Calculation rules of the quiz, without storage.
public enum QuizScoring {
    /// Points per correct answer; no time bonus, no 50:50 help in V1.
    public static let perPoint = 10
    public static let defaultLevel = 2.0

    /// Level step after a round, relative to ten questions: ≥ 9 correct +0.4, 7–8 +0.2,
    /// 5–6 ±0, ≤ 4 −0.3. Practice rounds move it only half as much (`weight` 0.5) so that nobody
    /// „practices their way up“.
    public static func levelStep(correct: Int, total: Int, weight: Double = 1) -> Double {
        guard total > 0 else { return 0 }
        let ratio = Double(correct) / Double(total)
        let step: Double =
            switch ratio {
            case 0.85...: 0.4
            case 0.65..<0.85: 0.2
            case 0.45..<0.65: 0
            default: -0.3
            }
        return step * weight
    }

    /// New level, limited to 1…5.
    public static func newLevel(_ old: Double, step: Double) -> Double {
        min(5, max(1, ((old + step) * 100).rounded() / 100))
    }

    /// Word label instead of a number: Başlangıç · Temel · Orta · İleri · Derin.
    public enum Tier: String, Sendable, CaseIterable {
        case beginner = "baslangic", basic = "temel", intermediate = "orta", advanced = "ileri", expert =
            "derin"
    }

    public static func tier(_ level: Double) -> Tier {
        switch level {
        case ..<1.5: .beginner
        case ..<2.5: .basic
        case ..<3.5: .intermediate
        case ..<4.5: .advanced
        default: .expert
        }
    }

    /// Repetition with the memorization formula: A mistake comes back tomorrow, then after 3 and about 7 days.
    /// New cards therefore start as if after a first repetition (`repetition` 1, interval 1).
    /// Unlike in memorization, the factor recovers: a mistake costs 0.2, each correct answer brings
    /// 0.1 back up to the starting value, otherwise a once-missed question would come up more and more often forever.
    public static func nextReview(
        interval: Double, ease: Double, repetition: Int, correct: Bool
    )
        -> (interval: Double, ease: Double, repetition: Int)
    {
        let y = MemorizationScheduler.next(
            interval: interval, ease: ease, repetition: repetition, score: correct ? .good : .zor)
        guard correct else { return y }
        return (y.interval, min(easeCeiling, max(y.ease, ease + easeIncrement)), y.repetition)
    }

    /// Starting value and upper limit of the repetition factor.
    public static let easeCeiling = 2.5
    /// Increase per correct repetition.
    public static let easeIncrement = 0.1
}

extension UserStore {
    // MARK: Daily question

    /// The answer to the question of the day `day` (`yyyy-MM-dd`), if already given – from the
    /// home screen or as question 1 of the daily round. Practice answers do not count here.
    public func questionAnswer(day: String) -> SoruCevabi? {
        var d = FetchDescriptor<SoruCevabi>(predicate: #Predicate { $0.gun == day })
        d.sortBy = [SortDescriptor(\.tarih)]
        return ((try? container.mainContext.fetch(d)) ?? []).first(where: \.isQuestionOfTheDay)
    }

    /// Remembers the first answer of a day; later ones change nothing.
    public func answerQuestion(
        day: String, selection: Int, correct: Bool, question: String = "", kind: String = "",
        area: String = ""
    ) {
        guard questionAnswer(day: day) == nil else { return }
        container.mainContext.insert(
            SoruCevabi(
                gun: day, secim: selection, dogru: correct, soru: question, tur: kind, sira: 1, alan: area))
        if !kind.isEmpty, let t = quizRound(kind) { updateRound(t) }
        saveExternal()
    }

    // MARK: Rounds

    public func quizRound(_ identifier: String) -> QuizTuru? {
        try? container.mainContext.fetch(
            FetchDescriptor<QuizTuru>(predicate: #Predicate { $0.kimlik == identifier })
        )
        .first
    }

    /// The daily round of a day (the oldest, if two devices each created one).
    public func dailyKind(day: String) -> QuizTuru? {
        var d = FetchDescriptor<QuizTuru>(predicate: #Predicate { $0.gun == day && $0.cesit == "gunluk" })
        d.sortBy = [SortDescriptor(\.baslangic)]
        return try? container.mainContext.fetch(d).first
    }

    /// Rounds from `day` (`yyyy-MM-dd`) on, oldest first.
    public func quizRounds(cesit: String? = nil, ab day: String = "") -> [QuizTuru] {
        let d = FetchDescriptor<QuizTuru>(
            predicate: #Predicate { $0.gun >= day }, sortBy: [SortDescriptor(\.baslangic)])
        let l = (try? container.mainContext.fetch(d)) ?? []
        return cesit.map { c in l.filter { $0.cesit == c } } ?? l
    }

    @discardableResult
    public func createRound(
        identifier: String = UUID().uuidString, day: String, cesit: String, seed: Int, area: String,
        questions: [String],
        code: String = ""
    ) -> QuizTuru {
        let t = QuizTuru(
            kimlik: identifier, gun: day, cesit: cesit, tohum: seed, alan: area, uzunluk: questions.count)
        t.questionList = questions
        t.kod = code
        container.mainContext.insert(t)
        saveExternal()
        return t
    }

    /// Answers of a round by position.
    public func answers(kind: String) -> [SoruCevabi] {
        let d = FetchDescriptor<SoruCevabi>(
            predicate: #Predicate { $0.tur == kind },
            sortBy: [SortDescriptor(\.sira), SortDescriptor(\.tarih)])
        var seenItems = Set<Int>()
        return ((try? container.mainContext.fetch(d)) ?? []).filter { seenItems.insert($0.sira).inserted }
    }

    /// Stores an answer, counts it toward the round, puts mistakes into the repetition, and at the end
    /// moves the level. A second answer for the same position changes nothing.
    public func answerQuiz(
        _ t: QuizTuru, index: Int, question: String, area: String, selection: Int, correct: Bool,
        duration: Double,
        reviewID: String, now: Date = .now, calendar: Calendar = .current
    ) {
        guard !answers(kind: t.kimlik).contains(where: { $0.sira == index }) else { return }
        container.mainContext.insert(
            SoruCevabi(
                gun: t.cesit == "gunluk" ? t.gun : Self.dayText(now, calendar), secim: selection,
                dogru: correct,
                soru: question, tur: t.kimlik, sira: index, sure: duration, alan: area))
        if t.cesit != "tekrar" && !correct && !reviewID.isEmpty {
            addToReview(reviewID, now: now)
        }
        updateRound(t, now: now)
        saveExternal()
    }

    /// Recounts hits and points and closes the round when all positions are answered.
    func updateRound(_ t: QuizTuru, now: Date = .now) {
        var c = answers(kind: t.kimlik)
        // Question 1 of the daily round is the daily question; it may already be answered on the home screen.
        if t.cesit == "gunluk", !c.contains(where: { $0.sira == 1 }), let g = questionAnswer(day: t.gun) {
            c.append(g)
        }
        t.cevapSayisi = c.count
        t.dogruSayisi = c.filter(\.dogru).count
        if t.cesit == "gunluk" { t.puan = t.dogruSayisi * QuizScoring.perPoint }
        if t.bitis == nil && t.cevapSayisi >= t.uzunluk {
            t.bitis = now
            updateLevels(t)
        }
    }

    /// Level per area after the end of a round: daily round fully, practice half, duel and Tekrar not at all.
    private func updateLevels(_ t: QuizTuru) {
        let weight: Double =
            switch t.cesit {
            case "gunluk": 1
            case "alistirma": 0.5
            default: 0
            }
        guard weight > 0 else { return }
        for (area, l) in Dictionary(grouping: answers(kind: t.kimlik), by: \.alan) where !area.isEmpty {
            let a = areaLevel(area)
            let step = QuizScoring.levelStep(
                correct: l.filter(\.dogru).count, total: l.count, weight: weight)
            a.seviye = QuizScoring.newLevel(a.seviye, step: step)
            a.guncelleme = .now
        }
    }

    // MARK: Level

    /// The entry of an area; created with 2.0 when needed.
    public func areaLevel(_ area: String) -> AlanSeviyesi {
        let d = FetchDescriptor<AlanSeviyesi>(predicate: #Predicate { $0.alan == area })
        if let a = try? container.mainContext.fetch(d).first { return a }
        let a = AlanSeviyesi(alan: area)
        container.mainContext.insert(a)
        return a
    }

    /// Level per area without creating anything; missing areas default to 2.0.
    public func areaLevels() -> [String: Double] {
        var s: [String: Double] = [:]
        for a in (try? container.mainContext.fetch(FetchDescriptor<AlanSeviyesi>())) ?? []
        where s[a.alan] == nil {
            s[a.alan] = a.seviye
        }
        return s
    }

    // MARK: Repetition

    public func reviewCards() -> [TekrarKarti] {
        (try? container.mainContext.fetch(FetchDescriptor<TekrarKarti>(sortBy: [SortDescriptor(\.sonraki)])))
            ?? []
    }

    /// Due by this evening.
    public func dueReviews(now: Date = .now, calendar: Calendar = .current) -> [TekrarKarti] {
        reviewCards().filter { MemorizationScheduler.isDue($0.sonraki, now: now, calendar: calendar) }
    }

    public func isInReview(_ question: String) -> Bool {
        ((try? container.mainContext.fetchCount(
            FetchDescriptor<TekrarKarti>(predicate: #Predicate { $0.soru == question })))
            ?? 0) > 0
    }

    /// New card, due tomorrow; an existing one is set back to tomorrow.
    public func addToReview(_ question: String, now: Date = .now) {
        let d = FetchDescriptor<TekrarKarti>(predicate: #Predicate { $0.soru == question })
        let k =
            (try? container.mainContext.fetch(d).first)
            ?? {
                let yeni = TekrarKarti(soru: question)
                yeni.tekrar = 1
                container.mainContext.insert(yeni)
                return yeni
            }()
        k.aralik = 1
        k.sonraki = now.addingTimeInterval(86400)
        saveExternal()
    }

    public func rateReview(_ question: String, correct: Bool, now: Date = .now) {
        let d = FetchDescriptor<TekrarKarti>(predicate: #Predicate { $0.soru == question })
        guard let k = try? container.mainContext.fetch(d).first else { return }
        let y = QuizScoring.nextReview(
            interval: k.aralik, ease: k.kolaylik, repetition: k.tekrar, correct: correct)
        k.aralik = y.interval
        k.kolaylik = y.ease
        k.tekrar = y.repetition
        k.sonraki = now.addingTimeInterval(y.interval * 86400)
        saveExternal()
    }

    // MARK: Duels

    public func duels() -> [Duello] {
        (try? container.mainContext.fetch(
            FetchDescriptor<Duello>(sortBy: [SortDescriptor(\.tarih, order: .reverse)])))
            ?? []
    }

    @discardableResult
    public func saveDuel(code: String, area: String, length: Int, kind: String) -> Duello {
        let d = Duello(kod: code, alan: area, uzunluk: length)
        d.tur = kind
        container.mainContext.insert(d)
        saveExternal()
        return d
    }

    public func updateDuel(_ d: Duello, opponentName: String, opponentCorrect: Int?) {
        d.karsiAd = opponentName
        d.karsiDogru = opponentCorrect
        saveExternal()
    }

    public func deleteDuel(_ d: Duello) {
        container.mainContext.delete(d)
        saveExternal()
    }

    // MARK: History

    /// When each question was last answered – i.e. shown: identifier → latest time.
    ///
    /// Works without its own model: every shown question that counts has a ``SoruCevabi`` with
    /// identifier and time, and that already syncs via iCloud. Practice rounds thus avoid what was already seen.
    public func quizSeen() -> [String: Date] {
        let d = FetchDescriptor<SoruCevabi>(predicate: #Predicate { $0.soru != "" })
        var t: [String: Date] = [:]
        for c in (try? container.mainContext.fetch(d)) ?? [] where t[c.soru].map({ $0 < c.tarih }) ?? true {
            t[c.soru] = c.tarih
        }
        return t
    }

    /// Hits per question identifier across all rounds (for the quiet badges).
    public func correctQuestions() -> Set<String> {
        let d = FetchDescriptor<SoruCevabi>(predicate: #Predicate { $0.dogru && $0.soru != "" })
        return Set(((try? container.mainContext.fetch(d)) ?? []).map(\.soru))
    }

    // MARK: Counts

    /// All counted answers: one per round and position, the daily question without a round once per day.
    ///
    /// Duplicate entries arise when two devices write the same position via iCloud; the first one
    /// is counted, as in ``answers(kind:)``.
    func countedAnswers(ab day: String = "") -> [SoruCevabi] {
        let d = FetchDescriptor<SoruCevabi>(
            predicate: #Predicate { $0.gun >= day }, sortBy: [SortDescriptor(\.tarih)])
        var seenItems = Set<String>()
        return ((try? container.mainContext.fetch(d)) ?? []).filter {
            seenItems.insert($0.tur.isEmpty ? "g:\($0.gun)" : "\($0.tur):\($0.sira)").inserted
        }
    }

    /// Correct and wrong per area across all rounds; answers without an area are dropped.
    public func quizAreaCounters() -> [String: QuizCounter] {
        var s: [String: QuizCounter] = [:]
        for c in countedAnswers() where !c.alan.isEmpty { s[c.alan, default: QuizCounter()].add(c.dogru) }
        return s
    }

    /// Correct and wrong per day (`yyyy-MM-dd`) from `day` on, daily question and all rounds combined.
    public func quizDayCounters(ab day: String) -> [String: QuizCounter] {
        var s: [String: QuizCounter] = [:]
        for c in countedAnswers(ab: day) { s[c.gun, default: QuizCounter()].add(c.dogru) }
        return s
    }

    /// Due repetitions per area. The card only knows the question; the area comes from the
    /// last answer to the same identifier. Cards from the daily question carry a generator identifier
    /// for which there is no answer; they count only in the total.
    public func dueReviewCounts(now: Date = .now) -> [String: Int] {
        var area: [String: String] = [:]
        for c in countedAnswers() where !c.alan.isEmpty && !c.soru.isEmpty { area[c.soru] = c.alan }
        var s: [String: Int] = [:]
        for k in dueReviews(now: now) {
            if let a = area[k.soru] { s[a, default: 0] += 1 }
        }
        return s
    }

    /// Deletes rounds, quiz answers, repetition, level and duels. The answers to the
    /// daily question remain: they carry the daily item „Soru“ and the streak.
    public func deleteQuizHistory() {
        let c = container.mainContext
        for t in (try? c.fetch(FetchDescriptor<QuizTuru>())) ?? [] { c.delete(t) }
        for s in (try? c.fetch(FetchDescriptor<SoruCevabi>())) ?? [] where !s.isQuestionOfTheDay {
            c.delete(s)
        }
        for k in (try? c.fetch(FetchDescriptor<TekrarKarti>())) ?? [] { c.delete(k) }
        for a in (try? c.fetch(FetchDescriptor<AlanSeviyesi>())) ?? [] { c.delete(a) }
        for d in (try? c.fetch(FetchDescriptor<Duello>())) ?? [] { c.delete(d) }
        saveExternal()
    }
}

/// Correct and wrong of a set of answers.
public struct QuizCounter: Equatable, Sendable {
    public var correct = 0
    public var wrong = 0

    public init(correct: Int = 0, wrong: Int = 0) {
        self.correct = correct
        self.wrong = wrong
    }

    public var total: Int { correct + wrong }
    /// Share correct, 0…1; 0 without answers.
    public var ratio: Double { total == 0 ? 0 : Double(correct) / Double(total) }

    mutating func add(_ d: Bool) {
        if d { correct += 1 } else { wrong += 1 }
    }
}
