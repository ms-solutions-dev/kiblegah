import ContentPacks
import Core
import DesignSystem
import Quran
import SwiftUI
import UserData

/// What a host gives the reader on the iPad: the selected verse lives in the host's detail column, and the
/// host wants to know the verse on top and can scroll the list.
struct PadReaderLink {
    var selection: Binding<Verse?>
    var visible: Binding<Int?>
    var jump: Binding<ContentKey?>
}

extension EnvironmentValues {
    /// The rounded verse rows of the iPad reader.
    @Entry var padReaderStyle = false
}

/// The Quran in verse mode (boards G07, G21). Columns follow the width of the page, not the device:
/// directory | reader | detail when there is room, otherwise the directory as a popover or a drawer and the
/// detail as a card above the player.
struct PadQuranScreen: View {
    @Environment(\.contentProvider) private var contentProvider
    @Environment(AppSettings.self) private var settings
    @Environment(UserStore.self) private var store
    @Environment(Router.self) private var direction
    @Environment(RecitationPlayer.self) private var player
    @Environment(AudioStore.self) private var audioStore
    @Environment(\.theme) private var theme
    @Environment(\.padWindow) private var window

    var start: ContentKey?
    /// Start in the full screen book (Mushaf links, „Mushaf'ta aç“).
    var opensBook = false

    @State private var selection: Verse?
    @State private var visible: Int?
    @State private var jump: ContentKey?
    @State private var page = CGSize.zero
    @State private var directoryOpen = false
    @State private var aaOpen = false
    @State private var settingsOpen = false
    @State private var readingVerse: Verse?
    @State private var bookOpen = false
    @State private var bookPage = 1
    @State private var bookShownOnce = false

    private var tall: Bool { window.height > window.width }
    private var showsDirectory: Bool { page.width >= 1100 }
    private var showsDetail: Bool { page.width >= 860 && !tall }
    /// The system bar on top is taken by the tabs in portrait and with a folded sidebar: then the controls
    /// get a row of their own (G21).
    private var bandsOwnRow: Bool { tall || page.width >= window.width - 1 }

    /// The start: an explicit target, otherwise the last reading position.
    private var entry: ContentKey {
        if let start { return start }
        return (store.lastPosition(khatm: settings.activeKhatm) ?? store.lastPosition())
            .flatMap { ContentKey(text: $0) } ?? .verse(surah: 1, verse: 1)
    }

    private var currentVerse: Verse? {
        guard let contentProvider else { return nil }
        if let visible, let k = contentProvider.key(index: visible) { return contentProvider.verse(k) }
        return contentProvider.verse(firstVerse(entry))
    }

    private var currentSurah: Surah? {
        guard let contentProvider, let v = currentVerse else { return nil }
        return contentProvider.surah(v.surah)
    }

    private var surahName: String {
        currentSurah?.name(language: translationLanguage()) ?? ""
    }

    var body: some View {
        columns
            .onGeometryChange(for: CGSize.self, of: \.size) { page = $0 }
            .pageBackground()
            .navigationTitle(surahName)
            .smallTitle()
            .toolbar { if !bandsOwnRow { toolbarContent } }
            .safeAreaInset(edge: .top, spacing: 0) {
                if bandsOwnRow { ownRow }
            }
            .sheet(item: $readingVerse) { ReadingOptions(verse: $0) }
            .sheet(isPresented: $settingsOpen) { ReadingSettings() }
            #if os(iOS)
                .fullScreenCover(isPresented: $bookOpen) {
                    PadBookScreen(start: bookPage) { key in
                        if let key { jump = key }
                    }
                }
            #endif
            .onChange(of: direction.padQuranJump) { _, k in
                if let k {
                    jump = k
                    direction.padQuranJump = nil
                }
            }
            .onAppear {
                if let k = direction.padQuranJump {
                    jump = k
                    direction.padQuranJump = nil
                }
                if opensBook, !bookShownOnce {
                    bookShownOnce = true
                    openBook()
                }
                #if DEBUG
                    openDebugState()
                #endif
            }
            .overlay {
                if tall, directoryOpen { drawer }
            }
    }

    #if DEBUG
        /// Screenshots: `-ipadVers` selects the verse on top, `-ipadAa`, `-ipadVerzeichnis` open their panels.
        private func openDebugState() {
            let d = UserDefaults.standard
            if d.bool(forKey: "ipadVers"), let v = currentVerse { selection = v }
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                if d.bool(forKey: "ipadAa") { aaOpen = true }
                if d.bool(forKey: "ipadVerzeichnis") { directoryOpen = true }
            }
        }
    #endif

    private var columns: some View {
        HStack(spacing: 14) {
            if showsDirectory {
                PadQuranDirectory(current: currentVerse) { jump = $0 }
                    .frame(width: 236)
                    .background(theme.colors.surface, in: .rect(cornerRadius: 28))
                    .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(theme.colors.line))
                    .clipShape(.rect(cornerRadius: 28))
                    .padShadow(theme)
            }
            readerColumn
            if showsDetail, let selection {
                detail(selection)
                    .frame(width: 322)
                    .background(theme.colors.surface, in: .rect(cornerRadius: 28))
                    .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(theme.colors.line))
                    .clipShape(.rect(cornerRadius: 28))
                    .padShadow(theme)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, tall ? 0 : 14)
        .padding(.bottom, tall ? 0 : 14)
        .animation(.timingCurve(0.3, 0.9, 0.3, 1, duration: 0.45), value: selection?.index)
    }

    /// The paper only colors the reader; the chrome around it keeps the app's colors.
    private var readerColumn: some View {
        let paper = ReadingPaper(setting: settings.readingPaper)
        let tokens = paper.tokens(base: theme.colors)
        let paperTheme = Theme(colors: tokens, largeAndSimple: theme.largeAndSimple, force: theme.force)
        return VStack(spacing: 0) {
            if !tall { readerHeader(tokens) }
            ReaderScreen(
                start: entry,
                pad: PadReaderLink(selection: $selection, visible: $visible, jump: $jump)
            )
            .id(start?.text ?? "start")
            .environment(\.padReaderStyle, true)
        }
        .environment(\.theme, paperTheme)
        .foregroundStyle(tokens.text)
        .background(tokens.background)
        .overlay(alignment: .bottom) { bottomOverlay }
        .clipShape(.rect(cornerRadius: tall ? 0 : 28))
        .overlay {
            if !tall {
                RoundedRectangle(cornerRadius: 28).strokeBorder(theme.colors.line)
            }
        }
        .shadow(color: .black.opacity(tall || theme.colors.dark ? 0 : 0.08), radius: 12, y: 6)
    }

    /// Name, verse count, page and translation on top of the column (G07).
    private func readerHeader(_ tokens: ColorTokens) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: surahName).typography(.display(size: 22))
                if let s = currentSurah, let v = currentVerse {
                    Text(app: "ipad.koran.kopf \(s.number) \(s.verseCount) \(v.page) \(v.juz)")
                        .typography(.footnote).opacity(0.75)
                        .contentTransition(.numericText())
                }
            }
            Spacer(minLength: 8)
            if let contentProvider {
                Text(
                    verbatim: localized(
                        "ipad.koran.meal \(activeTranslations(contentProvider, settings).map(\.title).joined(separator: ", "))"
                    )
                )
                .typography(.label(size: 14)).lineLimit(1).minimumScaleFactor(0.7)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(tokens.surface2, in: .capsule)
                .foregroundStyle(tokens.text2)
            }
        }
        .padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(tokens.line).frame(height: 1) }
    }

    /// The player or „hören“, and in portrait the detail above it (G21).
    @ViewBuilder private var bottomOverlay: some View {
        VStack(spacing: 8) {
            if !showsDetail, let selection {
                detail(selection)
                    .frame(maxHeight: tall ? 620 : 420)
                    .glassEffect(.regular, in: .rect(cornerRadius: 30))
                    .clipShape(.rect(cornerRadius: 30))
                    .shadow(color: .black.opacity(0.18), radius: 20, y: 10)
                    .padding(.horizontal, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if player.isActive {
                PadPlayerBar(width: nil)
            } else if let v = currentVerse {
                PadListenCapsule(title: localized("ipad.koran.hoeren \(surahName)")) { readingVerse = v }
            }
        }
        .environment(\.theme, theme)
    }

    private func detail(_ verse: Verse) -> some View {
        VerseSheet(
            verse: verse, embedded: true, closeEmbedded: { selection = nil },
            changed: { y in
                // A tap in the list stays where it is; paging in the detail takes the list along.
                if selection?.index != y.index {
                    selection = y
                    jump = y.key
                }
            },
            readInContext: { jump = $0.key })
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: Self.leadingPlacement) {
            if !showsDirectory { directoryButton }
        }
        ToolbarItem(placement: .principal) {
            modeSwitch
        }
        ToolbarItemGroup(placement: Self.trailingPlacement) {
            PrayerBand(style: .chip)
            bookButton
            aaButton
            moreMenu
        }
    }

    #if os(iOS)
        private static let leadingPlacement = ToolbarItemPlacement.topBarLeading
        private static let trailingPlacement = ToolbarItemPlacement.topBarTrailing
    #else
        private static let leadingPlacement = ToolbarItemPlacement.automatic
        private static let trailingPlacement = ToolbarItemPlacement.automatic
    #endif

    /// The same controls in a row of their own below the system bar (G21).
    private var ownRow: some View {
        HStack(spacing: 10) {
            if !showsDirectory {
                directoryButton
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10).frame(minHeight: 44)
                    .background(theme.colors.surface2, in: .capsule)
            }
            Spacer(minLength: 4)
            modeSwitch
            Spacer(minLength: 4)
            PrayerBand(style: .chip)
            bookButton.buttonStyle(.plain).padding(.horizontal, 10).frame(minWidth: 44, minHeight: 44)
                .background(theme.colors.surface2, in: .circle)
            aaButton.buttonStyle(.plain).frame(minWidth: 44, minHeight: 44)
                .background(theme.colors.surface2, in: .circle)
            moreMenu.buttonStyle(.plain).frame(minWidth: 44, minHeight: 44)
                .background(theme.colors.surface2, in: .circle)
        }
        .padding(.horizontal, 28).padding(.vertical, 6)
        .foregroundStyle(theme.colors.text)
        .overlay(alignment: .bottom) {
            if tall { Rectangle().fill(theme.colors.line).frame(height: 1) }
        }
        .background(theme.colors.background)
    }

    private var directoryButton: some View {
        Button {
            directoryOpen.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "text.justify.left")
                Text(verbatim: surahName).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption.weight(.semibold))
            }
            .typography(.label(size: 15))
            .foregroundStyle(theme.colors.text)
            .padding(.horizontal, 6)
        }
        .accessibilityLabel(localized("ipad.koran.verzeichnis"))
        .popover(isPresented: Binding(get: { directoryOpen && !tall }, set: { directoryOpen = $0 })) {
            PadQuranDirectory(current: currentVerse) {
                jump = $0
                directoryOpen = false
            }
            .frame(width: 320, height: 560)
            .presentationCompactAdaptation(.popover)
        }
    }

    private var bookButton: some View {
        Button {
            openBook()
        } label: {
            Image(systemName: "book.pages").foregroundStyle(theme.colors.text)
        }
        .accessibilityLabel(localized("kuran.mushaf"))
    }

    private var aaButton: some View {
        Button {
            aaOpen.toggle()
        } label: {
            Text(verbatim: "Aa").typography(.display(size: 17)).foregroundStyle(theme.colors.text)
        }
        .accessibilityLabel(localized("kuran.okuma_ayarlari"))
        .popover(isPresented: $aaOpen) {
            PadAaPopover { settingsOpen = true }
        }
    }

    /// „Vers | Seite“: Seite is the full screen book.
    private var modeSwitch: some View {
        HStack(spacing: 0) {
            Text(app: "ipad.koran.vers").typography(.label(size: 15))
                .padding(.horizontal, 18).frame(minHeight: 44)
                .background(theme.colors.surface, in: .capsule)
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                .accessibilityAddTraits(.isSelected)
            Button {
                openBook()
            } label: {
                Text(app: "ipad.koran.seite").typography(.label(size: 15))
                    .foregroundStyle(theme.colors.text2)
                    .padding(.horizontal, 18).frame(minHeight: 44)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
        }
        .padding(4)
        .background(theme.colors.surface2, in: .capsule)
    }

    /// What the iPhone reader keeps in its menu.
    private var moreMenu: some View {
        Menu {
            if let contentProvider, let v = currentVerse, let k = contentProvider.key(index: v.index) {
                SlotView(.verseMenuAction(k))
            }
            if let s = currentSurah { downloadButton(s) }
            NavigationLink(value: Goal.downloaded) {
                Label(localized("kuran.indirilenler"), systemImage: "arrow.down.circle")
            }
            NavigationLink(value: Goal.readingGoals) {
                Label(localized("ipad.koran.ziele"), systemImage: "target")
            }
            NavigationLink(value: Goal.memorization) {
                Label(localized("ezber.baslik"), systemImage: "brain.head.profile")
            }
            Button {
                settingsOpen = true
            } label: {
                Label(localized("kuran.okuma_ayarlari"), systemImage: "textformat.size")
            }
        } label: {
            Image(systemName: "ellipsis").foregroundStyle(theme.colors.text)
        }
        .accessibilityLabel(localized("kuran.daha_fazla"))
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

    private func openBook() {
        bookPage = currentVerse?.page ?? 1
        bookOpen = true
    }

    /// Portrait: the directory slides in from the left over a dimmed page (G21).
    private var drawer: some View {
        ZStack(alignment: .leading) {
            theme.colors.scrim.opacity(0.42).ignoresSafeArea()
                .onTapGesture { directoryOpen = false }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(localized("genel.kapat"))
            PadQuranDirectory(current: currentVerse) {
                jump = $0
                directoryOpen = false
            }
            .frame(width: 310)
            .background(theme.colors.surface, in: .rect(cornerRadius: 30))
            .clipShape(.rect(cornerRadius: 30))
            .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
            .padding(12)
            .transition(.move(edge: .leading))
        }
        .transition(.opacity)
    }
}

/// The directory (G07, G21): search, Sure / Cüz / Seiten / Gemerkt, continue reading and the reading links.
struct PadQuranDirectory: View {
    enum Mode: Hashable { case surah, juz, pages, saved }

    @Environment(\.contentProvider) private var contentProvider
    @Environment(UserStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme
    let current: Verse?
    let pick: (ContentKey) -> Void

    @State private var mode: Mode = .surah
    @State private var search = ""
    @State private var revelationOrder = GroupDefaults.d.bool(forKey: "kuranNuzulSirasi")
    @State private var savedByDate = GroupDefaults.d.bool(forKey: "kuranKayitTarihe")

    var body: some View {
        let _ = store.version
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(theme.colors.text2)
                        .accessibilityHidden(true)
                    TextField(localized("kuran.ara"), text: $search)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 14).frame(minHeight: 44)
                .background(theme.colors.surface2, in: .rect(cornerRadius: 14))
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)],
                    spacing: 4
                ) {
                    chip(.surah, "kuran.sure")
                    chip(.juz, "kuran.cuz")
                    chip(.pages, "ipad.koran.seiten")
                    chip(.saved, "kuran.kaydedilen")
                }
            }
            .padding([.horizontal, .top], 14).padding(.bottom, 6)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if let contentProvider {
                            if !search.isEmpty {
                                searchResult(contentProvider)
                            } else {
                                continueRow(contentProvider)
                                switch mode {
                                case .surah: surahs(contentProvider)
                                case .juz: juzRows(contentProvider)
                                case .pages: pages(contentProvider)
                                case .saved: saved(contentProvider)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8).padding(.bottom, 12)
                }
                .onAppear {
                    if let s = current?.surah, mode == .surah { proxy.scrollTo(s, anchor: .center) }
                }
            }
        }
        .foregroundStyle(theme.colors.text)
    }

    private func chip(_ m: Mode, _ key: String.LocalizationValue) -> some View {
        Button {
            mode = m
        } label: {
            Text(verbatim: localized(key)).typography(.label(size: 13))
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(mode == m ? theme.colors.onAccent : theme.colors.text2)
                .background(mode == m ? theme.colors.accent : theme.colors.surface2, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(mode == m ? .isSelected : [])
    }

    @ViewBuilder private func continueRow(_ contentProvider: any ContentProvider) -> some View {
        let last = (store.lastPosition(khatm: settings.activeKhatm) ?? store.lastPosition()).flatMap {
            ContentKey(text: $0)
        }
        if let last, case .verse(let s, let n) = last, let su = contentProvider.surah(s) {
            Button {
                pick(last)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(app: "kuran.kaldigin_yer").typography(.label(size: 10)).textCase(.uppercase)
                        .tracking(0.9).foregroundStyle(theme.colors.label)
                    Text(verbatim: "\(su.name(language: translationLanguage())) · \(s):\(n)")
                        .typography(.label(size: 16))
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(theme.colors.accent.opacity(0.14), in: .rect(cornerRadius: 16))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
        }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(QuranScreen.quickPicks, id: \.1) { name, a in
                    Button {
                        pick(a)
                    } label: {
                        Text(app: name).typography(.label(size: 13))
                            .padding(.horizontal, 12).frame(minHeight: 44)
                            .background(theme.colors.surface2, in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder private func surahs(_ contentProvider: any ContentProvider) -> some View {
        let list = contentProvider.surahs()
        Menu {
            Picker(localized("kuran.siralama"), selection: $revelationOrder) {
                Text(app: "kuran.siralama.mushaf").tag(false)
                Text(app: "kuran.siralama.nuzul").tag(true)
            }
        } label: {
            Label {
                Text(app: revelationOrder ? "kuran.siralama.nuzul" : "kuran.siralama.mushaf")
            } icon: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .typography(.footnote).foregroundStyle(theme.colors.text2)
            .frame(minHeight: 44)
        }
        .padding(.horizontal, 6)
        .onChange(of: revelationOrder) { _, n in GroupDefaults.d.set(n, forKey: "kuranNuzulSirasi") }
        ForEach(revelationOrder ? list.sorted { $0.revelationOrder < $1.revelationOrder } : list) { s in
            row(
                number: revelationOrder ? s.revelationOrder : s.number,
                title: s.name(language: translationLanguage()),
                arabic: s.nameArabic, on: current?.surah == s.number
            ) { pick(.verse(surah: s.number, verse: 1)) }
            .id(s.number)
        }
    }

    @ViewBuilder private func juzRows(_ contentProvider: any ContentProvider) -> some View {
        ForEach(1...30, id: \.self) { n in
            let first = contentProvider.juz(n).flatMap { contentProvider.key(index: $0.firstIndex) }
            let name: String = {
                if case .verse(let s, let a)? = first, let su = contentProvider.surah(s) {
                    return "\(su.name(language: translationLanguage())) \(a)"
                }
                return ""
            }()
            row(number: n, title: localized("kuran.cuz.no \(n)"), sub: name, on: current?.juz == n) {
                pick(.juz(n))
            }
        }
    }

    @ViewBuilder private func pages(_ contentProvider: any ContentProvider) -> some View {
        ForEach(1...604, id: \.self) { n in
            row(number: n, title: localized("kuran.sayfa.kisa \(n)"), on: current?.page == n) {
                if let p = contentProvider.page(n), let k = contentProvider.key(index: p.firstIndex) {
                    pick(k)
                }
            }
        }
    }

    @ViewBuilder private func saved(_ contentProvider: any ContentProvider) -> some View {
        let items: [(ContentKey, Int, Int, Date)] = store.saved().compactMap { k in
            guard let a = ContentKey(text: k.anahtar), case .verse(let s, let n) = a else { return nil }
            return (a, s, n, k.tarih)
        }
        if items.isEmpty {
            Text(app: "kuran.kaydedilen.bos").typography(.secondary).foregroundStyle(theme.colors.text2)
                .padding(14)
        } else {
            Menu {
                Picker(localized("kuran.siralama"), selection: $savedByDate) {
                    Text(app: "kuran.kaydedilen.sureye_gore").tag(false)
                    Text(app: "kuran.kaydedilen.tarihe_gore").tag(true)
                }
            } label: {
                Label {
                    Text(app: savedByDate ? "kuran.kaydedilen.tarihe_gore" : "kuran.kaydedilen.sureye_gore")
                } icon: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .typography(.footnote).foregroundStyle(theme.colors.text2)
                .frame(minHeight: 44)
            }
            .padding(.horizontal, 6)
            .onChange(of: savedByDate) { _, v in GroupDefaults.d.set(v, forKey: "kuranKayitTarihe") }
        }
        ForEach(SavedGroup.grouped(items, byDate: savedByDate)) { g in
            ForEach(g.items, id: \.0) { a, s, n, _ in
                row(
                    number: n,
                    title: contentProvider.surah(s)?.name(language: translationLanguage()) ?? "\(s)",
                    sub: "\(s):\(n)", on: false
                ) { pick(a) }
                .contextMenu {
                    Button(localized("kuran.indirilenler.sil"), systemImage: "trash", role: .destructive) {
                        store.toggleSaved(a.text)
                    }
                }
            }
        }
    }

    /// „2:255“ jumps, otherwise surah names; the meaning search of the verses has its own page.
    @ViewBuilder private func searchResult(_ contentProvider: any ContentProvider) -> some View {
        let numbers = search.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        if numbers.count >= 2, contentProvider.verse(.verse(surah: numbers[0], verse: numbers[1])) != nil {
            row(number: numbers[0], title: localized("kuran.ara.git \(numbers[0]) \(numbers[1])"), on: false)
            {
                pick(.verse(surah: numbers[0], verse: numbers[1]))
            }
        }
        let k = TurkishText.searchForm(search)
        ForEach(
            contentProvider.surahs().filter { s in
                (numbers.count == 1 && s.number == numbers[0])
                    || [s.nameTurkish, s.nameLatin, s.meaningEnglish].contains {
                        TurkishText.searchForm($0).contains(k)
                    }
            }
        ) { s in
            row(
                number: s.number, title: s.name(language: translationLanguage()), arabic: s.nameArabic,
                on: false
            ) {
                pick(.verse(surah: s.number, verse: 1))
            }
        }
        NavigationLink(value: Goal.searchQuery(search)) {
            Label(localized("ipad.koran.in_versen_suchen"), systemImage: "text.magnifyingglass")
                .typography(.emphasized).foregroundStyle(theme.colors.accent)
                .frame(minHeight: 44)
                .padding(.horizontal, 14)
        }
        .buttonStyle(.plain)
    }

    private func row(
        number: Int, title: String, sub: String? = nil, arabic: String? = nil, on: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(verbatim: "\(number)").typography(.display(size: 15)).monospacedDigit()
                    .frame(minWidth: 30, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title).typography(.label(size: 15)).lineLimit(1).minimumScaleFactor(0.8)
                    if let sub {
                        Text(verbatim: sub).typography(.footnote).foregroundStyle(theme.colors.text2)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if let arabic {
                    Text(verbatim: arabic).typography(.arabic(size: 19)).lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(on ? theme.colors.accent.opacity(0.14) : .clear, in: .rect(cornerRadius: 16))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// „Aa“ (G07): reading display, live at the text. The same button in verse mode and in the book.
struct PadAaPopover: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme
    /// In the book only the things that change the page make sense.
    var forBook = false
    let openAll: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var editionOpen = false

    var body: some View {
        @Bindable var a = settings
        VStack(alignment: .leading, spacing: 10) {
            Text(app: "ipad.aa.titel").typography(.display(size: 20))
            Text(app: "ipad.aa.papier").typography(.label(size: 13)).textCase(.uppercase).tracking(1.1)
                .foregroundStyle(theme.colors.label)
            HStack(spacing: 8) {
                ForEach(ReadingPaper.allCases, id: \.self) { p in
                    paperButton(p)
                }
            }
            if !forBook {
                sizeRow("ipad.aa.arabisch", value: $a.arabicSize, range: 20...56)
                sizeRow("ipad.aa.meal", value: $a.translationSize, range: 12...30)
                Toggle(localized("ipad.aa.meal_an"), isOn: $a.showTranslationInReader).frame(minHeight: 44)
            }
            Toggle(
                localized("ipad.aa.transkription"),
                isOn: forBook ? $a.bookTranscription : $a.showTransliteration
            )
            .frame(minHeight: 44)
            if forBook, settings.bookTranscription {
                Text(app: "ipad.aa.transkription.hinweis").typography(.footnote).foregroundStyle(
                    theme.colors.text2)
            }
            if forBook {
                // Tajweed in the book is an edition of the Mushaf (V4), not a switch.
                Button {
                    editionOpen = true
                } label: {
                    HStack {
                        Text(app: "mushaf.fassung.baslik")
                        Spacer()
                        Text(app: MushafPicker.shortName(MushafEdition(setting: settings.mushafEdition)))
                            .foregroundStyle(theme.colors.text2)
                        Image(systemName: "chevron.right").font(.footnote.weight(.bold))
                            .foregroundStyle(theme.colors.text2).accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            } else {
                Toggle(localized("kuran.tecvid.goster"), isOn: $a.tajweedColors).frame(minHeight: 44)
                Toggle(localized("kuran.kelime.goster"), isOn: $a.wordByWord).frame(minHeight: 44)
            }
            Picker(localized("kuran.kari"), selection: $a.reciter) {
                ForEach(Reciter.all.filter { $0.fullSurah == nil || SurahTimings.isAvailable() }) { k in
                    Text(verbatim: "\(k.name) · \(k.qiraat ?? k.style)").tag(k.id)
                }
            }
            .frame(minHeight: 44)
            Button {
                dismiss()
                openAll()
            } label: {
                HStack {
                    Text(app: "ipad.aa.alle")
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.bold)).accessibilityHidden(true)
                }
                .typography(.label(size: 15)).foregroundStyle(theme.colors.accent)
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .tint(theme.colors.accent)
        .padding(20)
        .frame(width: 360)
        .foregroundStyle(theme.colors.text)
        .presentationCompactAdaptation(.popover)
        .sheet(isPresented: $editionOpen) {
            NavigationStack { MushafPicker() }
        }
    }

    private func paperButton(_ p: ReadingPaper) -> some View {
        let on = ReadingPaper(setting: settings.readingPaper) == p
        let tokens = p.tokens(base: theme.colors)
        return Button {
            settings.readingPaper = p.rawValue
        } label: {
            Text(verbatim: localized(key: "ipad.papier.\(p.rawValue)"))
                .typography(.label(size: 11))
                .lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(tokens.text)
                .padding(.horizontal, 2)
                .frame(width: 60, height: 44)
                .background(tokens.background, in: .rect(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(on ? theme.colors.accent : theme.colors.line, lineWidth: 2)
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localized(key: "ipad.papier.\(p.rawValue)"))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func sizeRow(
        _ key: String.LocalizationValue, value: Binding<Double>, range: ClosedRange<Double>
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(verbatim: localized(key)).typography(.label(size: 15))
                Spacer()
                Text(verbatim: "\(Int(value.wrappedValue))").monospacedDigit().typography(.label(size: 15))
            }
            Slider(value: value, in: range, step: 1).accessibilityLabel(localized(key))
        }
    }
}
