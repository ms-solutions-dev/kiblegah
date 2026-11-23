import ContentPacks
import Core
import DesignSystem
import Quran
import SwiftUI
import UserData

#if os(iOS)
    import UIKit
#endif

/// Verse sheet (Q-Ayet): translation and „Notum“ - only finished tabs; Kaydet, Paylaş, Kopyala.
///
/// Study place: at the bottom a bar pages to the previous/next verse or jumps to the
/// next verse with content in the open tab (hadith, own note, bookmarked). „Im
/// Zusammenhang lesen“ closes the sheet and scrolls the reader to the verse just shown.
struct VerseSheet: View {
    enum SheetTab: Hashable { case translation, tafsir, hadith, tajweed, note }

    @Environment(\.contentProvider) private var contentProvider
    @Environment(AppSettings.self) private var settings
    @Environment(UserStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var close
    @Environment(RecitationPlayer.self) private var player
    @Environment(\.plugins) private var plugins
    @State private var verse: Verse
    /// Scrolls the reader to this verse (or opens it if it is in a different surah).
    var readInContext: ((Verse) -> Void)? = nil
    /// Reports the verse shown, so the Mushaf above highlights it and pages along ().
    var changed: ((Verse) -> Void)? = nil
    @State private var reiter: SheetTab = {
        #if DEBUG
            // Screen test without tapping: `-ayetReiter tafsir`.
            if UserDefaults.standard.string(forKey: "ayetReiter") == "tefsir" { return .tafsir }
        #endif
        return .translation
    }()
    @State private var contextOpen = false
    @State private var similarOpen = false

    init(verse: Verse, changed: ((Verse) -> Void)? = nil, readInContext: ((Verse) -> Void)? = nil) {
        _verse = State(initialValue: verse)
        self.changed = changed
        self.readInContext = readInContext
    }
    @State private var note = ""
    @State private var copied = false
    @State private var options = false
    @State private var sharing: ShareCard?
    /// sunnah.com has hadiths for this verse.
    @State private var hasSunnah = false
    @State private var tafsirSource = GroupDefaults.d.string(forKey: "tefsir.kaynak") ?? "muhtasar"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(verbatim: verse.text)
                        .typography(.arabic(size: settings.arabicSize))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Picker(localized("kuran.ayet.reiter"), selection: $reiter) {
                        Text(app: "kuran.ayet.meal").tag(SheetTab.translation)
                        if !(contentProvider?.tafsir(verse.key, language: tafsirLanguage(settings)).isEmpty
                            ?? true)
                        {
                            Text(app: "kuran.ayet.tefsir").tag(SheetTab.tafsir)
                        }
                        if !(contentProvider?.verseHadiths(verse.key, language: translationLanguage()).isEmpty
                            ?? true) || hasSunnah
                        {
                            Text(app: "kuran.ayet.hadis").tag(SheetTab.hadith)
                        }
                        if !(contentProvider?.tajweed(verse.key).isEmpty ?? true) {
                            Text(app: "kuran.ayet.tecvid").tag(SheetTab.tajweed)
                        }
                        Text(app: "kuran.ayet.notum").tag(SheetTab.note)
                    }
                    .pickerStyle(.segmented)
                    .background {
                        SlotView(.verseHadithProbe("\(verse.surah):\(verse.verse)")).hidden()
                            .environment(\.verseHadithNotice, VerseHadithNotice { hasSunnah = $0 })
                    }
                    switch reiter {
                    case .translation: translation
                    case .tafsir: tafsir
                    case .hadith:
                        ForEach(
                            contentProvider?.verseHadiths(verse.key, language: translationLanguage()) ?? []
                        ) { h in
                            NavigationLink(value: Goal.hadithDetail(h.identifier)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(verbatim: h.title).typography(.emphasized).multilineTextAlignment(
                                        .leading)
                                    Text(verbatim: "\(h.source) · \(h.degrees)").typography(.footnote)
                                        .foregroundStyle(
                                            theme.colors.text2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(theme.colors.surface, in: .rect(cornerRadius: 16))
                            }
                            .buttonStyle(.plain)
                        }
                        SlotView(.verseHadiths("\(verse.surah):\(verse.verse)"))
                    case .tajweed:
                        let t = contentProvider?.tajweed(verse.key) ?? []
                        Text(tajweedText(verse.text, spans: t, dark: theme.colors.dark))
                            .typography(.arabic(size: settings.arabicSize))
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        TajweedLegend(
                            rules: TajweedColors.rules.filter { k in t.contains { $0.rule == k } })
                    case .note: noteEditor
                    }
                    actions
                }
                .padding(20)
            }
            .pageBackground()
            .navigationTitle(title)
            .smallTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(localized("genel.kapat")) { close() } }
            }
            .navigationDestination(for: Goal.self) { GoalScreen(goal: $0) }
            .safeAreaInset(edge: .bottom) { navBar }
            // Swiping horizontally pages like the arrows: left goes to the next verse ().
            .simultaneousGesture(
                DragGesture(minimumDistance: 30).onEnded { d in
                    let x = d.translation.width
                    guard abs(x) > 70, abs(x) > abs(d.translation.height) * 2 else { return }
                    withAnimation(.snappy) {
                        git(contentProvider?.key(index: verse.index + (x < 0 ? 1 : -1)))
                    }
                }
            )
            .onChange(of: verse.index, initial: true) { changed?(verse) }
            .onAppear { note = store.note(verse.key.text)?.metin ?? "" }
            .onDisappear { store.saveNote(verse.key.text, text: note) }
        }
        // The book reader from the tafsir tab hangs off the root of the sheet, not off the section ().
        .pluginWrapper()
        .presentationDetents([.medium, .large])
    }

    /// Change of the verse shown: save the note, load the new one, keep the tab if it exists.
    private func git(_ a: ContentKey?) {
        guard let a, let contentProvider, let yeni = contentProvider.verse(a), yeni.index != verse.index
        else { return }
        store.saveNote(verse.key.text, text: note)
        verse = yeni
        note = store.note(yeni.key.text)?.metin ?? ""
        contextOpen = false
        similarOpen = false
        if reiter == .tafsir && contentProvider.tafsir(yeni.key, language: tafsirLanguage(settings)).isEmpty {
            reiter = .translation
        }
        if reiter == .hadith
            && contentProvider.verseHadiths(yeni.key, language: translationLanguage()).isEmpty && !hasSunnah
        {
            reiter = .translation
        }
    }

    /// Next/previous verse with content of the open tab's kind; nil if the kind makes no sense
    /// (every verse has a translation, tafsir and usually tajweed).
    private func neighbor(backward: Bool) -> ContentKey? {
        guard let contentProvider else { return nil }
        switch reiter {
        case .hadith:
            return contentProvider.nearbyVerseWithHadith(verse.key, rest: backward)
        case .note:
            return neighborKey(store.notes(archived: false).map(\.anahtar), backward: backward)
        default:
            return neighborKey(store.saved().map(\.anahtar), backward: backward)
        }
    }

    private func neighborKey(_ keys: [String], backward: Bool) -> ContentKey? {
        guard let contentProvider else { return nil }
        let orderedKeys = keys.compactMap { ContentKey(text: $0) }.compactMap {
            contentProvider.verse(firstVerse($0))?.index
        }
        let goal =
            backward
            ? orderedKeys.filter { $0 < verse.index }.max() : orderedKeys.filter { $0 > verse.index }.min()
        return goal.flatMap { contentProvider.key(index: $0) }
    }

    private var neighborName: String {
        switch reiter {
        case .hadith: localized("kuran.ayet.sonraki.hadis")
        case .note: localized("kuran.ayet.sonraki.not")
        default: localized("kuran.ayet.sonraki.kayit")
        }
    }

    private var navBar: some View {
        let _ = store.version
        let advanced = neighbor(backward: false)
        let backward = neighbor(backward: true)
        return HStack(spacing: 4) {
            Button {
                git(contentProvider?.key(index: verse.index - 1))
            } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            .disabled(verse.index <= 1)
            .accessibilityLabel(localized("kuran.ayet.onceki"))
            Spacer(minLength: 0)
            Menu {
                Button(localized("kuran.ayet.onceki_icerik"), systemImage: "arrow.left.to.line") {
                    git(backward)
                }
                .disabled(backward == nil)
                Button(localized("kuran.ayet.sonraki_icerik"), systemImage: "arrow.right.to.line") {
                    git(advanced)
                }
                .disabled(advanced == nil)
            } label: {
                Label(neighborName, systemImage: "arrow.right.to.line").typography(.footnote).lineLimit(1)
            } primaryAction: {
                git(advanced)
            }
            .disabled(advanced == nil && backward == nil)
            // Hide completely when there is no target: a gray button looks broken.
            .opacity(advanced == nil && backward == nil ? 0 : 1)
            .accessibilityHidden(advanced == nil && backward == nil)
            Spacer(minLength: 0)
            Button {
                git(contentProvider?.key(index: verse.index + 1))
            } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }
            .disabled(verse.index >= 6236)
            .accessibilityLabel(localized("kuran.ayet.sonraki"))
        }
        .padding(.horizontal, 12)
        .background(.bar)
        .environment(\.layoutDirection, .leftToRight)
    }

    private var title: String {
        let name = contentProvider?.surah(verse.surah)?.name(language: translationLanguage()) ?? ""
        return "\(name) \(verse.surah):\(verse.verse)"
    }

    @ViewBuilder private var translation: some View {
        if let contentProvider {
            ForEach(activeTranslations(contentProvider, settings)) { m in
                if let text = contentProvider.translation(verse.key, pack: m.id) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: m.title).typography(.footnote).textCase(.uppercase).foregroundStyle(
                            theme.colors.label)
                        Text(verbatim: text.markedText).typography(.body)
                        TranslationFootnotes(notes: text.footnotes).padding(.top, 2)
                    }
                }
            }
            DisclosureGroup(localized("kuran.ayet.baglam"), isExpanded: $contextOpen) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach([verse.index - 2, verse.index - 1, verse.index + 1, verse.index + 2], id: \.self)
                    {
                        n in
                        if let a = contentProvider.key(index: n), case .verse(let su, let number) = a,
                            let m = activeTranslations(contentProvider, settings).first,
                            let t = contentProvider.translation(a, pack: m.id)
                        {
                            Button {
                                git(a)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: "\(su):\(number)").typography(.footnote).foregroundStyle(
                                        theme.colors.label)
                                    Text(verbatim: t.text).typography(.secondary).foregroundStyle(
                                        theme.colors.text2
                                    )
                                    .multilineTextAlignment(.leading)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            if n == verse.index - 1 {
                                Text(verbatim: "· · ·").typography(.footnote).foregroundStyle(
                                    theme.colors.accent
                                )
                                .frame(maxWidth: .infinity)
                                .accessibilityHidden(true)
                            }
                        }
                    }
                    if let readInContext {
                        Button(localized("kuran.ayet.baglamda_oku"), systemImage: "text.book.closed") {
                            store.saveNote(verse.key.text, text: note)
                            readInContext(verse)
                            close()
                        }
                    }
                }
                .padding(.top, 8)
            }
            .tint(theme.colors.accent)
            similar(contentProvider)
            Text(app: "kuran.ayet.meal_ipucu").typography(.footnote).foregroundStyle(theme.colors.text2)
            Text(app: "kuran.ayet.konum \(verse.page) \(verse.juz)").typography(.footnote).foregroundStyle(
                theme.colors.text2)
        }
    }

    /// Verses with identical wording (QUL Similar Ayah,): helps with memorization to tell
    /// similar passages apart. The match shows the matching words in color; a tap
    /// jumps there (the Mushaf above pages along).
    @ViewBuilder private func similar(_ contentProvider: any ContentProvider) -> some View {
        let list = Array(contentProvider.similarVerses(verse.key).prefix(6))
        if !list.isEmpty {
            DisclosureGroup(isExpanded: $similarOpen) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(list, id: \.self) { b in
                        if case .verse(let su, let number) = b.goal, let h = contentProvider.verse(b.goal) {
                            Button {
                                git(b.goal)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(
                                        verbatim:
                                            "\(contentProvider.surah(su)?.name(language: translationLanguage()) ?? "") \(su):\(number) · \(localized("kuran.ayet.benzer.kelime \(b.word)"))"
                                    )
                                    .typography(.footnote).foregroundStyle(theme.colors.label)
                                    Text(Self.marked(h.text, b.words, color: theme.colors.accent))
                                        .typography(.arabic(size: max(20, settings.arabicSize * 0.7)))
                                        .multilineTextAlignment(.trailing)
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text(app: "kuran.ayet.benzer.kaynak").typography(.footnote).foregroundStyle(
                        theme.colors.text2)
                }
                .padding(.top, 8)
            } label: {
                Text(app: "kuran.ayet.benzer \(list.count)")
            }
            .tint(theme.colors.accent)
        }
    }

    /// Colors the words `words` (1-based, space-separated) in the Arabic text.
    static func marked(_ text: String, _ words: [ClosedRange<Int>], color: Color) -> AttributedString {
        var result = AttributedString()
        for (i, k) in text.split(separator: " ").enumerated() {
            if i > 0 { result += AttributedString(" ") }
            var part = AttributedString(String(k))
            if words.contains(where: { $0.contains(i + 1) }) { part.foregroundColor = color }
            result += part
        }
        return result
    }

    /// Which tafsir: the bundled one (Muhtasar) or a further source a plugin provides.
    /// The choice stays saved.
    @ViewBuilder private var tafsir: some View {
        let extra = plugins.extraTafsirSources()
        if !extra.isEmpty {
            sourceChips(extra)
        }
        if tafsirSource != "muhtasar" && extra.contains(where: { $0.id == tafsirSource }) {
            SlotView(.verseSources(verse: verse.key.text, work: tafsirSource))
        } else if let contentProvider {
            ForEach(contentProvider.tafsir(verse.key, language: tafsirLanguage(settings)), id: \.self) { t in
                let m = contentProvider.packs.first { $0.id == t.pack }
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: m?.title ?? t.pack).typography(.footnote).textCase(.uppercase)
                        .foregroundStyle(
                            theme.colors.label)
                    Text(verbatim: t.text).font(
                        .custom("Plus Jakarta Sans", size: settings.translationSize, relativeTo: .body))
                    Text(verbatim: "\(m?.author ?? "") · \(m?.source ?? "")").typography(.footnote)
                        .foregroundStyle(
                            theme.colors.text2)
                }
            }
            if translationLanguage() == "de" {
                Text(app: tafsirLanguage(settings) == "tr" ? "kuran.tefsir.de.tr" : "kuran.tefsir.de")
                    .typography(
                        .footnote
                    ).foregroundStyle(theme.colors.text2)
            }
        }
    }

    /// Tafsir source as chips: tolerate long names and later sources;
    /// the choice stays saved under „tefsir.kaynak“.
    private func sourceChips(_ extra: [TafsirSource]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach([TafsirSource("muhtasar", nameKey: "kaynak.muhtasar")] + extra, id: \.id) { source in
                    let identifier = source.id
                    let name = source.nameKey
                    let selected = tafsirSource == identifier
                    Button {
                        tafsirSource = identifier
                        GroupDefaults.d.set(identifier, forKey: "tefsir.kaynak")
                    } label: {
                        Text(verbatim: localized(key: name))
                            .typography(.emphasized)
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .foregroundStyle(selected ? theme.colors.background : theme.colors.text)
                            .background(selected ? theme.colors.text : theme.colors.surface2, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .padding(.horizontal, -20)
        .accessibilityLabel(localized("kaynak.sec"))
    }

    @ViewBuilder private var noteEditor: some View {
        let existing = store.note(verse.key.text)
        TextEditor(text: $note)
            .frame(minHeight: 160)
            .padding(8)
            .scrollContentBackground(.hidden)
            .background(theme.colors.surface, in: .rect(cornerRadius: 16))
            .overlay(alignment: .topLeading) {
                if note.isEmpty {
                    Text(app: "kuran.notum.bos").typography(.body).foregroundStyle(theme.colors.text2)
                        .padding(.horizontal, 13).padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel(localized("kuran.ayet.notum"))
        HStack {
            Text(app: "kuran.notum.ipucu").typography(.footnote).foregroundStyle(theme.colors.text2)
            Spacer()
            if let existing {
                Button(existing.arsiv ? localized("kuran.notum.geri_al") : localized("kuran.notum.arsivle")) {
                    store.saveNote(verse.key.text, text: note)
                    store.archiveNote(verse.key.text, !existing.arsiv)
                }
            }
        }
        if case .verse(let s, let n) = verse.key {
            SlotView(.verseBookMarks(surah: s, verse: n))
        }
    }

    /// Actions like the iOS share sheet: each symbol with a word below it,
    /// horizontally swipeable, „Paylaş“ in the accent color at the front. The row runs to the edge
    /// of the sheet; VoiceOver reads the detailed names.
    private var actions: some View {
        let _ = store.version
        let stored = store.isSaved(verse.key.text)
        let memorizing = store.isMemorizing(verse.key.text)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                shareButton
                Button {
                    options = true
                } label: {
                    Label(localized("kuran.oynatici.dinle"), systemImage: "play.fill")
                        .labelStyle(ActionTile(word: localized("kuran.oynatici.dinle")))
                }
                SlotView(.verseAction(verse.key))
                Button {
                    store.toggleSaved(verse.key.text)
                } label: {
                    Label(
                        localized(stored ? "kuran.kaydedildi" : "kuran.kaydet"),
                        systemImage: stored ? "bookmark.fill" : "bookmark"
                    )
                    .labelStyle(
                        ActionTile(word: localized(stored ? "kuran.kaydedildi" : "kuran.kaydet")))
                }
                .accessibilityAddTraits(stored ? .isSelected : [])
                CollectionMenu(key: verse.key)
                    .labelStyle(ActionTile(word: localized("kuran.islem.koleksiyon")))
                Button {
                    store.addToMemorization(verse.key.text)
                } label: {
                    Label(
                        localized(memorizing ? "ezber.eklendi" : "ezber.ekle_kisa"),
                        systemImage: "brain.head.profile"
                    )
                    .labelStyle(
                        ActionTile(word: localized(memorizing ? "ezber.eklendi" : "kuran.islem.ezber")))
                }
                .disabled(memorizing)
                Button {
                    #if os(iOS)
                        UIPasteboard.general.string = shareText
                    #endif
                    copied = true
                } label: {
                    Label(
                        localized(copied ? "kuran.kopyalandi" : "kuran.kopyala"),
                        systemImage: "doc.on.doc"
                    )
                    .labelStyle(
                        ActionTile(word: localized(copied ? "kuran.kopyalandi" : "kuran.kopyala")))
                }
            }
            .buttonStyle(.plain)
        }
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .padding(.horizontal, -20)
        .sheet(isPresented: $options) { ReadingOptions(verse: verse) { close() } }
    }

    /// „Paylaş“ opens the share sheet with preview and style choice.
    private var shareButton: some View {
        Button {
            sharing = shareCard
        } label: {
            Label(localized("kuran.paylas"), systemImage: "square.and.arrow.up")
                .labelStyle(ActionTile(word: localized("kuran.paylas"), prominent: true))
        }
        .shareSheet($sharing)
    }

    /// 9:16 card with style choice; „Yalnız metin“ in the sheet replaces the old text link.
    private var shareCard: ShareCard {
        let translation = contentProvider.flatMap { b in activeTranslations(b, settings).first }
        let text =
            translation.flatMap { m in contentProvider?.translation(verse.key, pack: m.id)?.text } ?? ""
        guard case .verse(let s, let n) = verse.key else {
            return .verse(arabic: verse.text, translation: text, source: title, surah: 1, verse: 1)
        }
        return .verse(
            arabic: verse.text, translation: text, source: "\(title) · \(translation?.title ?? "")", surah: s,
            verse: n)
    }

    /// Text with source: Arabic, translation with name, location, app.
    private var shareText: String {
        guard let contentProvider else { return verse.text }
        let translation = activeTranslations(contentProvider, settings).first
        let text = translation.flatMap { contentProvider.translation(verse.key, pack: $0.id)?.text } ?? ""
        return "\(verse.text)\n\n\(text)\n— \(title) · \(translation?.title ?? "") · Kıblegâh"
    }
}

/// An entry in the action strip of the verse sheet: tile with symbol, the short word below it.
/// The tile of the promoted entry („Paylaş“) sits on the accent.
public struct ActionTile: LabelStyle {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var enabled
    let word: String
    var prominent = false

    public init(word: String, prominent: Bool = false) {
        self.word = word
        self.prominent = prominent
    }

    public func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 6) {
            configuration.icon
                .font(.system(size: 20, weight: .medium))
                .frame(width: 56, height: 56)
                .foregroundStyle(prominent ? theme.colors.onAccent : theme.colors.text)
                .background(
                    prominent ? theme.colors.accent : theme.colors.surface, in: .rect(cornerRadius: 16)
                )
                .overlay {
                    if !prominent {
                        RoundedRectangle(cornerRadius: 16).strokeBorder(theme.colors.line, lineWidth: 1)
                    }
                }
            Text(verbatim: word).typography(.footnote).fontWeight(.semibold)
                .lineLimit(2).multilineTextAlignment(.center)
                .foregroundStyle(theme.colors.text)
        }
        .frame(minWidth: 64, maxWidth: 84)
        .opacity(enabled ? 1 : 0.5)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel { _ in configuration.title }
    }
}
