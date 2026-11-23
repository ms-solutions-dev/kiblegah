import Foundation
import SwiftData
import Testing

@testable import UserData

@MainActor @Suite struct QuizStoreTests {
    func defaults() throws -> UserStore {
        UserStore(container: try UserDataSchema.container(iCloud: false, inMemory: true))
    }

    /// Daily question on the home screen = question 1 of the daily round; practice rounds give no daily point.
    @Test func dailyQuestionIsQuestionOne() throws {
        let d = try defaults()
        d.answerQuestion(day: "2026-10-19", selection: 2, correct: true)
        let t = d.createRound(
            day: "2026-10-19", cesit: "gunluk", seed: 20745, area: "",
            questions: (1...10).map { "gen:x:\($0):1" })
        for i in 2...10 {
            d.answerQuiz(
                t, index: i, question: "gen:ayetSayisi:s:\(i):1", area: i % 2 == 0 ? "kuran" : "esma",
                selection: 0,
                correct: i != 5, duration: 3, reviewID: "gen:ayetSayisi:s:\(i):1")
        }
        #expect(t.isFinished && t.cevapSayisi == 10 && t.dogruSayisi == 9 && t.puan == 90)
        #expect(d.isInReview("gen:ayetSayisi:s:5:1") && !d.isInReview("gen:ayetSayisi:s:4:1"))
        #expect(d.areaLevels()["kuran"] == 2.4)  // 5/5 correct
        // second answer for the same position does not count
        d.answerQuiz(
            t, index: 3, question: "x", area: "kuran", selection: 1, correct: false, duration: 1, reviewID: ""
        )
        #expect(t.dogruSayisi == 9)

        let a = d.createRound(day: "2026-10-20", cesit: "alistirma", seed: 1, area: "", questions: ["a"])
        d.answerQuiz(
            a, index: 1, question: "gen:a", area: "kuran", selection: 0, correct: true, duration: 1,
            reviewID: ""
        )
        let n = d.dailyPoints(
            now: try #require(ISO8601DateFormatter().date(from: "2026-10-20T12:00:00Z")))
        #expect(!n.question)
        #expect(a.puan == nil)
    }

    @Test func subEntriesStayValid() throws {
        let d = try defaults()
        d.container.mainContext.insert(SoruCevabi(gun: "2026-10-18", secim: 1, dogru: false))
        #expect(d.questionAnswer(day: "2026-10-18")?.isQuestionOfTheDay == true)
        d.deleteQuizHistory()
        #expect(d.questionAnswer(day: "2026-10-18") != nil)
    }

    @Test func leitner() throws {
        let d = try defaults()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        d.addToReview("gen:q", now: t0)
        #expect(d.dueReviews(now: t0).isEmpty)
        let k = try #require(d.reviewCards().first)
        #expect(k.sonraki == t0.addingTimeInterval(86400))
        d.rateReview("gen:q", correct: true, now: t0)
        #expect(k.aralik == 3)
        d.rateReview("gen:q", correct: true, now: t0)
        #expect(k.aralik == 8)
        d.rateReview("gen:q", correct: false, now: t0)
        #expect(k.aralik == 1 && k.tekrar == 0)
    }

    /// A mistake pushes the factor down, correct answers bring it back up to 2.5, not beyond.
    @Test func factorRecovers() throws {
        let d = try defaults()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        d.addToReview("gen:q", now: t0)
        let k = try #require(d.reviewCards().first)
        d.rateReview("gen:q", correct: false, now: t0)
        d.rateReview("gen:q", correct: false, now: t0)
        #expect(abs(k.kolaylik - 2.1) < 0.001)
        d.rateReview("gen:q", correct: true, now: t0)
        #expect(abs(k.kolaylik - 2.2) < 0.001)
        for _ in 0..<5 { d.rateReview("gen:q", correct: true, now: t0) }
        #expect(k.kolaylik == 2.5)
    }

    @Test func levelAndStage() {
        #expect(QuizScoring.levelStep(correct: 9, total: 10) == 0.4)
        #expect(QuizScoring.levelStep(correct: 7, total: 10) == 0.2)
        #expect(QuizScoring.levelStep(correct: 5, total: 10) == 0)
        #expect(QuizScoring.levelStep(correct: 4, total: 10) == -0.3)
        #expect(QuizScoring.levelStep(correct: 10, total: 10, weight: 0.5) == 0.2)
        #expect(QuizScoring.newLevel(4.9, step: 0.4) == 5 && QuizScoring.newLevel(1.1, step: -0.3) == 1)
        #expect(QuizScoring.tier(2) == .basic && QuizScoring.tier(4.6) == .expert)
    }

    /// „Seen“ hangs on the answers: latest time per identifier, old entries without an identifier do not count.
    @Test func seenFromAnswers() throws {
        let d = try defaults()
        let c = d.container.mainContext
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        for (question, time) in [
            ("gen:esmaAnlami:e:5:1", t0), ("gen:esmaAnlami:e:5:1", t0.addingTimeInterval(60)),
            ("kur:quiz-siyer:siyer-0001:7", t0), ("", t0.addingTimeInterval(99)),
        ] {
            let s = SoruCevabi(gun: "2026-10-19", secim: 0, dogru: true, soru: question)
            s.tarih = time
            c.insert(s)
        }
        let g = d.quizSeen()
        #expect(g == ["gen:esmaAnlami:e:5:1": t0.addingTimeInterval(60), "kur:quiz-siyer:siyer-0001:7": t0])
    }

    /// Count for the quiz tiles: once per position, daily question included, Tekrar via the last answer.
    @Test func counters() throws {
        let d = try defaults()
        let time = try #require(ISO8601DateFormatter().date(from: "2026-10-19T12:00:00Z"))
        d.answerQuestion(day: "2026-10-19", selection: 0, correct: false)
        let t = d.createRound(
            day: "2026-10-19", cesit: "alistirma", seed: 1, area: "", questions: ["a", "b", "c"])
        for (i, (area, correct)) in [("kuran", true), ("kuran", false), ("siyer", true)].enumerated() {
            d.answerQuiz(
                t, index: i + 1, question: "gen:q:\(i)", area: area, selection: 0, correct: correct,
                duration: 1,
                reviewID: "gen:q:\(i)", now: time)
        }
        // the same position once more, e.g. from a second device
        d.container.mainContext.insert(
            SoruCevabi(
                gun: "2026-10-19", secim: 1, dogru: true, soru: "gen:q:1", tur: t.kimlik, sira: 2,
                alan: "kuran"))

        #expect(
            d.quizAreaCounters() == [
                "kuran": QuizCounter(correct: 1, wrong: 1), "siyer": QuizCounter(correct: 1),
            ])
        #expect(d.quizDayCounters(ab: "2026-10-19") == ["2026-10-19": QuizCounter(correct: 2, wrong: 2)])
        #expect(d.quizDayCounters(ab: "2026-10-20").isEmpty)
        let later = time.addingTimeInterval(86_400 * 30)
        #expect(d.dueReviewCounts(now: later) == ["kuran": 1])
        #expect(QuizCounter(correct: 3, wrong: 1).ratio == 0.75 && QuizCounter().ratio == 0)
    }

    @Test func duello() throws {
        let d = try defaults()
        let x = d.saveDuel(code: "K7R4MQ", area: "", length: 10, kind: "t")
        d.updateDuel(x, opponentName: "Opponent", opponentCorrect: 8)
        #expect(d.duels().first?.karsiDogru == 8)
    }
}
