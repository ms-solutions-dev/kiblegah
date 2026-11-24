import ContentPacks
import Core
import DesignSystem
import Quran
import SwiftUI
import UserData

/// The chosen translations: selection from Ayarlar, otherwise one in the app language.
/// The language of the word meanings: that of the first translation read (Diyanet translation → Turkish,
/// even with a German app), otherwise the app language.
@MainActor func wordLanguage(_ contentProvider: (any ContentProvider)?, _ settings: AppSettings) -> String {
    contentProvider.flatMap { activeTranslations($0, settings).first?.language } ?? translationLanguage()
}

@MainActor func activeTranslations(
    _ contentProvider: any ContentProvider, _ settings: AppSettings
) -> [PackManifest] {
    let all = contentProvider.translations()
    let selected = settings.selectedTranslations.compactMap { id in all.first { $0.id == id } }
    if !selected.isEmpty { return selected }
    return Array(
        (contentProvider.translations(language: translationLanguage()).first ?? all.first).map { [$0] } ?? [])
}

/// The reader as a list (Q-Okuyucu): one surah, verse by verse, with the translation source in the header.
///
/// The topmost visible verse is „Kaldığın yer“; on leaving, the range read
/// is saved as a reading event.
struct ReaderScreen: View {
    @Environment(\.contentProvider) private var contentProvider
    @Environment(AppSettings.self) private var settings
    @Environment(UserStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.scenePhase) private var phase
    @Environment(RecitationPlayer.self) private var player
    @Environment(Router.self) private var direction
    @Environment(AudioStore.self) private var audioStore
    let start: ContentKey
    /// iPad: the host holds selection, position and detail; bars and sheets of this page stay out.
    var pad: PadReaderLink? = nil
    /// Jump via the title page (): replaces the entry point without stacking a new screen.
    @State private var pendingJump: ContentKey?
    @State private var goOpen = false
    private var enabled: ContentKey { pendingJump ?? start }
    @State private var visible: Int?
    /// When this reader first appeared (for ``QuranPosition``).
    @State private var firstLaunch: Date?
    /// The verse in the open verse sheet: highlighted, and the list follows it into other surahs too ().
    @State private var light: Int?
    /// If playback reads past the end of the surah („bis Seitenende“, range), the list follows
    /// into the next surah instead of stopping at the last verse.
    @State private var followedSurah: Int?
    /// Follow as in map navigation: the list scrolls with the verse being played (also into the
    /// next surah) until the user scrolls; the center button or a new playback turns
    /// it back on.
    @State private var following = true
    @State private var selected: Verse?
    @State private var readingVerse: Verse?
    @State private var settingOpen = false
    @State private var seenRange: ClosedRange<Int>?
    @State private var launch = Date.now
    /// Word meanings per surah → verse (in a juz several surahs are in one list).
    @State private var wordMeanings: [Int: [Int: [WordMeaning]]] = [:]
    /// Height of the bar above the text, for the gradient below it.
    @State private var topInset: CGFloat = 0
    /// Measured width of the page capsule; ``kafa(translations:)`` keeps it free on the right.
    @State private var capsuleWidth: CGFloat = 0
    @Environment(\.wordByWord) private var wordByWord

    /// Juz view: the whole juz as one list across all its surahs.
    private var juzNumber: Int? {
        if case .juz(let n) = enabled { return n }
        return nil
    }

    private var surahByNumber: Int {
        if let followedSurah { return followedSurah }
        // In a juz, the surah of the topmost visible verse applies (title menu, Dinle, Mushaf).
        if let juzNumber, let contentProvider, let b = contentProvider.juz(juzNumber),
            case .verse(let s, _) = contentProvider.key(index: visible ?? b.firstIndex)
        {
            return s
        }
        return switch enabled {
        case .verse(let s, _), .verseRange(let s, _, _), .word(let s, _, _), .surah(let s): s
        default: 1
        }
    }

    /// Gradient below the glass bar: opaque at the top in the base tone,
    /// transparent toward the text, so the translation text does not overlap the title while the bar
    /// keeps its glass. Extends 28 pt below the bar and intercepts no taps.
    private var topGradient: some View {
        let total = topInset + 28
        return LinearGradient(
            stops: [
                .init(color: theme.colors.background, location: 0),
                .init(color: theme.colors.background, location: topInset / total),
                .init(color: theme.colors.background.opacity(0), location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: total)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    var body: some View {
        if let contentProvider, let surah = contentProvider.surah(surahByNumber) {
            let verses =
                juzNumber.map { contentProvider.verses(.juz($0)) }
                ?? contentProvider.verses(.surah(surah.number))
            let translations = activeTranslations(contentProvider, settings)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if pad == nil || settings.wordByWord { kafa(translations: translations) }
                    if juzNumber == nil {
                        SurahHeader(surah: surah, bandOnly: pad != nil)
                        basmala(surah, contentProvider)
                    }
                    ForEach(verses) { a in
                        if juzNumber != nil, a.verse == 1, let s = contentProvider.surah(a.surah) {
                            SurahHeader(surah: s)
                            basmala(s, contentProvider)
                        }
                        // Juz 1-29 usually begin in the middle of a surah: then only one line, no header band.
                        if juzNumber != nil, a.verse > 1, a.id == verses.first?.id,
                            let s = contentProvider.surah(a.surah)
                        {
                            Text(app: "kuran.cuz.devam \(s.name(language: translationLanguage())) \(a.verse)")
                                .typography(.footnote).foregroundStyle(theme.colors.label)
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                        }
                        VerseCell(
                            verse: a, translations: translations,
                            wordMeanings: wordMeanings[a.surah]?[a.verse]
                        )
                        .padding(.horizontal, pad == nil ? 0 : 20)
                        .background { rowBackground(a) }
                        .overlay(alignment: .leading) {
                            if pad == nil, isPlaying(a) || light == a.index {
                                Rectangle().fill(theme.colors.accent).frame(width: 4).offset(x: -10)
                            }
                        }
                        .id(a.index)
                        .contentShape(.rect)
                        .onTapGesture { select(a) }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction(named: localized("kuran.ayet.islemler")) { select(a) }
                        if pad == nil { Divider().overlay(theme.colors.line) }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, pad == nil ? 16 : 12)
            }
            .contentMargins(.bottom, pad == nil ? 0 : 90, for: .scrollContent)
            .scrollPosition(id: $visible, anchor: .top)
            // Scrolled manually (not our scrolling along): following paused, no surah change either.
            .onScrollPhaseChange { _, y in
                if y == .interacting, player.isActive { withAnimation { following = false } }
            }
            .overlay(alignment: .bottomTrailing) {
                if player.isActive && !following {
                    FollowAlongButton {
                        withAnimation { following = true }
                        if let s = player.current {
                            follow(s, surah: surah, verses: verses, contentProvider: contentProvider)
                        }
                    }
                    .padding(.bottom, pad == nil ? 0 : 84)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if pad == nil, !PadLayout.isPad { PlayerBar() }
            }
            .overlay(alignment: .top) {
                if pad == nil { topGradient }
            }
            .overlay(alignment: .topTrailing) {
                if pad == nil { pageMargin(contentProvider, surah) }
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.safeAreaInsets.top }) { topInset = $0 }
            .sheet(item: $readingVerse) { ReadingOptions(verse: $0) }
            .onChange(of: player.current) { _, s in
                guard following, let s else { return }
                follow(s, surah: surah, verses: verses, contentProvider: contentProvider)
            }
            // New playback: follow again.
            .onChange(of: player.queue) { withAnimation { following = true } }
            #if DEBUG
                .task { await followCheck(player, contentProvider) { following = false } }
            #endif
            .modifier(
                ReaderChrome(
                    isPad: pad != nil,
                    title: juzNumber.map { localized("kuran.cuz.no \($0)") }
                        ?? surah.name(language: translationLanguage()))
            )
            .sheet(isPresented: $goOpen) {
                MushafJumpSheet(current: mushafPage(contentProvider, surah), edition: .v1, git: { _ in }) {
                    goal in
                    skipTo(goal, contentProvider)
                }
            }
            .toolbar {
                if pad == nil {
                    // Title as a button as in the Mushaf: directly to surah/verse, juz or page.
                    ToolbarItem(placement: .principal) {
                        Button {
                            goOpen = true
                        } label: {
                            HStack(spacing: 4) {
                                Text(
                                    verbatim: juzNumber.map { localized("kuran.cuz.no \($0)") }
                                        ?? surah.name(language: translationLanguage())
                                )
                                .font(.headline).lineLimit(1)
                                Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                                    .foregroundStyle(theme.colors.text2)
                            }
                            .foregroundStyle(theme.colors.text)
                        }
                        .accessibilityHint(localized("kuran.mushaf.git.ipucu"))
                    }
                    // Straight into the Mushaf, without the menu.
                    ToolbarItem(placement: .primaryAction) {
                        NavigationLink(value: Goal.mushaf(mushafPage(contentProvider, surah))) {
                            Image(systemName: "book.pages")
                        }
                        .accessibilityLabel(localized("kuran.mushaf"))
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            listen(surah, contentProvider: contentProvider)
                        } label: {
                            Image(systemName: "play.fill")
                        }
                        .accessibilityLabel(localized("kuran.oynatici.dinle"))
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            // Plugin entries for the verse currently at the top.
                            if let k = contentProvider.key(index: visible ?? surah.firstIndex) {
                                SlotView(.verseMenuAction(k))
                            }
                            Button {
                                settingOpen = true
                            } label: {
                                Label(localized("kuran.okuma_ayarlari"), systemImage: "textformat.size")
                            }
                            downloadButton(surah)
                            NavigationLink(value: Goal.downloaded) {
                                Label(localized("kuran.indirilenler"), systemImage: "arrow.down.circle")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel(localized("kuran.daha_fazla"))
                    }
                }
            }
            .sheet(item: $selected, onDismiss: { light = nil }) { a in
                VerseSheet(
                    verse: a,
                    changed: { y in
                        // Swiped: the list runs along under the sheet, past the end of the surah ().
                        light = y.index
                        if verses.contains(where: { $0.index == y.index }) {
                            withAnimation { visible = y.index }
                        } else if let b = self.contentProvider {
                            skipTo(y.key, b)
                        }
                    },
                    readInContext: { goal in
                        if goal.surah == surah.number || verses.contains(where: { $0.index == goal.index }) {
                            withAnimation { visible = goal.index }
                        } else {
                            direction.open(.verse(goal.key), tabs: settings.tabs)
                        }
                    })
            }
            .sheet(isPresented: $settingOpen) { ReadingSettings() }
            .onAppear {
                launch = .now
                // Back from the Mushaf: continue where the user paged to there.
                if let first = firstLaunch {
                    if let s = QuranPosition.shared.fromOther(.scrollProxy, after: first), s != visible,
                        let a = contentProvider.key(index: s)
                    {
                        skipTo(a, contentProvider)
                    }
                    firstLaunch = .now
                    return
                }
                firstLaunch = .now
                if case .verse(_, let n) = start, n > 1 { visible = surah.firstIndex + n - 1 }
                #if DEBUG
                    // Screen test without tapping: `-ayetReiter tafsir` opens the sheet of the start verse.
                    if UserDefaults.standard.string(forKey: "ayetReiter") != nil,
                        case .verse(_, let n) = start
                    {
                        Task {
                            try? await Task.sleep(for: .milliseconds(800))
                            selected = verses.first { $0.index == surah.firstIndex + n - 1 }
                        }
                    }
                #endif
            }
            .onChange(of: pad?.jump.wrappedValue) { _, k in
                guard let k else { return }
                pad?.jump.wrappedValue = nil
                if case .verse(let s, let n) = k, let su = contentProvider.surah(s), s == surah.number {
                    withAnimation { visible = su.firstIndex + n - 1 }
                } else {
                    skipTo(k, contentProvider)
                }
            }
            .onChange(of: visible) { _, yeni in
                pad?.visible.wrappedValue = yeni
                guard let yeni, let k = contentProvider.key(index: yeni) else { return }
                QuranPosition.shared.save(yeni, .scrollProxy)
                store.saveLastPosition(k.text, khatm: settings.activeKhatm)
                seenRange =
                    seenRange.map { min($0.lowerBound, yeni)...max($0.upperBound, yeni) } ?? yeni...yeni
            }
            .onChange(of: phase) { _, e in if e != .active { save() } }
            .task(
                id:
                    "\(juzNumber.map { "c\($0)" } ?? "\(surah.number)")-\(settings.wordByWord)-\(wordLanguage(contentProvider, settings))"
            ) {
                guard settings.wordByWord else {
                    wordMeanings = [:]
                    return
                }
                let language = wordLanguage(contentProvider, settings)
                var surahs: [Int] = []
                for a in verses where surahs.last != a.surah { surahs.append(a.surah) }
                for s in surahs where wordMeanings[s] == nil {
                    if let k = await wordByWord?.surah(s, language: language) { wordMeanings[s] = k }
                }
            }
            .onDisappear { save() }
        } else {
            EmptyState(title: "kuran.paket_yok.baslik", explanation: "kuran.paket_yok.aciklama")
        }
    }

    /// Header above the text: only the translation source and the word-by-word hint. Surah number, Meccan/Medinan
    /// and verse count are already in the ``SurahHeader`` below. The width of the side capsule stays
    /// free on the right, so even two translations or a two-line hint do not disappear under it.
    private func kafa(translations: [PackManifest]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if pad == nil {
                Text(app: "kuran.meal_kaynagi \(translations.map(\.title).joined(separator: ", "))")
                    .typography(.footnote).foregroundStyle(theme.colors.text2)
            }
            if settings.wordByWord {
                Text(
                    app: wordLanguage(contentProvider, settings) == "de"
                        ? "kuran.kelime.kaynak.de" : "kuran.kelime.kaynak"
                )
                .typography(.footnote).foregroundStyle(theme.colors.text2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, capsuleWidth + 8)
        .padding(.vertical, 12)
    }

    @ViewBuilder private func basmala(_ s: Surah, _ contentProvider: any ContentProvider) -> some View {
        if s.basmala {
            Text(verbatim: contentProvider.basmala)
                .typography(.arabic(size: settings.arabicSize))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .accessibilityLabel(localized("kuran.besmele"))
        }
    }

    private func select(_ a: Verse) {
        if let pad { pad.selection.wrappedValue = a } else { selected = a }
    }

    /// iPhone: a band. iPad: a rounded row, heard softly tinted, selected with an outline (boards G07, G12).
    @ViewBuilder private func rowBackground(_ a: Verse) -> some View {
        if let pad {
            let chosen = pad.selection.wrappedValue?.index == a.index
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    isPlaying(a)
                        ? theme.colors.accent.opacity(0.16)
                        : chosen ? theme.colors.accent.opacity(0.06) : .clear
                )
                .overlay {
                    if chosen {
                        RoundedRectangle(cornerRadius: 20).strokeBorder(
                            theme.colors.accent.opacity(0.55), lineWidth: 1.5)
                    }
                }
                .padding(.vertical, 2)
                .animation(.easeInOut(duration: 0.4), value: isPlaying(a))
                .animation(.easeInOut(duration: 0.3), value: chosen)
        } else {
            isPlaying(a) || light == a.index ? theme.colors.surface2 : .clear
        }
    }

    private func isPlaying(_ a: Verse) -> Bool {
        guard let s = player.current else { return false }
        return s.surah == a.surah && s.verse == a.verse && !s.basmala
    }

    /// Verse tracking: the verse being played scrolls to the top; in surah mode the list continues
    /// past the end of the surah into the next surah.
    private func follow(
        _ s: RecitationPlayer.QueueItem, surah: Surah, verses: [Verse], contentProvider: any ContentProvider
    ) {
        if juzNumber != nil {
            guard !s.basmala, let su = contentProvider.surah(s.surah),
                verses.contains(where: { $0.surah == s.surah && $0.verse == s.verse })
            else { return }
            withAnimation { visible = su.firstIndex + s.verse - 1 }
            return
        }
        guard s.surah == surah.number else {
            guard let yeni = contentProvider.surah(s.surah) else { return }
            save()
            followedSurah = yeni.number
            let goal = yeni.firstIndex + (s.basmala ? 0 : s.verse - 1)
            // Scroll only after the rebuild with the new surah, otherwise the target ID is missing.
            Task { @MainActor in withAnimation { visible = goal } }
            return
        }
        guard !s.basmala else { return }
        withAnimation { visible = surah.firstIndex + s.verse - 1 }
    }

    /// „Okuma Seçenekleri“ for the topmost visible verse of this surah.
    private func listen(_ surah: Surah, contentProvider: any ContentProvider) {
        var verse = 1
        if let g = visible, case .verse(let s, let n) = contentProvider.key(index: g), s == surah.number {
            verse = n
        }
        readingVerse = contentProvider.verse(.verse(surah: surah.number, verse: verse))
    }

    @ViewBuilder private func downloadButton(_ surah: Surah) -> some View {
        let k = Reciter.find(settings.reciter)
        switch audioStore.status(k, surah: surah.number, verseCount: surah.verseCount) {
        case .ready:
            Label(localized("kuran.ses.indirildi"), systemImage: "checkmark.circle")
        case .downloading(let p):
            Button {
                audioStore.cancel(k, surah: surah.number)
            } label: {
                Label(localized("kuran.ses.iniyor.yuzde \(Int(p * 100))"), systemImage: "stop.circle")
            }
        case .yok:
            Button {
                audioStore.download(k, surah: surah.number, verseCount: surah.verseCount)
            } label: {
                Label(localized("kuran.ses.indir"), systemImage: "arrow.down.circle")
            }
        }
    }

    /// Glass capsule below the title bar: page and juz of the topmost
    /// visible verse. It sits above the header area, not above the right-aligned Arabic.
    private func pageMargin(_ contentProvider: any ContentProvider, _ surah: Surah) -> some View {
        let index = visible ?? surah.firstIndex
        let a = contentProvider.key(index: index).flatMap { contentProvider.verse($0) }
        let page = a?.page ?? 1
        return Text(app: "kuran.sayfa.kapsul \(page) \(a?.juz ?? 1)")
            .typography(.footnote).monospacedDigit()
            .foregroundStyle(theme.colors.text)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .glassEffect(.regular, in: .capsule)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { capsuleWidth = $0 }
            .padding(.top, 4)
            .padding(.trailing, 16)
            .allowsHitTesting(false)
            .contentTransition(.numericText())
            .animation(.default, value: page)
    }

    /// Jump from the title page: juz opens the juz list, otherwise the surah of the target; then scroll to the verse.
    private func skipTo(_ goal: ContentKey, _ contentProvider: any ContentProvider) {
        save()
        followedSurah = nil
        switch goal {
        case .juz(let n):
            pendingJump = .juz(n)
            let first = contentProvider.juz(n)?.firstIndex
            Task { @MainActor in visible = first }
        case .verse(let s, let a):
            pendingJump = .verse(surah: s, verse: a)
            let index = contentProvider.surah(s).map { $0.firstIndex + a - 1 }
            Task { @MainActor in withAnimation { visible = index } }
        default:
            break
        }
    }

    /// Mushaf page of the currently visible verse.
    private func mushafPage(_ contentProvider: any ContentProvider, _ surah: Surah) -> Int {
        let index = visible ?? surah.firstIndex
        return contentProvider.key(index: index).flatMap { contentProvider.verse($0)?.page } ?? 1
    }

    /// The part read up to the bottom edge of the screen: one event per visit.
    private func save() {
        guard let g = seenRange else { return }
        store.addReading(
            firstIndex: g.lowerBound, lastIndex: g.upperBound, seconds: Date.now.timeIntervalSince(launch),
            khatm: settings.activeKhatm)
        seenRange = nil
        launch = .now
    }
}

/// One verse: number, Arabic, transliteration, translation(s).
struct VerseCell: View {
    @Environment(\.contentProvider) private var contentProvider
    @Environment(AppSettings.self) private var settings
    @Environment(UserStore.self) private var store
    @Environment(RecitationPlayer.self) private var player
    @Environment(\.theme) private var theme
    let verse: Verse
    let translations: [PackManifest]
    var wordMeanings: [WordMeaning]? = nil
    @Environment(\.padReaderStyle) private var padStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(verbatim: "\(verse.surah):\(verse.verse)").typography(.footnote).monospacedDigit()
                    .foregroundStyle(padStyle ? theme.colors.label : theme.colors.text2)
                    .fontWeight(padStyle ? .semibold : .regular)
                    .padding(.horizontal, padStyle ? 10 : 0)
                    .padding(.vertical, padStyle ? 6 : 0)
                    .background(padStyle ? theme.colors.surface2 : .clear, in: .capsule)
                // Page marker at the first verse of each Mushaf page and at the start of a surah (variant C).
                if verse.verse == 1 || contentProvider?.page(verse.page)?.firstIndex == verse.index {
                    Text(app: "kuran.sayfa.kisa \(verse.page)").typography(.footnote).monospacedDigit()
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(theme.colors.surface2, in: .capsule)
                        .foregroundStyle(theme.colors.label)
                }
                if verse.sajdah != nil {
                    Image(systemName: "arrow.down.to.line").foregroundStyle(theme.colors.accent)
                        .accessibilityLabel(localized("kuran.secde"))
                }
                let _ = store.version
                if store.isSaved(verse.key.text) {
                    Image(systemName: "bookmark.fill").foregroundStyle(theme.colors.accent)
                        .accessibilityLabel(localized("kuran.kaydedildi"))
                }
                if store.note(verse.key.text) != nil {
                    Image(systemName: "note.text").foregroundStyle(theme.colors.sage)
                        .accessibilityLabel(localized("kuran.notun_var"))
                }
                Spacer()
            }
            if settings.wordByWord, let k = wordMeanings, k.count == verse.words.count {
                WordFlow(
                    words: verse.words, meanings: k, size: settings.arabicSize * 0.85,
                    tajweed: settings.tajweedColors ? (contentProvider?.tajweed(verse.key) ?? []) : [],
                    translationSize: max(12, settings.translationSize * 0.75), accent: playingWord,
                    listenFromWord: Reciter.find(settings.reciter).qcID == nil
                        ? nil : { n in listenFromWord(n) })
            } else {
                // Also without word-by-word translation, so that a long press speaks the word.
                WordFlow(
                    words: verse.words, meanings: [], size: settings.arabicSize,
                    tajweed: settings.tajweedColors ? (contentProvider?.tajweed(verse.key) ?? []) : [],
                    translationSize: 0, accent: playingWord,
                    listenFromWord: Reciter.find(settings.reciter).qcID == nil
                        ? nil : { n in listenFromWord(n) },
                    end: verseEnd(verse.verse), interval: settings.arabicSize * 0.3)
            }
            if settings.showTransliteration,
                let o = contentProvider?.transliteration(
                    verse.key, language: transliterationLanguage(settings))
            {
                Text(verbatim: o.text).font(
                    .custom(
                        "Plus Jakarta Sans", size: max(16, settings.transliterationSize), relativeTo: .body)
                )
                .foregroundStyle(theme.colors.text2)
            }
            ForEach(padStyle && !settings.showTranslationInReader ? [] : translations) { m in
                if let text = contentProvider?.translation(verse.key, pack: m.id) {
                    VStack(alignment: .leading, spacing: 2) {
                        if translations.count > 1 {
                            Text(verbatim: m.title).typography(.footnote).textCase(.uppercase)
                                .foregroundStyle(
                                    theme.colors.label)
                        }
                        Text(verbatim: text.markedText).font(
                            .custom("Plus Jakarta Sans", size: settings.translationSize, relativeTo: .body))
                        TranslationFootnotes(notes: text.footnotes).padding(.top, 4)
                    }
                }
            }
        }
        .padding(.vertical, 16)
    }
}

extension VerseCell {
    var arabic: Text {
        let end = " " + verseEnd(verse.verse)
        var a =
            if settings.tajweedColors, let t = contentProvider?.tajweed(verse.key), !t.isEmpty {
                tajweedText(verse.text, spans: t, dark: theme.colors.dark, ek: end)
            } else {
                AttributedString(verse.text + end)
            }
        if let n = playingWord { highlightWord(&a, verse, n, color: theme.colors.accent.opacity(0.25)) }
        return Text(a)
    }

    /// From word `n` to the end of the surah; the word timings are loaded beforehand.
    private func listenFromWord(_ n: Int) {
        guard let s = contentProvider?.surah(verse.surah) else { return }
        player.reciter = Reciter.find(settings.reciter)
        let verses = (verse.verse...s.verseCount).map { (surah: verse.surah, verse: $0) }
        Task {
            _ = await player.prepareTimings(surah: verse.surah)
            player.play(queue: RecitationPlayer.queue(verses: verses, withBasmala: false), word: n)
        }
    }

    /// The word of this verse currently being recited, otherwise nil.
    private var playingWord: Int? {
        guard let s = player.current, !s.basmala, s.surah == verse.surah, s.verse == verse.verse else {
            return nil
        }
        return player.currentWord
    }
}

/// „﴿١٢﴾“: verse end with Arabic-Indic digits.
/// „78. sure · Mekkî · 40 ayet“. For surahs whose classification is disputed (Tanzil/Medina Mushaf
/// versus Diyanet, e.g. Rahmân, Felak, Nâs), it also states whose count applies.
func surahHeader(_ s: Surah) -> LocalizedStringKey {
    let disputed = QuestionGenerator.revelationPlaceDisputed.contains(s.number)
    return switch (s.revelationPlace, disputed) {
    case (.meccan, false): "kuran.kafa.mekki \(s.number) \(s.verseCount)"
    case (.meccan, true): "kuran.kafa.mekki.ihtilaf \(s.number) \(s.verseCount)"
    case (.medinan, false): "kuran.kafa.medeni \(s.number) \(s.verseCount)"
    case (.medinan, true): "kuran.kafa.medeni.ihtilaf \(s.number) \(s.verseCount)"
    }
}

func verseEnd(_ n: Int) -> String {
    let digits = String(
        String(n).map { c in c.wholeNumberValue.map { Character(UnicodeScalar(0x0660 + $0)!) } ?? c })
    return "\u{FD3F}\(digits)\u{FD3E}"
}

/// Highlights word `n` (1-based) in the verse text; words are separated by a single space each.
func highlightWord(_ a: inout AttributedString, _ verse: Verse, _ n: Int, color: Color) {
    guard n >= 1, n <= verse.words.count else { return }
    let start = verse.words.prefix(n - 1).reduce(0) { $0 + $1.text.unicodeScalars.count + 1 }
    let length = verse.words[n - 1].text.unicodeScalars.count
    guard start + length <= a.unicodeScalars.count else { return }
    let b = a.unicodeScalars.index(a.startIndex, offsetBy: start)
    let e = a.unicodeScalars.index(b, offsetBy: length)
    a[b..<e].backgroundColor = color
}

/// Header band at the start of each surah: at the top the ornamental band as in the
/// printed Mushaf with „سورة …“ and points at both ends, below it name, number,
/// Meccan/Medinan and verse count. Visibly separates surahs within the juz.
/// The ornamental band of a surah start: points left and right, hatching, lines above and below,
/// „سورة …“ in the label color. Shared by the list header (`SurahHeader`) and the Mushaf
/// (fitted into the line height at 1x, larger when wrapped).
struct SurahBand: View {
    @Environment(\.theme) private var theme
    let nameArabic: String
    let height: CGFloat
    /// Small details in the band (Mushaf at 1x, where there is no room for an extra line): left and right
    /// of the Arabic name, independent of the reading direction. They are dropped if the width is too small.
    var sol: Text?
    var sag: Text?
    @State private var width: CGFloat = 0

    var body: some View {
        let color = theme.colors.label
        let uc = height * 18 / 46
        HStack(spacing: 0) {
            Arrowhead(sag: false).fill(color.opacity(0.85)).frame(width: uc)
            Text(verbatim: "سُورَةُ " + nameArabic)
                .font(.custom(Typography.arabicFontName, fixedSize: height * 22 / 46))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    // From about 300 pt band width both details fit next to the name; otherwise better to omit them.
                    if sol != nil || sag != nil, width >= 300 {
                        HStack(spacing: 0) {
                            sol
                            Spacer(minLength: 8)
                            sag
                        }
                        .font(.system(size: max(9, min(12, height * 0.32)), weight: .medium))
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .environment(\.layoutDirection, .leftToRight)
                    }
                }
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
                .background {
                    Canvas { c, size in
                        var path = Path()
                        var x: CGFloat = -size.height
                        let step = max(5, size.height * 9 / 46)
                        while x < size.width {
                            path.move(to: CGPoint(x: x, y: size.height))
                            path.addLine(to: CGPoint(x: x + size.height, y: 0))
                            x += step
                        }
                        c.stroke(path, with: .color(color.opacity(0.12)), lineWidth: max(1.5, step / 3))
                    }
                }
                .overlay(alignment: .top) { Rectangle().fill(color).frame(height: 1.5) }
                .overlay(alignment: .bottom) { Rectangle().fill(color).frame(height: 1.5) }
            Arrowhead(sag: true).fill(color.opacity(0.85)).frame(width: uc)
        }
        .frame(height: height)
        .accessibilityElement(children: .combine)
    }

    /// Point at the end of the band, pointing outwards.
    private struct Arrowhead: Shape {
        let sag: Bool
        func path(in r: CGRect) -> Path {
            var p = Path()
            if sag {
                p.move(to: CGPoint(x: r.minX, y: r.minY))
                p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
                p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            } else {
                p.move(to: CGPoint(x: r.maxX, y: r.minY))
                p.addLine(to: CGPoint(x: r.minX, y: r.midY))
                p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            }
            p.closeSubpath()
            return p
        }
    }
}

struct SurahHeader: View {
    @Environment(\.theme) private var theme
    let surah: Surah
    /// iPad: name and count stand in the head of the column already.
    var bandOnly = false

    var body: some View {
        VStack(spacing: 8) {
            SurahBand(nameArabic: surah.nameArabic, height: 46)
            if !bandOnly {
                VStack(spacing: 2) {
                    Text(verbatim: surah.name(language: translationLanguage())).typography(.emphasized)
                    Text(
                        app: surahHeader(surah)
                    )
                    .typography(.footnote).foregroundStyle(theme.colors.text2)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, bandOnly ? 12 : 28)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// On the iPhone the reader is a page of its own; on the iPad its host draws background and title.
private struct ReaderChrome: ViewModifier {
    let isPad: Bool
    let title: String

    func body(content: Content) -> some View {
        if isPad {
            content
        } else {
            content.pageBackground().navigationTitle(title).smallTitle()
        }
    }
}
