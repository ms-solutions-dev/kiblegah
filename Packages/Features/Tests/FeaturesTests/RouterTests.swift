import Core
import Foundation
import Testing

@testable import Features

@MainActor @Suite struct RouterTests {
    let tabs = AppTab.standard

    @Test func quranVerseLink() throws {
        let y = Router()
        y.open(url: try #require(URL(string: "kiblegah://kuran/2:255")), tabs: tabs)
        #expect(y.selected == .quran)
        #expect(y.path[.quran] == [.verse(.verse(surah: 2, verse: 255))])
    }

    /// The tab has been called "Bugün" since 01 C; widget and notifications still open it via `vakit`.
    @Test func prayerLinkOpensTodayTab() throws {
        for address in ["kiblegah://vakit", "kiblegah://bugun"] {
            let y = Router()
            y.selected = .quran
            y.path[.prayerTimes] = [.allPrayerTimes]
            y.open(url: try #require(URL(string: address)), tabs: tabs)
            #expect(y.selected == .prayerTimes)
            #expect(y.path[.prayerTimes] == [])
        }
    }

    @Test func dhikrGoesToDiscoverWhenNotATab() throws {
        let y = Router()
        y.open(url: try #require(URL(string: "kiblegah://zikir")), tabs: tabs)
        #expect(y.selected == .discover)
        #expect(y.path[.discover] == [.dhikr])
    }

    @Test func qiblaOpensInDiscoverWhenNotATab() throws {
        let y = Router()
        y.open(
            url: try #require(URL(string: "kiblegah://kible")),
            tabs: [.prayerTimes, .quran, .duas, .dhikr])
        #expect(y.selected == .discover)
        #expect(y.path[.discover] == [.section(.qibla)])
    }

    @Test func discoverCalendarGuide() throws {
        let y = Router()
        y.open(url: try #require(URL(string: "kiblegah://takvim")), tabs: tabs)
        #expect(y.selected == .discover && y.path[.discover] == [.calendar])
        y.open(url: try #require(URL(string: "kiblegah://rehber")), tabs: tabs)
        if Backlog.prayerGuide {
            #expect(y.selected == .discover && y.path[.discover] == [.guide])
        } else {
            #expect(y.selected == .discover && y.path[.discover] == [])
        }
        y.open(url: try #require(URL(string: "kiblegah://takvim")), tabs: tabs)
        #expect(y.path[.discover] == [.calendar])
        y.open(url: try #require(URL(string: "kiblegah://kesfet")), tabs: tabs)
        #expect(y.selected == .discover && y.path[.discover] == [])
    }

    @Test func dhikrOwnTabWhenTab() throws {
        let y = Router()
        y.open(
            url: try #require(URL(string: "kiblegah://zikir")),
            tabs: [.dhikr, .prayerTimes, .qibla, .quran])
        #expect(y.selected == .dhikr)
        #expect(y.path[.dhikr] == [])
    }

    @Test func unknownPrayerTimeFallsBack() throws {
        let y = Router()
        y.selected = .qibla
        y.open(url: try #require(URL(string: "kiblegah://xyz")), tabs: tabs)
        #expect(y.selected == .prayerTimes)
    }

    @Test func qibla() throws {
        let y = Router()
        y.open(url: try #require(URL(string: "kiblegah://kible")), tabs: tabs)
        #expect(y.selected == .qibla)
    }
}

@MainActor @Suite struct QuizRouterTests {
    /// Quiz is not a tab by default: links land in Keşfet, the round above the quiz area.
    @Test func quizLinks() throws {
        let y = Router()
        y.open(url: try #require(URL(string: "kiblegah://quiz")), tabs: AppTab.standard)
        #expect(y.selected == .discover && y.path[.discover] == [.quiz])
        y.open(url: try #require(URL(string: "kiblegah://quiz/gun")), tabs: AppTab.standard)
        #expect(y.path[.discover] == [.quiz, .quizGame("gun")])
        y.open(url: try #require(URL(string: "kiblegah://quiz/duello/K7R4MQ")), tabs: AppTab.standard)
        #expect(y.path[.discover] == [.quiz, .quizGame("duello:K7R4MQ")])
        let t = Router()
        t.open(
            url: try #require(URL(string: "kiblegah://quiz/gun")),
            tabs: [.prayerTimes, .quran, .quiz, .qibla])
        #expect(t.selected == .quiz && t.path[.quiz] == [.quizGame("gun")])
        t.open(
            url: try #require(URL(string: "kiblegah://quiz")),
            tabs: [.prayerTimes, .quran, .quiz, .qibla])
        #expect(t.selected == .quiz && t.path[.quiz] == [])
    }

    @Test func requestText() {
        #expect(QuizSession.Request("gun") == .day)
        #expect(QuizSession.Request("duello:K7R4MQ") == .duello("K7R4MQ"))
        #expect(
            QuizSession.Request(QuizSession.Request.practiceText(.hadith, length: 15, tier: 3))
                == .practice(.hadith, 15, 3))
        // Banks are areas like the others; "karisik" stays without an area.
        #expect(QuizSession.Request("alistirma:siyer:10:0") == .practice(.init(bank: "siyer"), 10, 0))
        #expect(QuizSession.Request("alistirma:karisik:10:0") == .practice(nil, 10, 0))
        #expect(
            QuizSession.Request(QuizSession.Request.practiceText(nil, length: 10, tier: 0))
                == .practice(nil, 10, 0))
        #expect(QuizSession.Request("x") == nil)
    }

    /// Store edition without Sohbet: `kiblegah://sohbet` does not select a tab that does not exist.
    @Test func talksWithoutPluginNoTab() throws {
        let y = Router(tabFilter: { $0 != .talks })
        y.open(
            url: try #require(URL(string: "kiblegah://sohbet")),
            tabs: [.prayerTimes, .qibla, .quran, .talks])
        #expect(y.selected == .discover)
    }
}

/// Links a plugin understands reach it through `routes`; without one they fall back to Bugün.
@MainActor @Suite struct PluginRouteTests {
    @Test func pluginRoutes() throws {
        let goal = Goal.plugin(PluginGoal("ornek", ["1"], area: .duas))
        let y = Router(routes: { $0 == ["ornek", "1"] ? goal : nil })
        y.open(url: try #require(URL(string: "kiblegah://ornek/1")), tabs: [.prayerTimes, .quran, .duas])
        #expect(y.selected == .duas && y.path[.duas] == [goal])
        let z = Router()
        z.selected = .quran
        z.open(url: try #require(URL(string: "kiblegah://ornek/1")), tabs: AppTab.standard)
        #expect(z.selected == .prayerTimes)
    }
}
