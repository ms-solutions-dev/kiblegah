import ContentPacks
import Core
import DesignSystem
import Duas
import PrayerTimes
import SwiftUI
import UserData

/// Esmâü'l-Hüsnâ: list with search.
struct DivineNamesScreen: View {
    @Environment(\.contentProvider) private var contentProvider
    @Environment(\.theme) private var theme
    @State private var search = ""

    var body: some View {
        let l = (contentProvider?.divineNames() ?? []).filter { e in
            search.isEmpty
                || [e.latin, e.transliterationTR ?? "", e.meaning(translationLanguage()) ?? ""].contains {
                    TurkishText.searchForm($0).contains(TurkishText.searchForm(search))
                }
        }
        List {
            if l.isEmpty { Text(app: "dua.ara.yok").foregroundStyle(theme.colors.text2) }
            ForEach(l) { e in
                NavigationLink(value: Goal.divineNameDetail(e.number)) {
                    HStack(spacing: 12) {
                        Text(verbatim: "\(e.number)").typography(.footnote).monospacedDigit().frame(
                            minWidth: 26
                        )
                        .foregroundStyle(theme.colors.text2)
                        VStack(alignment: .leading, spacing: 2) {
                            // ed-Dârr only as the pair with en-Nâfi‘ (DivineName.namedWithPartner).
                            Text(verbatim: e.displayName)
                                .typography(
                                    .emphasized)
                            Text(verbatim: e.displayMeaning).typography(.footnote)
                                .foregroundStyle(
                                    theme.colors.text2
                                )
                                .lineLimit(e.partner == nil ? 1 : 2)
                        }
                        Spacer()
                        Text(verbatim: e.displayArabic).typography(.arabic(size: e.partner == nil ? 22 : 18))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if let contentProvider, contentProvider.unreviewed("esma") {
                Section { Text(app: "esma.kaynak").typography(.footnote).foregroundStyle(theme.colors.text2) }
            }
        }
        .alwaysSearchable($search, prompt: localized("esma.ara"))
        .navigationTitle(localized("sekme.esma"))
    }
}

/// Namaz rehberi: overview of the times → rakat plan.
struct GuideScreen: View {
    @Environment(\.theme) private var theme

    var body: some View {
        List {
            ForEach(PrayerGuide.prayerTimes) { v in
                Section {
                    ForEach(v.parts) { k in
                        NavigationLink(value: Goal.guideStep(k.id)) {
                            Text(app: "rehber.kisim \(k.rakat) \(k.name.text(translationLanguage()))")
                        }
                    }
                } header: {
                    Text(verbatim: v.name.text(translationLanguage()))
                }
            }
            Section { Text(app: "rehber.not").typography(.footnote).foregroundStyle(theme.colors.text2) }
        }
        .navigationTitle(localized("rehber.baslik"))
    }
}

/// Step by step with an honest count across all rakat; „Önceki adım“ and at the end „Bitir“.
struct GuideStepScreen: View {
    @Environment(\.contentProvider) private var contentProvider
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var close
    let sectionID: String
    @State private var step = 0
    @State private var light: String?

    var body: some View {
        if let k = PrayerGuide.prayerTimes.flatMap(\.parts).first(where: { $0.id == sectionID }) {
            let steps = PrayerGuide.steps(k)
            let a = steps[min(step, steps.count - 1)]
            VStack(alignment: .leading, spacing: 14) {
                Text(app: "rehber.sayac \(step + 1) \(steps.count) \(a.rakat) \(k.rakat)")
                    .typography(.footnote).foregroundStyle(theme.colors.text2)
                ProgressView(value: Double(step + 1), total: Double(steps.count)).tint(theme.colors.sage)
                Text(verbatim: a.title.text(translationLanguage())).typography(.title1)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let n = a.explanation {
                            Text(verbatim: n.text(translationLanguage())).typography(.body)
                        }
                        ForEach(a.recitations, id: \.id) { o in reading(o) }
                    }
                }
                HStack(spacing: 12) {
                    Button(localized("rehber.onceki")) { step -= 1 }
                        .buttonStyle(SecondaryButton()).disabled(step == 0)
                    if step + 1 < steps.count {
                        Button(localized("rehber.sonraki")) { step += 1 }.buttonStyle(PrimaryButton())
                    } else {
                        Button(localized("rehber.bitir")) { close() }.buttonStyle(PrimaryButton())
                    }
                }
            }
            .padding(20)
            .pageBackground()
            .navigationTitle(k.name.text(translationLanguage()))
            .smallTitle()
        }
    }

    /// A text: tapping expands Arabic, Okunuş and meaning; Quran passages open the reader.
    @ViewBuilder private func reading(_ o: PrayerGuide.Recitation) -> some View {
        if let verse = o.verse {
            NavigationLink(
                value: Goal.verse(
                    verse == .surah(112) || verse == .surah(1)
                        ? .verse(surah: verseSurah(verse), verse: 1) : verse)
            ) {
                HStack {
                    Text(verbatim: o.name.text(translationLanguage())).typography(.emphasized)
                    Spacer()
                    Image(systemName: "book").accessibilityHidden(true)
                }
                .padding(14)
                .background(theme.colors.surface, in: .rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        } else {
            Button {
                light = light == o.id ? nil : o.id
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(verbatim: o.name.text(translationLanguage())).typography(.emphasized)
                        Spacer()
                        Image(systemName: light == o.id ? "chevron.up" : "chevron.down").accessibilityHidden(
                            true)
                    }
                    if light == o.id {
                        if let ar = o.arabic {
                            Text(verbatim: ar).typography(.arabic(size: 26)).multilineTextAlignment(.trailing)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        if let ok = o.transliteration { Text(verbatim: ok).typography(.body) }
                        if let time = o.meaning {
                            Text(verbatim: time.text(translationLanguage())).typography(.secondary)
                                .foregroundStyle(
                                    theme.colors.text2)
                        }
                    }
                }
                .foregroundStyle(theme.colors.text)
                .padding(14)
                .background(theme.colors.surface, in: .rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(light == o.id ? .isSelected : [])
        }
    }

    private func verseSurah(_ a: ContentKey) -> Int {
        if case .surah(let s) = a { return s } else { return 1 }
    }
}

/// Takvim: Kandiller and mübarek günler of this and next year.
struct CalendarScreen: View {
    @Environment(PrayerTimeModel.self) private var prayerTimes
    @Environment(\.theme) private var theme

    var body: some View {
        let tz = prayerTimes.table?.location.timeZone ?? .current
        let today = Day(.now, timeZoneIdentifier: tz)
        let flat = prayerTimes.table.map { HijriDate.adjustment($0) } ?? 0
        let l = (prayerTimes.religiousDays + ReligiousDay.calculate(year: today.year + 1, adjustment: flat))
            .filter { $0.day >= today }
        List {
            if l.isEmpty { Text(app: "takvim.bos").foregroundStyle(theme.colors.text2) }
            ForEach(Array(l.enumerated()), id: \.offset) { _, d in
                HStack(spacing: 12) {
                    IconTile(Self.icon(d.kind), tone: Self.ton(d.kind))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            verbatim: AppLanguage.bundle.localizedString(
                                forKey: "dini.\(d.kind.rawValue)", value: nil, table: nil)
                        )
                        .typography(.emphasized)
                        Text(verbatim: date(d.day, tz)).typography(.footnote).foregroundStyle(
                            theme.colors.text2)
                    }
                    Spacer()
                    if d.source == .calculated {
                        Text(app: "vakit.yaklasik").typography(.footnote).foregroundStyle(theme.colors.text2)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Section { Text(app: "takvim.not").typography(.footnote).foregroundStyle(theme.colors.text2) }
        }
        .navigationTitle(localized("takvim.baslik"))
    }

    /// Imagery as in Hadith (08 A): nights, festivals, Ramadan and the remaining days each get one tone.
    static func ton(_ t: ReligiousDay.Kind) -> CategoryTone {
        switch t {
        case .mawlidKandil, .raghaibKandil, .mirajKandil, .baratKandil, .laylatAlQadr: .purple
        case .eidAlFitr, .eidAlAdha, .eidAlFitrEve, .dayOfArafah: .saffron
        case .ramadanStart: .sage
        case .hijriNewYear, .ashura, .threeHolyMonthsStart: .rose
        }
    }

    static func icon(_ t: ReligiousDay.Kind) -> String {
        switch t {
        case .mawlidKandil, .raghaibKandil, .mirajKandil, .baratKandil, .laylatAlQadr: "moon.stars"
        case .eidAlFitr, .eidAlAdha, .eidAlFitrEve, .dayOfArafah: "sparkles"
        case .ramadanStart: "moon"
        case .hijriNewYear, .ashura, .threeHolyMonthsStart: "calendar"
        }
    }

    private func date(_ g: Day, _ tz: TimeZone) -> String {
        var s = Date.FormatStyle(date: .complete, time: .omitted)
        s.locale = AppLanguage.locale
        s.timeZone = tz
        return g.start(tz).addingTimeInterval(12 * 3600).formatted(s)
    }
}
