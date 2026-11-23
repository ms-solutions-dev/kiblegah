import AVFoundation
import ContentPacks
import Core
import DesignSystem
import Duas
import Quran
import SwiftUI
import UserData

/// Dualar (D-list): search, dua of the day, favorites, categories.
struct DuasScreen: View {
    @Environment(\.contentProvider) private var contentProvider
    @Environment(AppSettings.self) private var settings
    @Environment(UserStore.self) private var store
    @Environment(\.theme) private var theme
    @State private var search = ""

    static let categories = ["rabbena", "peygamber", "aile", "ilim"]

    var body: some View {
        List {
            if let contentProvider {
                let tum = contentProvider.duas()
                if search.isEmpty {
                    if let g = DuaContent.ofTheDay(tum, day: .now) {
                        Section { DuaRow(dua: g, parent: localized("dua.gunun")) }
                    }
                    Section {
                        let _ = store.version
                        let fav = favorites(tum)
                        NavigationLink(value: Goal.duaList("favori")) {
                            // Smaller at AX sizes instead of „Favorile-/rim“.
                            Label {
                                Text(verbatim: localized("dua.favoriler \(fav.count)"))
                                    .lineLimit(1).minimumScaleFactor(0.6)
                            } icon: {
                                Image(systemName: fav.isEmpty ? "heart" : "heart.fill")
                            }
                        }
                        ForEach(Self.categories, id: \.self) { k in
                            NavigationLink(value: Goal.duaList(k)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: categoryName(k)).typography(.emphasized)
                                    Text(app: "dua.adet \(tum.filter { $0.category == k }.count)").typography(
                                        .footnote
                                    )
                                    .foregroundStyle(theme.colors.text2)
                                }
                            }
                        }
                    } header: {
                        Text(app: "dua.kategoriler")
                    } footer: {
                        if contentProvider.unreviewed("dualar") { Text(app: "dua.ungeprueft") }
                    }
                    // Sünnet duaları.
                    SlotView(.duasSection)
                } else {
                    let result = DuaContent.search(
                        search, tum, contentProvider,
                        pack: activeTranslations(contentProvider, settings).first?.id ?? "",
                        language: transliterationLanguage(settings))
                    if result.isEmpty {
                        Text(app: "dua.ara.yok").foregroundStyle(theme.colors.text2)
                    }
                    ForEach(result) { DuaRow(dua: $0, parent: nil) }
                }
            }
        }
        .alwaysSearchable($search, prompt: localized("dua.ara"))
        .navigationTitle(localized("sekme.dualar"))
    }

    private func favorites(_ tum: [Dua]) -> [Dua] { tum.filter { store.isSaved($0.key.text) } }
}

func categoryName(_ k: String) -> String {
    AppLanguage.bundle.localizedString(forKey: "dua.kategori.\(k)", value: k, table: nil)
}

/// One row: title from the beginning of the translation, source below.
struct DuaRow: View {
    @Environment(\.contentProvider) private var contentProvider
    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme
    let dua: Dua
    let parent: String?

    var body: some View {
        NavigationLink(value: Goal.dua(dua.slug)) {
            VStack(alignment: .leading, spacing: 4) {
                if let parent {
                    Text(verbatim: parent).typography(.footnote).textCase(.uppercase).foregroundStyle(
                        theme.colors.label)
                }
                if let contentProvider {
                    Text(
                        verbatim: DuaContent.transliteration(
                            dua, contentProvider, language: transliterationLanguage(settings)) ?? ""
                    ).typography(
                        .emphasized
                    )
                    .lineLimit(2)
                    Text(verbatim: duaSource(dua, contentProvider)).typography(.footnote).foregroundStyle(
                        theme.colors.text2)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

func duaSource(_ d: Dua, _ contentProvider: any ContentProvider) -> String {
    let name = contentProvider.surah(d.surah)?.name(language: translationLanguage()) ?? ""
    return d.first == d.end ? "\(name) \(d.surah):\(d.first)" : "\(name) \(d.surah):\(d.first)–\(d.end)"
}

/// List of a category or of the favorites (empty/filled).
struct DuaListScreen: View {
    @Environment(\.contentProvider) private var contentProvider
    @Environment(UserStore.self) private var store
    @Environment(\.theme) private var theme
    let category: String

    var body: some View {
        let _ = store.version
        let l = (contentProvider?.duas() ?? []).filter {
            category == "favori" ? store.isSaved($0.key.text) : $0.category == category
        }
        List {
            if l.isEmpty {
                Text(app: category == "favori" ? "dua.favori.bos" : "dua.ara.yok").foregroundStyle(
                    theme.colors.text2)
            }
            ForEach(l) { DuaRow(dua: $0, parent: nil) }
        }
        .navigationTitle(category == "favori" ? localized("dua.favoriler.baslik") : categoryName(category))
    }
}

/// Dua detail (D-Detay): Arabic, Okunuş, Anlam, source with jump into the reader,
/// listen to Okunuş and Anlam, favorite as a toggle with state, share via the card sheet.
struct DuaDetailScreen: View {
    @Environment(\.contentProvider) private var contentProvider
    @Environment(AppSettings.self) private var settings
    @Environment(UserStore.self) private var store
    @Environment(RecitationPlayer.self) private var player
    @Environment(\.theme) private var theme
    let slug: String
    @State private var settingOpen = false
    @State private var synthesizer = AVSpeechSynthesizer()

    var body: some View {
        if let contentProvider, let d = contentProvider.duas().first(where: { $0.slug == slug }) {
            let translation = activeTranslations(contentProvider, settings).first
            let meaning =
                translation.flatMap { DuaContent.translation(d, contentProvider, pack: $0.id) } ?? ""
            let transliteration =
                DuaContent.transliteration(d, contentProvider, language: transliterationLanguage(settings))
                ?? ""
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(verbatim: categoryName(d.category)).typography(.footnote).textCase(.uppercase)
                        .foregroundStyle(theme.colors.label)
                    Text(verbatim: DuaContent.arabic(d, contentProvider))
                        .typography(.arabic(size: settings.arabicSize))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    section(
                        "dua.okunusu", transliteration, size: max(16, settings.transliterationSize),
                        isItalic: false)
                    section("dua.anlami", meaning, size: settings.translationSize, isItalic: false)
                    NavigationLink(value: Goal.verse(.verse(surah: d.surah, verse: d.first))) {
                        Text(app: "dua.kaynak \(duaSource(d, contentProvider)) \(translation?.title ?? "")")
                            .typography(
                                .secondary
                            )
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if contentProvider.unreviewed("dualar") || contentProvider.unreviewed("okunus-tr") {
                        Text(app: "dua.ungeprueft").typography(.footnote).foregroundStyle(
                            theme.colors.warningText)
                    }
                    // „Kitaplarda“: citations from the dua books.
                    SlotView(.duaCitations(d.slug))
                    actions(
                        d, contentProvider: contentProvider, transliteration: transliteration,
                        meaning: meaning)
                }
                .padding(20)
            }
            .pageBackground()
            .safeAreaInset(edge: .bottom) { PlayerBar() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    let fav = store.isSaved(d.key.text)
                    Button {
                        store.toggleSaved(d.key.text)
                    } label: {
                        Image(systemName: fav ? "heart.fill" : "heart")
                    }
                    .accessibilityLabel(localized("dua.favori"))
                    .accessibilityValue(localized(fav ? "dua.favori.acik" : "dua.favori.kapali"))
                    .accessibilityAddTraits(fav ? .isSelected : [])
                }
                ToolbarItem(placement: .primaryAction) {
                    CollectionMenu(key: d.key).labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        settingOpen = true
                    } label: {
                        Image(systemName: "textformat.size")
                    }
                    .accessibilityLabel(localized("kuran.okuma_ayarlari"))
                }
            }
            .sheet(isPresented: $settingOpen) { ReadingSettings() }
            .onDisappear { synthesizer.stopSpeaking(at: .immediate) }
        } else {
            EmptyState(title: "dua.yok.baslik", explanation: "dua.yok.aciklama")
        }
    }

    private func section(
        _ title: LocalizedStringKey, _ text: String, size: Double, isItalic: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(app: title).typography(.footnote).textCase(.uppercase).foregroundStyle(theme.colors.label)
            Text(verbatim: text).font(.custom("Plus Jakarta Sans", size: size, relativeTo: .body)).italic(
                isItalic)
        }
    }

    private func actions(
        _ d: Dua, contentProvider: any ContentProvider, transliteration: String, meaning: String
    ) -> some View {
        VStack(spacing: 10) {
            Button {
                if let s = contentProvider.surah(d.surah) {
                    player.reciter = Reciter.find(settings.reciter)
                    player.play(surah: s.number, verseCount: s.verseCount, verse: d.first, end: d.end)
                }
            } label: {
                Label(localized("dua.okunusu_dinle"), systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButton())
            Button {
                if synthesizer.isSpeaking {
                    synthesizer.stopSpeaking(at: .immediate)
                } else {
                    let s = AVSpeechUtterance(string: meaning)
                    s.voice = AVSpeechSynthesisVoice(language: translationLanguage())
                    synthesizer.speak(s)
                }
            } label: {
                Label(localized("dua.anlami_dinle"), systemImage: "speaker.wave.2").frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButton())
            let translation = activeTranslations(contentProvider, settings).first?.title
            ShareButton(
                .dua(
                    arabic: DuaContent.arabic(d, contentProvider), meaning: meaning,
                    source: [duaSource(d, contentProvider), translation ?? ""].filter { !$0.isEmpty }.joined(
                        separator: " · "),
                    slug: d.slug),
                labeled: true
            )
            .buttonStyle(SecondaryButton())
        }
    }
}
