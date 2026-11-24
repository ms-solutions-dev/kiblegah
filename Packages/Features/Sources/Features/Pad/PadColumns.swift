import ContentPacks
import Core
import DesignSystem
import PrayerTimes
import SwiftUI
import UserData

/// How an area spreads over columns (board G06). The screens stay the ones of the iPhone: they only push
/// `Goal`s, and each column decides by this rule where a goal goes.
struct PadColumnPlan {
    /// With a middle list (categories | list | detail), otherwise list | detail.
    let threeColumns: Bool
    let root: AnyView
    /// A goal that belongs into the right column; everything else opens in the middle one.
    let isDetail: (Goal) -> Bool

    @MainActor static func plan(for tab: AppTab) -> PadColumnPlan? {
        switch tab {
        case .hadith:
            return PadColumnPlan(threeColumns: true, root: AnyView(HadithScreen())) { g in
                if case .hadithDetail = g { return true }
                return false
            }
        case .duas:
            return PadColumnPlan(threeColumns: true, root: AnyView(DuasScreen())) { g in
                switch g {
                case .dua: return true
                case .plugin(let p): return p.id == "sunnet-dua"
                default: return false
                }
            }
        case .divineNames:
            return PadColumnPlan(threeColumns: false, root: AnyView(DivineNamesScreen())) { _ in true }
        default:
            return nil
        }
    }
}

extension EnvironmentValues {
    /// The goal shown next to a list, so that its row can look selected.
    @Entry var padOpenGoal: Goal? = nil
}

extension View {
    /// A row with its goal: tinted while that goal is open in the next column.
    func padRowSelection(_ goal: Goal) -> some View { modifier(PadRowSelection(goal: goal)) }
}

private struct PadRowSelection: ViewModifier {
    @Environment(\.padOpenGoal) private var open
    @Environment(\.theme) private var theme
    let goal: Goal

    func body(content: Content) -> some View {
        if open == goal {
            content.listRowBackground(theme.colors.accent.opacity(0.14))
        } else {
            content
        }
    }
}

/// The columns of an area. Narrower than the columns need, it is the usual stack.
struct PadColumnArea: View {
    @Environment(Router.self) private var direction
    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme
    let tab: AppTab
    let plan: PadColumnPlan

    /// Middle column: its first goal and what was pushed on top of it.
    @State private var middle: Goal?
    @State private var middlePath: [Goal] = []
    /// Right column.
    @State private var detail: Goal?
    @State private var detailPath: [Goal] = []
    @State private var width: CGFloat = 0

    private var wide: Bool { width >= 860 }
    /// Three columns only with room for real titles; with an open sidebar the middle list opens on the right.
    private var threeColumns: Bool { plan.threeColumns && width >= 1000 }

    /// The columns take the surface as their ground, as cards on the page.
    private var columnTheme: Theme {
        Theme(colors: theme.colors.onSurface, largeAndSimple: theme.largeAndSimple, force: theme.force)
    }

    var body: some View {
        Group {
            if wide {
                HStack(spacing: 14) {
                    leftColumn.frame(width: threeColumns ? max(236, width * 0.24) : max(320, width * 0.36))
                    if threeColumns { middleColumn.frame(width: max(260, width * 0.3)) }
                    rightColumn
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .environment(\.theme, columnTheme)
                .pageBackground()
            } else {
                stack
            }
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        .onChange(of: direction.path[tab] ?? [], initial: true) { _, goals in
            // Links from outside (widgets, search): into the columns instead of a stack.
            guard wide || width == 0, !goals.isEmpty else { return }
            for g in goals { route(g) }
            direction.path[tab] = []
        }
    }

    /// The stack for narrow widths, as on the iPhone.
    private var stack: some View {
        NavigationStack(path: Binding(get: { direction.path[tab] ?? [] }, set: { direction.path[tab] = $0 }))
        {
            plan.root.navigationDestination(for: Goal.self) { GoalScreen(goal: $0) }
        }
    }

    private func card<V: View>(_ v: V) -> some View {
        v
            .background(theme.colors.surface, in: .rect(cornerRadius: 28))
            .clipShape(.rect(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(theme.colors.line))
            .padShadow(theme)
    }

    /// The first list. Its stack stays empty: whatever it would push opens next to it.
    private var leftColumn: some View {
        card(
            NavigationStack(
                path: Binding(
                    get: { [Goal]() },
                    set: { goals in if let g = goals.last { route(g) } })
            ) {
                plan.root
                    .toolbarTitleDisplayMode(.inline)
                    .navigationDestination(for: Goal.self) { _ in EmptyView() }
            }
            .environment(\.padOpenGoal, threeColumns ? middle : detail)
        )
    }

    private var middleColumn: some View {
        card(
            NavigationStack(
                path: Binding(
                    get: { middlePath },
                    set: { goals in
                        if let g = goals.last, goals.count > middlePath.count, plan.isDetail(g) {
                            open(g)
                        } else {
                            middlePath = goals
                        }
                    })
            ) {
                Group {
                    if let middle {
                        GoalScreen(goal: middle)
                    } else {
                        placeholder("ipad.liste.kategorie")
                    }
                }
                .toolbarTitleDisplayMode(.inline)
                .navigationDestination(for: Goal.self) {
                    GoalScreen(goal: $0).toolbarTitleDisplayMode(.inline)
                }
            }
            .id(middle)
            .environment(\.padOpenGoal, detail)
        )
    }

    private var rightColumn: some View {
        card(
            NavigationStack(
                path: Binding(
                    get: { detailPath },
                    set: { goals in
                        if case .verse(let k)? = goals.last, goals.count > detailPath.count {
                            // A verse opens in the Quran area, not in this narrow column.
                            direction.open(.verse(k), tabs: settings.tabs)
                        } else {
                            detailPath = goals
                        }
                    })
            ) {
                Group {
                    if let detail {
                        GoalScreen(goal: detail)
                    } else {
                        placeholder("ipad.liste.eintrag")
                    }
                }
                .toolbarTitleDisplayMode(.inline)
                .navigationDestination(for: Goal.self) {
                    GoalScreen(goal: $0).toolbarTitleDisplayMode(.inline)
                }
            }
            .id(detail)
            .transition(.scale(scale: 0.97).combined(with: .offset(y: 10)).combined(with: .opacity))
        )
        .frame(maxWidth: .infinity)
    }

    private func placeholder(_ key: String.LocalizationValue) -> some View {
        Text(verbatim: localized(key)).typography(.secondary).foregroundStyle(theme.colors.text2)
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.colors.surface)
    }

    private func route(_ g: Goal) {
        if plan.isDetail(g) || !threeColumns {
            open(g)
        } else {
            withAnimation(.easeOut(duration: 0.25)) {
                middle = g
                middlePath = []
                detail = nil
                detailPath = []
            }
        }
    }

    private func open(_ g: Goal) {
        withAnimation(.timingCurve(0.3, 0.9, 0.3, 1, duration: 0.4)) {
            detail = g
            detailPath = []
        }
    }
}

/// Entdecken on the iPad (board G05): search and „Sor“, tiles for everything that has no row of its own, then
/// verse, question and continue reading as cards.
struct PadDiscoverScreen: View {
    @Environment(\.theme) private var theme
    @Environment(Router.self) private var direction
    @Environment(AppSettings.self) private var settings
    @Environment(UserStore.self) private var store
    @Environment(\.contentProvider) private var contentProvider
    @Environment(\.plugins) private var plugins
    @Environment(\.padWindow) private var window

    private var tall: Bool { window.height > window.width }

    var body: some View {
        let _ = store.version
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(app: "sekme.kesfet").typography(.display(size: 34)).padding(.top, 4)
                HStack(spacing: 10) {
                    Button {
                        direction.open(.search, tabs: settings.tabs)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass").accessibilityHidden(true)
                            Text(app: "ipad.entdecken.suche").lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .typography(.body)
                        .foregroundStyle(theme.colors.text2)
                        .padding(.horizontal, 22)
                        .frame(minHeight: 52)
                        .background(theme.colors.surface, in: .capsule)
                        .overlay(Capsule().strokeBorder(theme.colors.line))
                        .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(localized("arama.baslik"))
                    SlotView(.discoverAsk)
                }
                let extras = plugins.discoverTiles()
                // In portrait the areas hidden from the top bar are reachable here too.
                let count = 3 + (Backlog.prayerGuide ? 1 : 0) + extras.count + 1 + (tall ? 3 : 0)
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: 14),
                        count: tall || count % 3 == 1 ? 2 : 3),
                    spacing: 14
                ) {
                    tile(
                        .calendar, "takvim.baslik", sub: localized("kesfet.takvim.alt"), icon: "calendar",
                        delay: 0)
                    if Backlog.prayerGuide {
                        tile(
                            .guide, "rehber.baslik", sub: localized("kesfet.rehber.alt"),
                            icon: "figure.stand", delay: 0.07)
                    }
                    tile(
                        .collections, "koleksiyon.ekran", sub: localized("ipad.entdecken.sammlungen"),
                        icon: "folder", delay: 0.14)
                    tile(
                        .divineName, "sekme.esma", sub: localized("kesfet.esma.alt"),
                        icon: AppTab.divineNames.icon, delay: 0.21)
                    tile(
                        .dhikr, "sekme.zikir",
                        sub: localized("kesfet.zikir.alt \(store.dhikrTotal(days: 1))"),
                        icon: AppTab.dhikr.icon, delay: 0.28)
                    if tall {
                        areaTile(.duas, "sekme.dualar", sub: localized("kesfet.dualar.alt"), delay: 0.3)
                        areaTile(.hadith, "sekme.hadis", sub: localized("kesfet.hadis.alt"), delay: 0.32)
                        areaTile(.quiz, "sekme.quiz", sub: localized("kesfet.quiz.alt"), delay: 0.34)
                    }
                    ForEach(extras) { entry in
                        tileLink(
                            goal: entry.goal, title: localized(key: entry.titleKey),
                            sub: localized(key: entry.subKey),
                            icon: entry.icon, delay: 0.35)
                    }
                }
                TimelineView(.everyMinute) { context in
                    cards(Day(context.date, timeZoneIdentifier: .current))
                }
                Text(app: "kesfet.bugun").typography(.label(size: 13)).textCase(.uppercase).tracking(1.1)
                    .foregroundStyle(theme.colors.label)
                    .padding(.top, 4)
                DiscoverTodayCards()
                    .padding(.horizontal, -16)
            }
            .padding(.horizontal, tall ? 28 : 16)
            .padding(.bottom, 20)
        }
        .pageBackground()
        .hideTopBar()
    }

    /// Into an area of its own: changes the sidebar selection instead of stacking it here.
    private func areaTile(_ tab: AppTab, _ title: LocalizedStringKey, sub: String, delay: Double) -> some View
    {
        Button {
            direction.selected = tab
        } label: {
            tileBody(Text(app: title), sub: sub, icon: tab.icon)
        }
        .buttonStyle(.plain)
        .padEnter(delay: delay)
    }

    private func tile(
        _ goal: Goal, _ title: LocalizedStringKey, sub: String, icon: String, delay: Double
    ) -> some View {
        NavigationLink(value: goal) {
            tileBody(Text(app: title), sub: sub, icon: icon)
        }
        .buttonStyle(.plain)
        .padEnter(delay: delay)
    }

    private func tileLink(goal: Goal, title: String, sub: String, icon: String, delay: Double) -> some View {
        NavigationLink(value: goal) {
            tileBody(Text(verbatim: title), sub: sub, icon: icon)
        }
        .buttonStyle(.plain)
        .padEnter(delay: delay)
    }

    private func tileBody(_ title: Text, sub: String, icon: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 21)).foregroundStyle(theme.colors.accent)
                .frame(width: 52, height: 52)
                .background(theme.colors.accent.opacity(0.14), in: .rect(cornerRadius: 16))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                title.typography(.label(size: 18)).foregroundStyle(theme.colors.text).lineLimit(2)
                Text(verbatim: sub).typography(.footnote).foregroundStyle(theme.colors.text2).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
        .padCard(theme, radius: 22)
        .contentShape(.rect)
    }

    private func cards(_ day: Day) -> some View {
        let last = (store.lastPosition(khatm: settings.activeKhatm) ?? store.lastPosition()).flatMap {
            ContentKey(text: $0)
        }
        return Group {
            if tall {
                VStack(spacing: 14) {
                    cardBody("ipad.heute.vers") { PadVerseOfTheDay(day: day, tall: true) }
                    cardBody("ipad.heute.frage") {
                        QuestionOfTheDayCard(day: day, optionColumns: 2, showsTitle: false)
                    }
                    cardBody("kuran.kaldigin_yer") { ContinueCard(lastPosition: last) }
                }
            } else {
                HStack(alignment: .top, spacing: 14) {
                    cardBody("ipad.heute.vers") { PadVerseOfTheDay(day: day, tall: false) }
                        .frame(maxWidth: .infinity)
                        .padEnter()
                    cardBody("ipad.heute.frage") {
                        QuestionOfTheDayCard(day: day, optionColumns: 1, showsTitle: false)
                    }
                    .frame(width: 280)
                    .padEnter(delay: 0.08)
                    cardBody("kuran.kaldigin_yer") { ContinueCard(lastPosition: last, showsTitle: false) }
                        .frame(width: 280)
                        .padEnter(delay: 0.16)
                }
            }
        }
    }

    private func cardBody<V: View>(
        _ title: String.LocalizationValue, @ViewBuilder _ content: () -> V
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: localized(title)).typography(.label(size: 13)).textCase(.uppercase).tracking(1.1)
                .foregroundStyle(theme.colors.label)
            content()
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padCard(theme)
    }
}
