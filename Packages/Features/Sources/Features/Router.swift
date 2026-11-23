import Core
import Foundation
import Observation

/// A destination within a tab that can be jumped to.
public enum Goal: Hashable, Sendable {
    case verse(ContentKey)
    case dua(String)
    case dhikr
    case divineName
    case settings
    case notifications
    case allPrayerTimes
    case location
    case downloaded
    case duaList(String)
    case divineNameDetail(Int)
    case dhikrDivineName(Int)
    case guide
    case guideStep(String)
    case calendar
    case search
    case hadith
    case hadithCategory(Int, String)
    case hadithDetail(Int)
    case collections
    case readingGoals
    case talks
    /// Storage management (Ayarlar).
    case storage
    case memorization
    case mushaf(Int)
    case memorizationPractice(String)
    case talkChannels
    /// Saved videos as a grid and starting from one of them in the player
    /// (`kiblegah://sohbet/savedItems`, `…/savedItems/<video>`).
    case talkSaved
    case talkSubscribed(String)
    /// Shared channel pack as a link (`kiblegah://sohbet/pack?…`).
    case talkPack(String)
    /// Search with a preset query (`kiblegah://search?q=…`).
    case searchQuery(String)
    case collection(String)
    /// The home screen of an area that is currently not in the tab bar.
    case section(AppTab)
    /// Quiz area (V1) and a round in it: `day`, `repetition`, `duello:<code>`,
    /// `practice:<area|karisik>:<length>:<stufe>` (`kiblegah://quiz`, `/quiz/day`, `/quiz/duello/<code>`).
    case quiz
    case quizGame(String)
    case quizPractice
    case quizDuello
    case quizHistory
    case quizSettings
    /// A destination that a plugin provides (`Plugin/screen(_:)`, `Plugin/route(_:)`).
    case plugin(PluginGoal)
}

/// A destination only a plugin knows: an identifier, its arguments and the tab it belongs to.
public struct PluginGoal: Hashable, Sendable {
    public let id: String
    public let arguments: [String]
    public let area: AppTab

    public init(_ id: String, _ arguments: [String] = [], area: AppTab = .discover) {
        self.id = id
        self.arguments = arguments
        self.area = area
    }
}

/// Where the app currently is: selected tab and a separate stack per tab.
///
/// Each tab has its own stack; "Zurück" therefore always stays in the caller's tab and
/// never leads into another one.
@MainActor @Observable public final class Router {
    public var selected: AppTab = .prayerTimes
    public var path: [AppTab: [Goal]] = [:]
    /// Which areas the app target ships with; destinations of other areas land in Keşfet.
    @ObservationIgnored private let tabFilter: @MainActor (AppTab) -> Bool
    /// Links the plugins understand (path components of `kiblegah://…`).
    @ObservationIgnored private let routes: @MainActor ([String]) -> Goal?

    public init(
        tabFilter: @escaping @MainActor (AppTab) -> Bool = { _ in true },
        routes: @escaping @MainActor ([String]) -> Goal? = { _ in nil }
    ) {
        self.tabFilter = tabFilter
        self.routes = routes
    }

    /// The saved tabs, as this app target shows them.
    private func visible(_ tabs: [AppTab]) -> [AppTab] {
        AppTab.normalized(tabs, allowed: tabFilter)
    }

    /// Opens a destination. If its area is not a tab, it lands in the stack of Keşfet.
    public func open(_ goal: Goal, tabs: [AppTab]) {
        let tabs = visible(tabs)
        let area = Router.area(goal)
        let tab = tabs.contains(area) ? area : .discover
        selected = tab
        if let targetStack = Router.path(goal, tab: tab) {
            path[tab] = targetStack
        }
    }

    /// Parses `kiblegah://…`. Unknown input leads to the home page, never to nothing.
    public func open(url: URL, tabs: [AppTab]) {
        guard url.scheme == "kiblegah" else { return }
        let tabs = visible(tabs)
        let parts = [url.host()].compactMap { $0 } + url.pathComponents.filter { $0 != "/" }
        switch parts.first {
        case "vakit", "bugun": selected = .prayerTimes; path[.prayerTimes] = []
        case "kible": sec(.qibla, tabs: tabs)
        case "kuran":
            if parts.dropFirst().first == "hedefler" {
                open(.readingGoals, tabs: tabs)
            } else if parts.dropFirst().first == "sayfa",
                let n = parts.dropFirst(2).first.flatMap({ Int($0) })
            {
                open(.mushaf(min(604, max(1, n))), tabs: tabs)
            } else if parts.dropFirst().first == "ezber" {
                if let k = parts.dropFirst(2).first {
                    open(.memorizationPractice(k), tabs: tabs)
                } else {
                    open(.memorization, tabs: tabs)
                }
            } else if let text = parts.dropFirst().first,
                let a = ContentKey(text: "a:" + text) ?? ContentKey(text: text)
            {
                open(.verse(a), tabs: tabs)
            } else {
                sec(.quran, tabs: tabs)
            }
        case "dua":
            if let id = parts.dropFirst().first {
                open(.dua(id), tabs: tabs)
            } else {
                sec(.duas, tabs: tabs)
            }
        case "zikir": open(.dhikr, tabs: tabs)
        case "esma":
            // kiblegah://esma/83 opens the page of a Name.
            if let n = parts.dropFirst().first.flatMap({ Int($0) }), (1...99).contains(n) {
                open(.divineNameDetail(n), tabs: tabs)
            } else {
                open(.divineName, tabs: tabs)
            }
        case "hadis":
            if let n = parts.dropFirst().first.flatMap({ Int($0) }) {
                open(.hadithDetail(n), tabs: tabs)
            } else {
                open(.hadith, tabs: tabs)
            }
        case "arama":
            let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first {
                $0.name == "q"
            }?.value
            open(q.map { .searchQuery($0) } ?? .search, tabs: tabs)
        case "sohbet":
            if parts.dropFirst().first == "paket" {
                open(.talkPack(url.absoluteString), tabs: tabs)
            } else if parts.dropFirst().first == "kaydedilenler" {
                if parts.count > 2 {
                    open(.talkSubscribed(parts[2]), tabs: tabs)
                } else {
                    open(.talkSaved, tabs: tabs)
                }
            } else {
                open(.talks, tabs: tabs)
            }
        case "quiz":
            let p = Array(parts.dropFirst())
            if p.first == "gun" {
                open(.quizGame("gun"), tabs: tabs)
            } else if p.count == 2, p[0] == "alistirma" {
                open(.quizGame("alistirma:\(p[1]):10:0"), tabs: tabs)
            } else if p.count == 2, p[0] == "duello" {
                open(.quizGame("duello:\(p[1])"), tabs: tabs)
            } else if p.first == "gecmis" {
                open(.quizHistory, tabs: tabs)
            } else if p.first == "duello" {
                open(.quizDuello, tabs: tabs)
            } else if let g = routes(parts) {
                open(g, tabs: tabs)
            } else {
                open(.quiz, tabs: tabs)
            }
        case "kesfet": selected = .discover; path[.discover] = []
        case "takvim": open(.calendar, tabs: tabs)
        case "rehber":
            if Backlog.prayerGuide {
                open(.guide, tabs: tabs)
            } else {
                selected = .discover
                path[.discover] = []
            }
        case "ayarlar": open(.settings, tabs: tabs)
        case "koleksiyonlar": open(.collections, tabs: tabs)
        case "bildirimler": open(.notifications, tabs: tabs)
        default:
            if let g = routes(parts) { open(g, tabs: tabs) } else { selected = .prayerTimes }
        }
    }

    private func sec(_ tab: AppTab, tabs: [AppTab]) {
        selected = tabs.contains(tab) ? tab : .discover
        if !tabs.contains(tab) {
            switch tab {
            case .qibla, .quran, .duas: path[.discover] = [.section(tab)]
            default: break
            }
        }
    }

    static func area(_ goal: Goal) -> AppTab {
        switch goal {
        case .verse: .quran
        case .dua: .duas
        case .dhikr: .dhikr
        case .divineName: .divineNames
        case .settings, .storage: .discover
        case .downloaded, .readingGoals, .memorization, .memorizationPractice, .mushaf: .quran
        case .duaList: .duas
        case .divineNameDetail: .divineNames
        case .dhikrDivineName: .dhikr
        case .guide, .guideStep, .calendar, .search: .discover
        case .hadith, .hadithCategory, .hadithDetail: .hadith
        case .collections, .collection, .searchQuery, .section: .discover
        case .plugin(let p): p.area
        case .quiz, .quizGame, .quizPractice, .quizDuello, .quizHistory: .quiz
        case .quizSettings: .discover
        case .talks, .talkChannels, .talkPack, .talkSaved, .talkSubscribed: .talks
        case .notifications, .allPrayerTimes, .location: .prayerTimes
        }
    }

    /// The stack that belongs to a destination. `nil` means: the tab itself is the destination.
    static func path(_ goal: Goal, tab: AppTab) -> [Goal]? {
        switch (goal, tab) {
        case (.dhikr, .dhikr), (.divineName, .divineNames), (.hadith, .hadith), (.talks, .talks),
            (.quiz, .quiz):
            []
        // A round from Keşfet or a link: the quiz area underneath, so that "Zurück" lands there.
        case (.quizGame, .discover), (.quizDuello, .discover), (.quizHistory, .discover): [.quiz, goal]
        default: [goal]
        }
    }
}
