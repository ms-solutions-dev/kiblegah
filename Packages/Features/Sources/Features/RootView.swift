import ContentPacks
import Core
import DesignSystem
import Quran
import SwiftUI
import UserData
import WidgetBridge

#if os(iOS)
    import UIKit
#endif

/// The shell: native tab bar with the four chosen areas and Keşfet.
public struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var direction
    @Environment(UserStore.self) private var store
    @Environment(\.contentProvider) private var contentProvider
    @Environment(\.scenePhase) private var phase
    @Environment(RecitationPlayer.self) private var player
    @Environment(\.plugins) private var plugins

    public init() {}

    public var body: some View {
        @Bindable var direction = direction
        Group {
            if PadLayout.isPad {
                #if DEBUG
                    PadShell().modifier(PadNarrowForScreenshot())
                #else
                    PadShell()
                #endif
            } else {
                TabView(selection: $direction.selected) {
                    // Sohbet only if the edition includes it (the saved order remains untouched).
                    ForEach(plugins.tabs(settings.tabs) + [.discover]) { tab in
                        Tab(value: tab) {
                            TabRoot(tab: tab)
                        } label: {
                            Label {
                                Text(app: tab.titleKey)
                            } icon: {
                                Image(systemName: tab.icon)
                            }
                        }
                    }
                }
            }
        }
        // Quran widgets (/): when the app comes and goes, not after every verse.
        // Qibla control (lock screen, Control Center, Action button): straight to Qibla.
        .onChange(of: phase, initial: true) { _, e in
            #if os(iOS)
                if e == .active, let url = KibleAcNiyeti.pending() {
                    direction.open(url: url, tabs: settings.tabs)
                }
            #endif
        }
        .onChange(of: phase, initial: true) { _, e in
            if e != .inactive {
                QuranWidgetWriter.save(store: store, settings: settings, contentProvider: contentProvider)
            }
            if e == .background { ListenWidgetWriter.save(player, contentProvider: contentProvider) }
        }
        // „Kur'an dinle“: on start, pause and surah change, not per verse (reload budget).
        .onChange(of: player.isPlaying) { ListenWidgetWriter.save(player, contentProvider: contentProvider) }
        .onChange(of: player.current?.surah) {
            ListenWidgetWriter.save(player, contentProvider: contentProvider)
        }
        #if os(iOS)
            .fullScreenCover(isPresented: Binding(get: { !settings.onboardingDone }, set: { _ in })) {
                OnboardingScreen()
            }
        #else
            .sheet(isPresented: Binding(get: { !settings.onboardingDone }, set: { _ in })) {
                OnboardingScreen()
            }
        #endif
    }
}

/// One tab with its own navigation stack.
struct TabRoot: View {
    @Environment(Router.self) private var direction
    let tab: AppTab

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var columnPlan: PadColumnPlan? {
        PadLayout.isPad && sizeClass == .regular ? PadColumnPlan.plan(for: tab) : nil
    }

    var body: some View {
        @Bindable var direction = direction
        Group {
            if let columnPlan {
                PadColumnArea(tab: tab, plan: columnPlan)
            } else {
                NavigationStack(
                    path: Binding(get: { direction.path[tab] ?? [] }, set: { direction.path[tab] = $0 })
                ) {
                    TabScreen(tab: tab)
                        .padPlayerInset(pageOwnsPlayer: tab == .quran)
                        .navigationDestination(for: Goal.self) { goal in
                            GoalScreen(goal: goal)
                                .padPlayerInset(pageOwnsPlayer: goal.showsReader)
                        }
                }
            }
        }
        .modifier(PadColumnPlayer(active: columnPlan != nil))
    }
}

/// The home screen of an area.
struct TabScreen: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let tab: AppTab

    var body: some View {
        switch tab {
        case .discover:
            if PadLayout.isPad, sizeClass == .regular { PadDiscoverScreen() } else { DiscoverScreen() }
        case .prayerTimes: TodayScreen()
        case .qibla: QiblaScreen()
        case .quran:
            if PadLayout.isPad, sizeClass == .regular { PadQuranScreen() } else { QuranScreen() }
        case .duas: DuasScreen()
        case .dhikr: DhikrScreen()
        case .divineNames: DivineNamesScreen()
        case .hadith: HadithScreen()
        case .talks: PluginScreen(goal: .talks)
        case .quiz: QuizScreen()
        }
    }
}

/// A destination within a stack.
public struct GoalScreen: View {
    let goal: Goal

    public init(goal: Goal) { self.goal = goal }

    public var body: some View {
        switch goal {
        case .settings: SettingsScreen()
        case .dhikr: DhikrScreen()
        case .divineName: DivineNamesScreen()
        case .hadith: HadithScreen()
        case .hadithCategory(let k, let name): HadithScreen(parent: k, title: name)
        case .hadithDetail(let n): HadithDetailScreen(identifier: n)
        case .collections: CollectionsScreen().pluginWrapper()
        case .readingGoals: ReadingGoalsScreen()
        // Provided by plugins of the app target; without one an empty state.
        case .talks, .talkChannels, .talkSaved, .talkSubscribed, .talkPack, .plugin:
            PluginScreen(goal: goal)
        case .storage: StorageScreen()
        case .memorization: MemorizationScreen()
        case .mushaf(let n): MushafGoal(page: n)
        case .memorizationPractice(let a): MemorizationPracticeScreen(key: a)
        case .collection(let k): CollectionDetailScreen(identifier: k)
        case .divineNameDetail(let n): DivineNameDetailScreen(number: n)
        case .dhikrDivineName(let n): DhikrScreen(divineName: n)
        case .guide: GuideScreen()
        case .guideStep(let k): GuideStepScreen(sectionID: k)
        case .calendar: CalendarScreen()
        case .search: SearchScreen()
        case .searchQuery(let q): SearchScreen(start: q)
        case .dua(let slug): DuaDetailScreen(slug: slug)
        case .verse(let a): QuranGoal(key: a)
        case .notifications: NotificationsScreen()
        case .allPrayerTimes: AllPrayerTimesScreen()
        case .location: LocationPickerScreen()
        case .downloaded: DownloadsScreen()
        case .duaList(let k): DuaListScreen(category: k)
        case .section(let s): TabScreen(tab: s)
        case .quiz: QuizScreen()
        case .quizGame(let request): QuizGameScreen(request: request)
        case .quizPractice: QuizPracticeScreen()
        case .quizDuello: QuizDuelScreen()
        case .quizHistory: QuizHistoryScreen()
        case .quizSettings: QuizSettingsScreen()
        }
    }
}

extension AppTab {
    var titleKey: LocalizedStringKey {
        switch self {
        case .prayerTimes: "sekme.vakit"
        case .qibla: "sekme.kible"
        case .quran: "sekme.kuran"
        case .duas: "sekme.dualar"
        case .dhikr: "sekme.zikir"
        case .divineNames: "sekme.esma"
        case .hadith: "sekme.hadis"
        case .talks: "sekme.sohbet"
        case .quiz: "sekme.quiz"
        case .discover: "sekme.kesfet"
        }
    }

    var icon: String {
        switch self {
        case .prayerTimes: "sun.horizon"
        case .qibla: "location.north.circle"
        case .quran: "book"
        case .duas: "hands.and.sparkles"
        case .dhikr: "circle.dotted.circle"
        case .divineNames: "sparkles"
        case .hadith: "text.book.closed"
        case .talks: "play.square.stack"
        case .quiz: "questionmark.bubble"
        case .discover: "square.grid.2x2"
        }
    }
}

/// A page of the Mushaf as a destination; on the iPad the full screen book above the reader.
struct MushafGoal: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.contentProvider) private var contentProvider
    let page: Int

    var body: some View {
        if PadLayout.isPad, sizeClass == .regular, let p = contentProvider?.page(page),
            let k = contentProvider?.key(index: p.firstIndex)
        {
            PadQuranScreen(start: k, opensBook: true)
        } else {
            MushafScreen(start: page)
        }
    }
}

/// A Quran destination: the reader, or with „Mushaf'ta aç“ directly the Mushaf page on which the
/// destination begins. Without a page (content missing) it stays with the reader.
struct QuranGoal: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(AppSettings.self) private var settings
    @Environment(\.contentProvider) private var contentProvider
    let key: ContentKey

    var body: some View {
        if PadLayout.isPad, sizeClass == .regular {
            PadQuranScreen(start: key, opensBook: settings.openInMushaf)
        } else if settings.openInMushaf, let contentProvider, let n = Self.page(key, contentProvider) {
            MushafScreen(start: n)
        } else {
            ReaderScreen(start: key)
        }
    }

    /// Medine-604 page (V1) of the first verse; the Mushaf converts it to its own edition.
    static func page(_ a: ContentKey, _ contentProvider: any ContentProvider) -> Int? {
        if case .juz(let n) = a {
            return contentProvider.juz(n).flatMap { contentProvider.key(index: $0.firstIndex) }.flatMap {
                contentProvider.verse($0)?.page
            }
        }
        return contentProvider.verse(firstVerse(a))?.page
    }
}

extension Goal {
    /// The Quran columns show the player themselves.
    var showsReader: Bool {
        switch self {
        case .verse, .mushaf: true
        default: false
        }
    }
}

extension View {
    /// iPad: the global player below this page, so that nothing lies under it.
    func padPlayerInset(pageOwnsPlayer: Bool) -> some View {
        modifier(PadPlayerInset(pageOwnsPlayer: pageOwnsPlayer))
    }
}

struct PadPlayerInset: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let pageOwnsPlayer: Bool

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom) {
            if PadLayout.isPad, !(pageOwnsPlayer && sizeClass == .regular) {
                PadPlayerBar()
            }
        }
    }
}

/// Around the columns of an area, which have no outer stack.
private struct PadColumnPlayer: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.safeAreaInset(edge: .bottom) { PadPlayerBar() }
        } else {
            content
        }
    }
}

#if DEBUG && os(iOS)
    /// Screenshots of a narrow window: `-ipadSchmal YES` makes the scene compact and the root 400 pt wide.
    /// A real Split View cannot be set up from the command line.
    private struct PadNarrowForScreenshot: ViewModifier {
        private let on = UserDefaults.standard.bool(forKey: "ipadSchmal")

        func body(content: Content) -> some View {
            if on {
                content
                    .environment(\.horizontalSizeClass, .compact)
                    .frame(width: 400)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                content
            }
        }
    }
#elseif DEBUG
    private struct PadNarrowForScreenshot: ViewModifier {
        func body(content: Content) -> some View { content }
    }
#endif
