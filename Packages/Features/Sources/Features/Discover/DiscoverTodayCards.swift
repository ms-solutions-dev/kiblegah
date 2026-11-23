import ContentPacks
import Core
import DesignSystem
import Duas
import Foundation
import PrayerTimes
import SwiftUI
import UserData

/// What „Bugün“ shows in Keşfet. App data only, fixed per date: Anyone looking
/// twice on the same day sees the same thing, even without network.
enum DiscoverToday {
    /// Consecutive day number, independent of the device's time zone.
    static func dayNumber(_ g: Day) -> Int {
        Int((g.start(.gmt).timeIntervalSince1970 / 86400).rounded(.down))
    }

    /// The slot of the day in a list with `count` entries, cycling in order.
    static func index(_ count: Int, day: Day) -> Int? {
        guard count > 0 else { return nil }
        let n = dayNumber(day) % count
        return n < 0 ? n + count : n
    }

    /// One name per day, going through all 99 in order.
    static func divineName(_ l: [DivineName], day: Day) -> DivineName? {
        index(l.count, day: day).map { l[$0] }
    }

    /// The next dini gün from today (today counts) and how many days until then.
    static func next(_ l: [ReligiousDay], today: Day) -> (day: ReligiousDay, remaining: Int)? {
        guard let d = l.filter({ $0.day >= today }).min(by: { $0.day < $1.day }) else { return nil }
        return (d, dayNumber(d.day) - dayNumber(today))
    }
}

/// The horizontal Bugün carousel: name of the day, next dini gün, dua of the day. In „Büyük ve
/// sade“ and at AX font sizes the cards are stacked so that nothing is cut off.
/// From the next card only a colored edge (12 pt, narrower than its inner padding) peeks out,
/// no cropped title like „SIRADAK…“.
struct DiscoverTodayCards: View {
    @Environment(\.contentProvider) private var contentProvider
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var size
    @Environment(PrayerTimeModel.self) private var prayerTimes
    @Environment(AppSettings.self) private var settings

    var body: some View {
        if theme.largeAndSimple || size.isAccessibilitySize {
            VStack(spacing: 12) { cards }
                .padding(.horizontal, 16)
        } else {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    cards.containerRelativeFrame(.horizontal) { w, _ in w - 8 }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder private var cards: some View {
        let tz = prayerTimes.table?.location.timeZone ?? .current
        // Calendar day of the device like the dua of the day and the Bugün tab.
        let today = Day(.now, timeZoneIdentifier: .current)
        if let e = DiscoverToday.divineName(contentProvider?.divineNames() ?? [], day: today) {
            NavigationLink(value: Goal.divineNameDetail(e.number)) {
                card(parent: "kesfet.gunun_ismi", ton: .saffron) {
                    // ed-Dârr only as the pair with en-Nâfi‘ (DivineName.namedWithPartner).
                    Text(verbatim: e.displayArabic).typography(.arabic(size: 28))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(verbatim: e.displayName)
                        .typography(
                            .emphasized)
                    Text(verbatim: e.displayMeaning).typography(.footnote).lineLimit(2)
                }
            }
            .buttonStyle(.plain)
        }
        if let s = DiscoverToday.next(religiousDays(today), today: today) {
            NavigationLink(value: Goal.calendar) {
                card(parent: "kesfet.siradaki", ton: .rose) {
                    Text(verbatim: remainingText(s.remaining)).typography(.title2)
                    Text(
                        verbatim: AppLanguage.bundle.localizedString(
                            forKey: "dini.\(s.day.kind.rawValue)", value: nil, table: nil)
                    )
                    .typography(.emphasized)
                    Text(verbatim: date(s.day.day, tz)).typography(.footnote)
                }
            }
            .buttonStyle(.plain)
        }
        if let contentProvider, let d = DuaContent.ofTheDay(contentProvider.duas(), day: .now) {
            NavigationLink(value: Goal.dua(d.slug)) {
                card(parent: "dua.gunun", ton: .clay) {
                    Text(verbatim: DuaContent.arabic(d, contentProvider)).typography(.arabic(size: 22))
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(
                        verbatim: DuaContent.transliteration(
                            d, contentProvider, language: transliterationLanguage(settings)) ?? ""
                    )
                    .typography(
                        .footnote
                    )
                    .lineLimit(2)
                    Text(verbatim: duaSource(d, contentProvider)).typography(.footnote)
                }
            }
            .buttonStyle(.plain)
        }
    }

    /// A card in the tone of its area; the heading carries the symbol color of the tone (≥ 4.5:1).
    private func card<I: View>(
        parent: LocalizedStringKey, ton: CategoryTone, @ViewBuilder _ content: () -> I
    ) -> some View {
        let r = theme.colors.category(ton)
        return VStack(alignment: .leading, spacing: 6) {
            Text(app: parent).typography(.footnote).textCase(.uppercase).foregroundStyle(r.icon)
            content()
        }
        .foregroundStyle(theme.colors.text)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .background(r.background, in: .rect(cornerRadius: 20))
        .contentShape(.rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }

    /// Calendar of this and next year; calculated without a location (no Diyanet list yet).
    private func religiousDays(_ today: Day) -> [ReligiousDay] {
        let flat = prayerTimes.table.map { HijriDate.adjustment($0) } ?? 0
        let thisYear =
            prayerTimes.religiousDays.isEmpty
            ? ReligiousDay.calculate(year: today.year, adjustment: flat) : prayerTimes.religiousDays
        return thisYear + ReligiousDay.calculate(year: today.year + 1, adjustment: flat)
    }

    private func remainingText(_ n: Int) -> String {
        switch n {
        case 0: localized("kesfet.bugun")
        case 1: localized("kesfet.yarin")
        default: localized("kesfet.gun_sonra \(n)")
        }
    }

    private func date(_ g: Day, _ tz: TimeZone) -> String {
        var s = Date.FormatStyle().day().month(.wide).weekday(.wide)
        s.locale = AppLanguage.locale
        s.timeZone = tz
        return g.start(tz).addingTimeInterval(12 * 3600).formatted(s)
    }
}
