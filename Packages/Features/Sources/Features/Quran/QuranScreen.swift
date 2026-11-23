import ContentPacks
import Core
import DesignSystem
import SwiftUI
import UserData

/// Quran home (Q-Sureler): search, edge-to-edge quick pick, „Devam et“ hero, Surah/Juz/Kaydedilen.
struct QuranScreen: View {
    enum ListMode: Hashable { case surah, juz, saved }

    @Environment(\.contentProvider) private var contentProvider
    @Environment(UserStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicSize
    @State private var search = ""
    @State private var list: ListMode = {
        #if DEBUG
            // Screenshots of the saved verses: `-kuranListe saved`.
            if UserDefaults.standard.string(forKey: "kuranListe") == "kaydedilen" { return .saved }
        #endif
        return .surah
    }()
    /// Surah list in Mushaf or revelation order; stays saved.
    @State private var revelationOrder = GroupDefaults.d.bool(forKey: "kuranNuzulSirasi")
    @State private var savedByDate = GroupDefaults.d.bool(forKey: "kuranKayitTarihe")

    static let quickPicks: [(LocalizedStringKey, ContentKey)] = [
        ("kuran.hizli.yasin", .verse(surah: 36, verse: 1)), ("kuran.hizli.mulk", .verse(surah: 67, verse: 1)),
        ("kuran.hizli.kehf", .verse(surah: 18, verse: 1)),
        ("kuran.hizli.kursi", .verse(surah: 2, verse: 255)),
    ]

    var body: some View {
        List {
            if let contentProvider {
                if search.isEmpty {
                    Section { fast }.listSectionMarginsHorizontal()
                    Section { resumeSection(contentProvider) }
                    Section { readingLinks }
                    Section {
                        Picker(localized("kuran.liste"), selection: $list) {
                            Text(app: "kuran.sure").tag(ListMode.surah)
                            Text(app: "kuran.cuz").tag(ListMode.juz)
                            Text(app: "kuran.kaydedilen").tag(ListMode.saved)
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        switch list {
                        case .surah:
                            Picker(localized("kuran.siralama"), selection: $revelationOrder) {
                                Text(app: "kuran.siralama.mushaf").tag(false)
                                Text(app: "kuran.siralama.nuzul").tag(true)
                            }
                            .onChange(of: revelationOrder) { _, n in
                                GroupDefaults.d.set(n, forKey: "kuranNuzulSirasi")
                            }
                            let surahs = contentProvider.surahs()
                            ForEach(
                                revelationOrder
                                    ? surahs.sorted { $0.revelationOrder < $1.revelationOrder } : surahs
                            ) {
                                surahRow($0)
                            }
                            if revelationOrder {
                                Text(app: "kuran.siralama.nuzul.kaynak").typography(.footnote)
                                    .foregroundStyle(theme.colors.text2)
                            }
                        case .juz: ForEach(1...30, id: \.self) { juzRow($0, contentProvider) }
                        case .saved: savedList
                        }
                    }
                    if list == .saved { savedItems(contentProvider) }
                } else {
                    searchResult(contentProvider)
                }
            } else {
                EmptyState(title: "kuran.paket_yok.baslik", explanation: "kuran.paket_yok.aciklama")
            }
        }
        .alwaysSearchable($search, prompt: localized("kuran.ara"))
        .pageBackground()
        .navigationTitle(localized("sekme.kuran"))
    }

    /// Quick pick edge-to-edge (A24): the row extends to the screen edge and is not cut off
    /// at a card edge; only the content keeps 16 pt spacing.
    private var fast: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.quickPicks, id: \.1) { name, a in
                    NavigationLink(value: Goal.verse(a)) {
                        Text(app: name).typography(.emphasized).padding(.horizontal, 14).frame(minHeight: 44)
                            .background(theme.colors.surface2, in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        .listRowBackground(Color.clear)
    }

    /// Colors of the dark „Devam et“ card: in the light scheme the Metin tone
    /// as the base with the roles of the dark sister palette on it, in the dark scheme the
    /// second surface with its own roles - so contrasts come from the tokens.
    private var cardColors: (background: Color, colors: ColorTokens) {
        let r = theme.colors
        if r.dark { return (r.surface2, r) }
        let contrast: ColorTokens =
            [
                (ColorTokens.calmLight, ColorTokens.calmDark), (.skyLight, .skyDark),
                (.ornamentLight, .ornamentDark),
                (.emeraldLight, .emeraldDark), (.nightLight, .nightDark), (.roseLight, .roseDark),
            ].first { $0.0 == r }?.1 ?? .dawnDark
        return (r.text, contrast)
    }

    /// „Devam et“ hero: surah in Arabic and Latin, ring for the
    /// progress in the surah, a tap goes to the last reading position. Without a reading position,
    /// the entry point is Al-Fâtiha. Khatm numbers only outside „Büyük ve sade“ and only from
    /// the first verse read - „0 / 6.236“ only discourages. Without a list chevron, the card carries
    /// its own button.
    @ViewBuilder
    private func resumeSection(_ contentProvider: any ContentProvider) -> some View {
        let _ = store.version
        let k = settings.activeKhatm
        let name = store.khatms().first { $0.kimlik == k }?.ad
        let readCount = store.versesReadCount(khatm: k)
        if let m = store.lastPosition(khatm: k), let a = ContentKey(text: m), case .verse(let s, let n) = a,
            let surah = contentProvider.surah(s)
        {
            NavigationLink(value: Goal.verse(a)) {
                continueCard(
                    parent: name ?? localized("kuran.kaldigin_yer"), surah: surah,
                    bottom: localized("kuran.hero.konum \(s) \(n) \(surah.verseCount)"),
                    mapButton: localized("kuran.devam_et"),
                    ratio: Double(n) / Double(max(surah.verseCount, 1)),
                    khatm: theme.largeAndSimple || readCount == 0
                        ? nil
                        : localized("kuran.hatim \(readCount) \(store.thisWeekDays(khatm: k))"))
            }
            .buttonStyle(.plain)
            .navigationLinkIndicatorVisibility(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)
        } else if let fatiha = contentProvider.surah(1) {
            NavigationLink(value: Goal.verse(.verse(surah: 1, verse: 1))) {
                continueCard(
                    parent: name ?? localized("kuran.basla"), surah: fatiha,
                    bottom: localized("kuran.basla.alt"),
                    mapButton: localized("kuran.hero.fatiha"), ratio: nil, khatm: nil)
            }
            .buttonStyle(.plain)
            .navigationLinkIndicatorVisibility(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    /// Reading position and study cards below the hero; the weekly overview is missing in „Büyük ve sade“.
    @ViewBuilder
    private var readingLinks: some View {
        if !theme.largeAndSimple {
            NavigationLink(value: Goal.readingGoals) { ReadingSummary() }
        }
        NavigationLink(value: Goal.memorization) {
            let _ = store.version
            let n = store.memorizationCards().filter { MemorizationScheduler.isDue($0.sonraki) }.count
            LabeledContent {
                if n > 0 { Text(verbatim: "\(n)").foregroundStyle(theme.colors.accent) }
            } label: {
                Label(localized("ezber.baslik"), systemImage: "brain.head.profile")
            }
        }
    }

    /// The card itself; with large fonts the ring slides below the text so that the
    /// surah name is not cut off.
    private func continueCard(
        parent: String, surah: Surah, bottom: String, mapButton: String, ratio: Double?, khatm: String?
    ) -> some View {
        let (background, r) = cardColors
        let text = VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: parent).typography(.footnote).textCase(.uppercase).fontWeight(.bold)
                .foregroundStyle(r.text2)
            Text(verbatim: surah.nameArabic).typography(.arabic(size: 30))
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityHidden(true)
            Text(verbatim: surah.name(language: translationLanguage())).typography(.title2)
            Text(verbatim: bottom).typography(.footnote).foregroundStyle(r.text2)
            if let khatm {
                Text(verbatim: khatm).typography(.footnote).foregroundStyle(r.text2)
            }
            Label(mapButton, systemImage: "play.fill")
                .typography(.emphasized)
                .padding(.horizontal, 18).frame(minHeight: 44)
                .foregroundStyle(r.onAccent)
                .background(r.accent, in: .capsule)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        return Group {
            if dynamicSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 14) {
                    text
                    if let ratio { surahProgress(ratio, r) }
                }
            } else {
                HStack(alignment: .center, spacing: 14) {
                    text
                    if let ratio { surahProgress(ratio, r) }
                }
            }
        }
        .foregroundStyle(r.text)
        .padding(18)
        .background(background, in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// Ring "how far into this surah": up to the bookmarked position, not the khatm.
    private func surahProgress(_ ratio: Double, _ r: ColorTokens) -> some View {
        ZStack {
            Circle().stroke(r.text.opacity(0.18), lineWidth: 7)
            Circle().trim(from: 0, to: min(max(ratio, 0), 1))
                .stroke(r.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(min(max(ratio, 0), 1), format: .percent.precision(.fractionLength(0)))
                .typography(.emphasized).monospacedDigit()
        }
        .frame(width: 76, height: 76)
    }

    private func surahRow(_ s: Surah) -> some View {
        NavigationLink(value: Goal.verse(.verse(surah: s.number, verse: 1))) {
            HStack(spacing: 12) {
                Text(verbatim: "\(revelationOrder ? s.revelationOrder : s.number)").typography(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 30)
                    .foregroundStyle(theme.colors.text2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: s.name(language: translationLanguage())).typography(.emphasized)
                    HStack(spacing: 4) {
                        Text(
                            app: s.revelationPlace == .meccan
                                ? "kuran.sure.alt.mekki \(s.verseCount)"
                                : "kuran.sure.alt.medeni \(s.verseCount)"
                        )
                        // In Nüzul order, additionally the position in the Mushaf.
                        if revelationOrder { Text(app: "kuran.sure.mushaf_no \(s.number)") }
                    }
                    .typography(.footnote).foregroundStyle(theme.colors.text2)
                }
                Spacer()
                Text(verbatim: s.nameArabic).typography(.arabic(size: 20))
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func juzRow(_ n: Int, _ contentProvider: any ContentProvider) -> some View {
        let first =
            contentProvider.juz(n).flatMap { contentProvider.key(index: $0.firstIndex) }
            ?? .verse(surah: 1, verse: 1)
        let name: String = {
            if case .verse(let s, let a) = first, let su = contentProvider.surah(s) {
                return "\(su.name(language: translationLanguage())) \(a)"
            }
            return ""
        }()
        return NavigationLink(value: Goal.verse(.juz(n))) {
            HStack {
                Text(app: "kuran.cuz.no \(n)").typography(.emphasized)
                Spacer()
                Text(verbatim: name).typography(.secondary).foregroundStyle(theme.colors.text2)
            }
        }
    }

    /// Like the surah list: a row that toggles the order.
    @ViewBuilder private var savedList: some View {
        if !store.saved().isEmpty {
            Picker(localized("kuran.siralama"), selection: $savedByDate) {
                Text(app: "kuran.kaydedilen.sureye_gore").tag(false)
                Text(app: "kuran.kaydedilen.tarihe_gore").tag(true)
            }
            .onChange(of: savedByDate) { _, t in GroupDefaults.d.set(t, forKey: "kuranKayitTarihe") }
        } else {
            Text(app: "kuran.kaydedilen.bos").typography(.secondary).foregroundStyle(theme.colors.text2)
        }
    }

    /// Saved verses: one section per group,
    /// per verse the verse number in a Mushaf mark, the beginning of the verse in Arabic and two
    /// lines of translation. Grouped by surah (Mushaf order) or by the day of saving,
    /// newest first. Previously each verse showed only „Nisâ 4:1“.
    @ViewBuilder
    private func savedItems(_ contentProvider: any ContentProvider) -> some View {
        let _ = store.version
        let translation = activeTranslations(contentProvider, settings).first?.id
        let l: [(ContentKey, Int, Int, Date)] = store.saved().compactMap { k in
            guard let a = ContentKey(text: k.anahtar), case .verse(let s, let n) = a else { return nil }
            return (a, s, n, k.tarih)
        }
        ForEach(SavedGroup.grouped(l, byDate: savedByDate)) { g in
            Section {
                ForEach(g.items, id: \.0) { a, s, n, _ in
                    NavigationLink(value: Goal.verse(a)) {
                        SavedRow(
                            verse: n, surah: savedByDate ? contentProvider.surah(s) : nil,
                            arabic: contentProvider.verse(a)?.text ?? "",
                            translation: translation.flatMap {
                                contentProvider.translation(a, pack: $0)?.text
                            } ?? "")
                    }
                    .swipeActions {
                        Button(localized("kuran.indirilenler.sil"), role: .destructive) {
                            store.toggleSaved(a.text)
                        }
                    }
                }
            } header: {
                switch g.kind {
                case .surah(let number):
                    if let su = contentProvider.surah(number) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: "\(number) · \(su.name(language: translationLanguage()))")
                            Spacer()
                            Text(verbatim: su.nameArabic).typography(.arabic(size: 18)).textCase(nil)
                        }
                    }
                case .day(let day):
                    Text(verbatim: SavedGroup.dayName(day))
                }
            }
        }
    }

    /// Search: „2:255“ jumps directly, otherwise surah names (Turkish, transliteration, meaning).
    @ViewBuilder
    private func searchResult(_ contentProvider: any ContentProvider) -> some View {
        let numbers = search.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        if numbers.count >= 2, contentProvider.verse(.verse(surah: numbers[0], verse: numbers[1])) != nil {
            NavigationLink(value: Goal.verse(.verse(surah: numbers[0], verse: numbers[1]))) {
                Text(app: "kuran.ara.git \(numbers[0]) \(numbers[1])")
            }
        }
        let k = TurkishText.searchForm(search)
        let result = contentProvider.surahs().filter { s in
            (numbers.count == 1 && s.number == numbers[0])
                || [s.nameTurkish, s.nameLatin, s.meaningEnglish].contains {
                    TurkishText.searchForm($0).contains(k)
                }
        }
        if result.isEmpty && numbers.count < 2 {
            Text(app: "kuran.ara.yok").foregroundStyle(theme.colors.text2)
        }
        ForEach(result) { surahRow($0) }
        // Meaning search in the verses (full text over translation and Okunuş).
        let verses = contentProvider.search(
            search, preferred: activeTranslations(contentProvider, settings).map(\.id), limit: 30
        )
        .filter { $0.kind == .translation || $0.kind == .transliteration }
        SearchSections(result: verses, queryText: search)
    }
}

extension View {
    /// A list section without side margins so that a horizontal row runs to the edge of the
    /// screen (A24); on the Mac there is no margin.
    fileprivate func listSectionMarginsHorizontal() -> some View {
        #if os(iOS)
            listSectionMargins(.horizontal, 0)
        #else
            self
        #endif
    }
}

/// A group of saved verses: a surah or a day.
struct SavedGroup: Identifiable {
    enum Kind: Hashable {
        case surah(Int)
        case day(Date)
    }

    let kind: Kind
    var items: [(ContentKey, Int, Int, Date)]
    var id: Kind { kind }

    /// By surah in Mushaf order, within it by verse; or by day, newest first.
    static func grouped(
        _ l: [(ContentKey, Int, Int, Date)], byDate: Bool, calendar: Calendar = .current
    ) -> [SavedGroup] {
        var g: [SavedGroup] = []
        if byDate {
            for o in l.sorted(by: { $0.3 > $1.3 }) {
                let day = calendar.startOfDay(for: o.3)
                if g.last?.kind == .day(day) {
                    g[g.count - 1].items.append(o)
                } else {
                    g.append(.init(kind: .day(day), items: [o]))
                }
            }
        } else {
            for o in l.sorted(by: { ($0.1, $0.2) < ($1.1, $1.2) }) {
                if g.last?.kind == .surah(o.1) {
                    g[g.count - 1].items.append(o)
                } else {
                    g.append(.init(kind: .surah(o.1), items: [o]))
                }
            }
        }
        return g
    }

    /// „Bugün“, „Dün“, otherwise the date in the app language.
    static func dayName(_ day: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(day) { return localized("genel.bugun") }
        if calendar.isDateInYesterday(day) { return localized("genel.dun") }
        return day.formatted(Date.FormatStyle(date: .long, time: .omitted).locale(AppLanguage.locale))
    }
}

/// A saved verse: on the left the verse number in a Mushaf mark, on the right the beginning of the verse in
/// Arabic on one line and two lines of translation. For groups by date, the surah is shown above.
struct SavedRow: View {
    @Environment(\.theme) private var theme
    let verse: Int
    let surah: Surah?
    let arabic: String
    let translation: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VerseMarker(number: verse)
            VStack(alignment: .leading, spacing: 4) {
                if let surah {
                    Text(verbatim: "\(surah.name(language: translationLanguage())) \(surah.number):\(verse)")
                        .typography(.footnote)
                        .bold()
                        .foregroundStyle(theme.colors.accent)
                }
                Text(verbatim: arabic).typography(.arabic(size: 20)).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .environment(\.layoutDirection, .rightToLeft)
                if !translation.isEmpty {
                    Text(verbatim: translation).typography(.secondary).foregroundStyle(theme.colors.text2)
                        .lineLimit(
                            2)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Verse number in the eight-pointed mark as in the Mushaf (two rotated squares).
struct VerseMarker: View {
    @Environment(\.theme) private var theme
    let number: Int

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).stroke(theme.colors.sage, lineWidth: 1.5)
            RoundedRectangle(cornerRadius: 4).stroke(theme.colors.sage, lineWidth: 1.5).rotationEffect(
                .degrees(45))
            Text(verbatim: "\(number)").font(.system(size: number > 99 ? 10 : 12, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(theme.colors.sage)
        }
        .frame(width: 26, height: 26)
        .padding(3)
        .accessibilityHidden(true)
    }
}
