import Core
import DesignSystem
import SwiftUI
import UserData

/// Keşfet as a discovery page: search and „Sor“ in one row at the top, below it
/// the Bugün carousel, then a compact list with a color field per area. No dead end;
/// Ayarlar stays as the last row. Namaz-Rehber is in the backlog (`Backlog.prayerGuide`).
struct DiscoverScreen: View {
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var size
    @Environment(AppSettings.self) private var settings
    @Environment(UserStore.self) private var store
    @Environment(Router.self) private var direction
    @Environment(\.plugins) private var plugins

    /// The tabs of this edition: what is there does not appear here again.
    private var tabs: [AppTab] { plugins.tabs(settings.tabs) }

    var body: some View {
        let _ = store.version
        List {
            Section {
                searchAndAsk
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            Section {
                DiscoverTodayCards()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } header: {
                Text(app: "kesfet.bugun")
            }
            Section {
                if !tabs.contains(.dhikr) {
                    row(
                        .dhikr, "sekme.zikir",
                        bottom: localized("kesfet.zikir.alt \(store.dhikrTotal(days: 1))"),
                        icon: AppTab.dhikr.icon, ton: .turquoise)
                }
                if !tabs.contains(.divineNames) {
                    row(
                        .divineName, "sekme.esma", bottom: localized("kesfet.esma.alt"),
                        icon: AppTab.divineNames.icon,
                        ton: .saffron)
                }
                if !tabs.contains(.hadith) {
                    row(
                        .hadith, "sekme.hadis", bottom: localized("kesfet.hadis.alt"),
                        icon: AppTab.hadith.icon,
                        ton: .sea)
                }
                if !tabs.contains(.quiz) {
                    row(
                        .quiz, "sekme.quiz", bottom: localized("kesfet.quiz.alt"), icon: AppTab.quiz.icon,
                        ton: .olive)
                }
                if Backlog.prayerGuide {
                    row(
                        .guide, "rehber.baslik", bottom: localized("kesfet.rehber.alt"), icon: "figure.stand",
                        ton: .olive)
                }
                row(
                    .calendar, "takvim.baslik", bottom: localized("kesfet.takvim.alt"), icon: "calendar",
                    ton: .rose)
                ForEach(
                    AppTab.selectable.filter {
                        !tabs.contains($0) && $0 != .dhikr && $0 != .divineNames && $0 != .hadith
                            && $0 != .talks && $0 != .quiz
                    }
                ) { tab in
                    Button {
                        direction.open(tab.goal, tabs: settings.tabs)
                    } label: {
                        label(
                            tab.titleKey, bottom: tab.discoverSubtitle, icon: tab.icon,
                            ton: tab.discoverTone)
                    }
                    .foregroundStyle(theme.colors.text)
                }
            }
            Section {
                NavigationLink(value: Goal.collections) {
                    Label {
                        Text(app: "koleksiyon.ekran")
                    } icon: {
                        IconTile("folder", tone: .neutral)
                    }
                }
                SlotView(.discoverRows)
                NavigationLink(value: Goal.settings) {
                    Label {
                        Text(app: "ayarlar.baslik")
                    } icon: {
                        IconTile("gearshape", tone: .neutral)
                    }
                }
            }
        }
        .pageBackground()
        .navigationTitle(Text(app: "sekme.kesfet"))
    }

    /// Search as a field, „Sor“ as a short button next to it; from `.xxLarge` stacked, otherwise
    /// the placeholder is cut off even before the AX sizes. „Sor“ opens
    /// the conversation history so that begun conversations stay visible; without
    /// a conversation, directly the new question, one tap to the question.
    /// Buttons instead of `NavigationLink`, because the list would otherwise put an arrow behind every capsule.
    private var searchAndAsk: some View {
        let arrangement =
            size >= .xxLarge
            ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return arrangement {
            Button {
                direction.open(.search, tabs: settings.tabs)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").accessibilityHidden(true)
                    Text(app: "kesfet.ara").lineLimit(1)
                    Spacer(minLength: 0)
                }
                .typography(.body)
                .foregroundStyle(theme.colors.text2)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(theme.colors.surface, in: .capsule)
                .overlay(Capsule().strokeBorder(theme.colors.line))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localized("arama.baslik"))
            // „Sor“.
            SlotView(.discoverAsk)
        }
    }

    private func row(
        _ h: Goal, _ title: LocalizedStringKey, bottom: String, icon: String, ton: CategoryTone
    )
        -> some View
    {
        NavigationLink(value: h) { label(title, bottom: bottom, icon: icon, ton: ton) }
    }

    private func label(
        _ title: LocalizedStringKey, bottom: String, icon: String, ton: CategoryTone
    ) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(app: title).typography(.emphasized)
                Text(verbatim: bottom).typography(.footnote).foregroundStyle(theme.colors.text2)
            }
        } icon: {
            IconTile(icon, tone: ton)
        }
    }
}

extension AppTab {
    /// The jump target that opens this area outside the tab bar.
    var goal: Goal {
        switch self {
        case .dhikr: .dhikr
        case .divineNames: .divineName
        case .hadith: .hadith
        case .talks: .talks
        case .quiz: .quiz
        case .duas, .quran, .qibla: .section(self)
        default: .allPrayerTimes
        }
    }

    /// Subtitle in Keşfet so that every row is built the same way (02 B: „Dualar“ aligned).
    var discoverSubtitle: String {
        switch self {
        case .duas: localized("kesfet.dualar.alt")
        case .quran: localized("kesfet.kuran.alt")
        case .qibla: localized("kesfet.kible.alt")
        default: ""
        }
    }

    /// The tone of an area, the same everywhere (Keşfet, carousel).
    var discoverTone: CategoryTone {
        switch self {
        case .duas: .clay
        case .quran: .sage
        case .qibla: .olive
        case .dhikr: .turquoise
        case .divineNames: .saffron
        case .hadith: .sea
        case .talks: .purple
        case .quiz: .olive
        case .prayerTimes, .discover: .neutral
        }
    }
}
