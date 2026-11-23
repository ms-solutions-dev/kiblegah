import ContentPacks
import Core
import Foundation
import Observation
import PrayerTimes
import UserData

/// A running round: questions, given answers, the current choice.
///
/// The questions are rebuilt from the round's stored identifiers; only answers are
/// stored. A daily round can thus be continued on the same day, even on another device.
@MainActor @Observable final class QuizSession {
    struct Answer: Equatable {
        let selection: Int
        let correct: Bool
    }

    let kind: QuizTuru
    /// Slot (1…) and question; slots whose question cannot be built with these bundles are missing.
    let questions: [(index: Int, question: QuizQuestion)]
    private(set) var answers: [Int: Answer] = [:]
    var index = 0
    var selection: Int?
    private var launch = Date.now

    init(kind: QuizTuru, questions: [(Int, QuizQuestion)], answers: [Int: Answer]) {
        self.kind = kind
        self.questions = questions.map { (index: $0.0, question: $0.1) }
        self.answers = answers
        index = self.questions.firstIndex { answers[$0.index] == nil } ?? max(0, self.questions.count - 1)
    }

    var finished: Bool { questions.allSatisfy { answers[$0.index] != nil } }
    var current: (index: Int, question: QuizQuestion)? {
        questions.indices.contains(index) ? questions[index] : nil
    }
    var currentAnswer: Answer? { current.flatMap { answers[$0.index] } }
    var correctCount: Int { answers.values.filter(\.correct).count }
    var remaining: Int { questions.filter { answers[$0.index] == nil }.count }

    /// Stores the chosen answer.
    func submitAnswer(store: UserStore) {
        guard let (index, s) = current, let selection, answers[index] == nil else { return }
        let correct = selection == s.correct
        answers[index] = Answer(selection: selection, correct: correct)
        let duration = Date.now.timeIntervalSince(launch)
        if kind.cesit == "tekrar" { store.rateReview(s.identifier, correct: correct) }
        store.answerQuiz(
            kind, index: index, question: s.identifier, area: s.area.rawValue, selection: selection,
            correct: correct,
            duration: duration,
            reviewID: s.reviewID)
    }

    /// To the next open question.
    func next() {
        selection = nil
        launch = .now
        if let i = questions.indices.first(where: { $0 > index && answers[questions[$0].index] == nil }) {
            index = i
        } else if let i = questions.indices.first(where: { answers[questions[$0].index] == nil }) {
            index = i
        }
    }

    // MARK: Setup

    enum Request: Equatable {
        case day
        case repetition
        case duello(String)
        case practice(QuizArea?, Int, Int)

        /// `day`, `repetition`, `duello:<code>`, `practice:<area|karisik>:<length>:<stufe 0…3>`.
        init?(_ text: String) {
            let p = text.split(separator: ":").map(String.init)
            switch p.first {
            case "gun": self = .day
            case "tekrar": self = .repetition
            case "duello" where p.count == 2: self = .duello(p[1])
            case "alistirma" where p.count == 4:
                self = .practice(
                    p[1] == "karisik" ? nil : QuizArea(rawValue: p[1]), Int(p[2]) == 15 ? 15 : 10,
                    Int(p[3]) ?? 0)
            default: return nil
            }
        }

        static func practiceText(_ area: QuizArea?, length: Int, tier: Int) -> String {
            "alistirma:\(area?.rawValue ?? "karisik"):\(length):\(tier)"
        }
    }

    /// Builds or loads the round for a request. `nil` if there is nothing to play (no due
    /// review, invalid duel code).
    static func prepare(
        _ request: Request, contentProvider: any ContentProvider, store: UserStore
    ) async -> QuizSession? {
        let pool = await QuizPoolStore.shared.pool(contentProvider)
        let generator = QuizGenerator(pool: pool)
        let bank = await QuizBanks.questions()
        let today = QuizDay.today()
        let dayNumber = QuizDay.dayNumber(today)
        let ofTheDay = QuestionOfTheDayCard.question(day: today, contentProvider: contentProvider).map {
            QuizQuestion(ofTheDay: $0, dayNumber: dayNumber)
        }

        func parse(_ k: String) -> QuizQuestion? {
            if k == ofTheDay?.identifier { return ofTheDay }
            if let (b, id, seed) = QuizID.decodeBank(k) {
                return bank.first { $0.bank == b && $0.id == id && $0.available }?.question(seed: seed)
            }
            return generator.question(identifier: k)
        }

        let kind: QuizTuru
        switch request {
        case .day:
            if let t = store.dailyKind(day: today.description) {
                kind = t
            } else {
                let plan = QuizPlanner.daily(
                    dayNumber: dayNumber, ofTheDay: ofTheDay, generator: generator, bank: bank)
                guard !plan.isEmpty else { return nil }
                kind = store.createRound(
                    day: today.description, cesit: "gunluk", seed: dayNumber, area: "",
                    questions: plan.map(\.identifier))
            }
        case .repetition:
            let due = store.dueReviews().map(\.soru).filter { parse($0) != nil }
            guard !due.isEmpty else { return nil }
            kind = store.createRound(
                day: today.description, cesit: "tekrar", seed: 0, area: "", questions: due)
        case .duello(let code):
            guard let c = DuelCode.parse(code), c.area?.isBank != true else { return nil }
            let cleaned = DuelCode.create(seed: c.seed, area: c.area, length: c.length)
            if let d = store.duels().first(where: { $0.kod == cleaned }), let t = store.quizRound(d.tur) {
                kind = t
            } else {
                // Duels with a fixed level, without banks and without history: both devices get the same questions.
                let plan = QuizPlanner.practice(
                    seed: c.seed, area: c.area, length: c.length, generator: generator, bank: [],
                    level: { _ in QuizPlanner.dailyLevel })
                guard !plan.isEmpty else { return nil }
                kind = store.createRound(
                    day: today.description, cesit: "duello", seed: Int(c.seed),
                    area: c.area?.rawValue ?? "",
                    questions: plan.map(\.identifier), code: cleaned)
                store.saveDuel(
                    code: cleaned, area: c.area?.rawValue ?? "", length: plan.count, kind: kind.kimlik)
            }
        case .practice(let area, let length, let tier):
            let levels = store.areaLevels()
            let seed = UInt64.random(in: 0..<DuelCode.seedTop)
            let plan = QuizPlanner.practice(
                seed: seed, area: area, length: length, generator: generator, bank: bank,
                level: { a in
                    switch tier {
                    case 1: 1
                    case 2: 2
                    case 3: 3
                    default: Int((levels[a.rawValue] ?? QuizScoring.defaultLevel).rounded())
                    }
                },
                // First what has not come up here yet; Tekrar and the daily round are unaffected.
                seen: QuizSeen(ids: store.quizSeen().map { ($0.key, $0.value) }))
            guard !plan.isEmpty else { return nil }
            kind = store.createRound(
                day: today.description, cesit: "alistirma", seed: Int(seed), area: area?.rawValue ?? "",
                questions: plan.map(\.identifier))
        }

        let list = kind.questionList.enumerated().compactMap { i, k in parse(k).map { (i + 1, $0) } }
        guard !list.isEmpty else { return nil }
        if list.count < kind.uzunluk && kind.bitis == nil { kind.uzunluk = list.count }
        var answers: [Int: Answer] = [:]
        for c in store.answers(kind: kind.kimlik) {
            answers[c.sira] = Answer(selection: c.secim, correct: c.dogru)
        }
        if kind.cesit == "gunluk", answers[1] == nil, let g = store.questionAnswer(day: kind.gun) {
            answers[1] = Answer(selection: g.secim, correct: g.dogru)
        }
        return QuizSession(kind: kind, questions: list, answers: answers)
    }
}
