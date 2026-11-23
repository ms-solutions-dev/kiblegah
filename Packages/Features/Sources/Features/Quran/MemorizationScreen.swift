import ContentPacks
import Core
import DesignSystem
import Quran
import SwiftUI
import UserData

/// Memorization: cards with a review schedule; due ones first.
struct MemorizationScreen: View {
    @Environment(\.contentProvider) private var contentProvider
    @Environment(UserStore.self) private var store
    @Environment(\.theme) private var theme
    @State private var addOpen = false

    var body: some View {
        let _ = store.version
        let cards = store.memorizationCards()
        let due = cards.filter { MemorizationScheduler.isDue($0.sonraki) }
        List {
            if cards.isEmpty {
                Text(app: "ezber.bos").foregroundStyle(theme.colors.text2)
            }
            if !due.isEmpty {
                Section {
                    ForEach(due, id: \.anahtar) { row($0) }
                } header: {
                    Text(app: "ezber.bugun \(due.count)")
                }
            }
            let after = cards.filter { !MemorizationScheduler.isDue($0.sonraki) }
            if !after.isEmpty {
                Section {
                    ForEach(after, id: \.anahtar) { row($0) }
                } header: {
                    Text(app: "ezber.sonra")
                }
            }
            Section {
                Button(localized("ezber.ekle"), systemImage: "plus") { addOpen = true }
            } footer: {
                Text(app: "ezber.aciklama")
            }
        }
        .navigationTitle(localized("ezber.baslik"))
        .sheet(isPresented: $addOpen) { AddToMemorization() }
    }

    private func row(_ k: EzberKarti) -> some View {
        NavigationLink(value: Goal.memorizationPractice(k.anahtar)) {
            VStack(alignment: .leading, spacing: 3) {
                Text(
                    verbatim: contentProvider.flatMap { b in
                        ContentKey(text: k.anahtar).map { verseName($0, b) }
                    }
                        ?? k.anahtar
                )
                .typography(.emphasized)
                Text(
                    verbatim: k.tekrar == 0 && k.aralik == 0
                        ? localized("ezber.yeni")
                        : localized(
                            "ezber.sonraki \(k.sonraki.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(AppLanguage.locale)))"
                        )
                )
                .typography(.footnote).foregroundStyle(theme.colors.text2)
            }
        }
        .swipeActions {
            Button(localized("kuran.indirilenler.sil"), role: .destructive) {
                store.removeFromMemorization(k)
            }
        }
    }
}

/// New card: surah and verse range (at most 20 verses per card).
private struct AddToMemorization: View {
    @Environment(\.contentProvider) private var contentProvider
    @Environment(UserStore.self) private var store
    @Environment(\.dismiss) private var close
    @State private var surah = 1
    @State private var first = 1
    @State private var end = 7

    var body: some View {
        NavigationStack {
            Form {
                let surahs = contentProvider?.surahs() ?? []
                Picker(localized("kuran.sure"), selection: $surah) {
                    ForEach(surahs) { s in
                        Text(verbatim: "\(s.number). \(s.name(language: translationLanguage()))").tag(
                            s.number)
                    }
                }
                let n = surahs.first { $0.number == surah }?.verseCount ?? 1
                Stepper(value: $first, in: 1...n) { Text(app: "ezber.ilk \(first)") }
                Stepper(value: $end, in: first...min(n, first + 19)) { Text(app: "ezber.son \(end)") }
            }
            .onChange(of: surah) { _, s in
                let n = contentProvider?.surah(s)?.verseCount ?? 1
                first = 1
                end = min(n, 5)
            }
            .onChange(of: first) { _, i in
                let n = contentProvider?.surah(surah)?.verseCount ?? 1
                end = min(max(end, i), min(n, i + 19))
            }
            .navigationTitle(localized("ezber.ekle"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(localized("genel.vazgec")) { close() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("koleksiyon.olustur")) {
                        store.addToMemorization(
                            first == end ? "a:\(surah):\(first)" : "a:\(surah):\(first)-\(end)")
                        close()
                    }
                }
            }
        }
    }
}

/// Practice (variant 09, both): words hidden, only initial letters, or open; reveal each word
/// individually. Two layouts to switch between in the toolbar, the choice persists:
/// A „alt“ with a fixed rating bar above the tab bar, B „deste“ as a card to swipe.
///
/// A session runs through all cards due today, starting with the tapped one; at the top
/// there is „1 / 3 bugün“ with a bar. If the tapped card is not due, only it is practiced.
struct MemorizationPracticeScreen: View {
    enum Mode: Hashable { case hidden, firstLetter, light }

    @Environment(\.contentProvider) private var contentProvider
    @Environment(UserStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(RecitationPlayer.self) private var player
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var close
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    let key: String
    @AppStorage(MemorizationLayout.key, store: GroupDefaults.d) private var layout: MemorizationLayout =
        .bottom
    @State private var appearance: Mode = .firstLetter
    @State private var expanded: Set<String> = []
    @State private var index: [String] = []
    @State private var cursor = 0
    @State private var dragOffset: CGSize = .zero
    @State private var scrollable = false

    private var current: String { index.indices.contains(cursor) ? index[cursor] : key }

    var body: some View {
        let verses = verseList
        VStack(spacing: 0) {
            progress.padding(.horizontal, 20).padding(.top, 6)
            switch layout {
            case .bottom: bottomLayout(verses)
            case .deck: deckLayout(verses)
            }
        }
        .pageBackground()
        .navigationTitle(title)
        .smallTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker(localized("ezber.duzen"), selection: $layout) {
                        Label(localized("ezber.duzen.alt"), systemImage: "rectangle.bottomthird.inset.filled")
                            .tag(MemorizationLayout.bottom)
                        Label(localized("ezber.duzen.deste"), systemImage: "rectangle.stack").tag(
                            MemorizationLayout.deck)
                    }
                } label: {
                    Image(
                        systemName: layout == .bottom
                            ? "rectangle.bottomthird.inset.filled" : "rectangle.stack")
                }
                .accessibilityLabel(localized("ezber.duzen"))
                .accessibilityValue(localized(layout == .bottom ? "ezber.duzen.alt" : "ezber.duzen.deste"))
            }
        }
        .onAppear { if index.isEmpty { buildQueue() } }
    }

    private func buildQueue() {
        let cards = store.memorizationCards()
        let bu = cards.first { $0.anahtar == key }
        guard let bu, MemorizationScheduler.isDue(bu.sonraki) else {
            index = [key]
            return
        }
        index =
            [key]
            + cards.filter { $0.anahtar != key && MemorizationScheduler.isDue($0.sonraki) }.map(
                \.anahtar)
    }

    private var progress: some View {
        let total = max(index.count, 1)
        return VStack(alignment: .trailing, spacing: 6) {
            Text(app: "ezber.ilerleme \(min(cursor + 1, total)) \(total)").typography(.footnote)
                .foregroundStyle(theme.colors.text2)
            ProgressView(value: Double(cursor), total: Double(total))
                .tint(theme.colors.sage)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    private func modePicker() -> some View {
        Picker(localized("ezber.gorunum"), selection: $appearance) {
            Text(app: "ezber.gizli").tag(Mode.hidden)
            Text(app: "ezber.ilk_harf").tag(Mode.firstLetter)
            Text(app: "ezber.acik").tag(Mode.light)
        }
        .pickerStyle(.segmented)
        .onChange(of: appearance) { _, _ in expanded = [] }
    }

    private func verseText(_ verses: [Verse]) -> some View {
        VStack(alignment: .trailing, spacing: 14) {
            ForEach(verses) { a in
                FlowLayout(interval: 10) {
                    ForEach(a.words) { k in word(k) }
                    Text(verbatim: verseEnd(a.verse)).typography(.arabic(size: settings.arabicSize * 0.8))
                        .foregroundStyle(theme.colors.accent)
                }
                .environment(\.layoutDirection, .rightToLeft)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func tools(_ verses: [Verse]) -> some View {
        HStack {
            Button(localized("ezber.dinle"), systemImage: "play.fill") { listen(verses) }
            Spacer()
            Button(localized("ezber.hepsini_ac")) { appearance = .light }
        }
        .buttonStyle(.bordered)
    }

    private func bottomLayout(_ verses: [Verse]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                modePicker()
                verseText(verses)
                    .padding(16)
                    .background(theme.colors.surface, in: .rect(cornerRadius: 20))
                tools(verses)
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text(app: "ezber.nasildi").typography(.footnote).foregroundStyle(theme.colors.label)
                HStack(spacing: 8) {
                    ForEach(MemorizationScheduler.Rating.allCases, id: \.self) { p in largeRating(p) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(theme.colors.background)
        }
    }

    private func deckLayout(_ verses: [Verse]) -> some View {
        let prediction = MemorizationSwipe.score(dragOffset, allowUp: !scrollable)
        return VStack(spacing: 14) {
            modePicker().padding(.horizontal, 20).padding(.top, 12)
            ZStack {
                if cursor + 1 < index.count {
                    RoundedRectangle(cornerRadius: 24).fill(theme.colors.surface2)
                        .padding(.horizontal, 14).padding(.top, 16)
                        .accessibilityHidden(true)
                }
                ScrollView {
                    VStack(spacing: 14) {
                        Text(verbatim: title).typography(.footnote).textCase(.uppercase).foregroundStyle(
                            theme.colors.label)
                        verseText(verses)
                        Text(app: "ezber.dokun").typography(.footnote).foregroundStyle(theme.colors.text2)
                    }
                    .padding(20)
                }
                .scrollBounceBehavior(.basedOnSize)
                .onScrollGeometryChange(for: Bool.self) { g in
                    g.contentSize.height > g.containerSize.height + 1
                } action: {
                    _, yeni in
                    scrollable = yeni
                }
                .background(theme.colors.surface, in: .rect(cornerRadius: 24))
                .overlay {
                    RoundedRectangle(cornerRadius: 24).strokeBorder(
                        prediction.map { background($0) } ?? theme.colors.line, lineWidth: 2)
                }
                .overlay(alignment: .topTrailing) {
                    if let prediction {
                        Text(app: name(prediction)).typography(.emphasized).textCase(.uppercase)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .foregroundStyle(text(prediction))
                            .background(background(prediction), in: .rect(cornerRadius: 8))
                            .rotationEffect(.degrees(8))
                            .padding(16)
                            .accessibilityHidden(true)
                    }
                }
                .offset(dragOffset)
                .rotationEffect(.degrees(Double(dragOffset.width) / 22))
                .simultaneousGesture(
                    DragGesture(minimumDistance: 24)
                        .onChanged { d in
                            dragOffset =
                                scrollable ? CGSize(width: d.translation.width, height: 0) : d.translation
                        }
                        .onEnded { d in
                            if let p = MemorizationSwipe.score(d.translation, allowUp: !scrollable) {
                                rate(p)
                            }
                            withAnimation(.spring(duration: 0.3)) { dragOffset = .zero }
                        }
                )
                .accessibilityActions {
                    ForEach(MemorizationScheduler.Rating.allCases, id: \.self) { p in
                        Button(localized(nameText(p))) { rate(p) }
                    }
                }
                .sensoryFeedback(.selection, trigger: prediction)
                .padding(.horizontal, 20)
            }
            .frame(maxHeight: .infinity)
            tools(verses).padding(.horizontal, 20)
            HStack(spacing: 8) {
                smallRating(.zor, "arrow.left")
                smallRating(.good, "arrow.up")
                smallRating(.kolay, "arrow.right")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    private var verseList: [Verse] {
        guard let r = interval, let contentProvider else { return [] }
        return (r.first...r.end).compactMap { contentProvider.verse(.verse(surah: r.surah, verse: $0)) }
    }

    private var interval: (surah: Int, first: Int, end: Int)? {
        switch ContentKey(text: current) {
        case .verse(let s, let a): (s, a, a)
        case .verseRange(let s, let i, let j): (s, i, j)
        default: nil
        }
    }

    private var title: String {
        guard let contentProvider, let a = ContentKey(text: current) else { return current }
        return verseName(a, contentProvider)
    }

    /// Large word tiles (variant 09 A): hidden on `surface2`, revealed without a surface.
    @ViewBuilder private func word(_ k: Word) -> some View {
        let light = appearance == .light || expanded.contains(k.key.text)
        Button {
            if light { expanded.remove(k.key.text) } else { expanded.insert(k.key.text) }
        } label: {
            Text(verbatim: light ? k.text : (appearance == .firstLetter ? firstLetter(k.text) : "ـــــ"))
                .typography(.arabic(size: settings.arabicSize * 0.95))
                .foregroundStyle(light ? theme.colors.text : theme.colors.text2)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .frame(minWidth: 44, minHeight: 44)
                .background(light ? .clear : theme.colors.surface2, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(light ? k.text : localized("ezber.gizli_kelime"))
    }

    /// First letter together with its marks (harakat), then tatweel as a placeholder.
    private func firstLetter(_ m: String) -> String {
        guard let first = m.first else { return m }
        return String(first) + "ـــ"
    }

    private func listen(_ verses: [Verse]) {
        player.reciter = Reciter.find(settings.reciter)
        player.play(
            queue: RecitationPlayer.queue(verses: verses.map { ($0.surah, $0.verse) }, withBasmala: false))
    }

    private func rate(_ p: MemorizationScheduler.Rating) {
        if let k = store.memorizationCards().first(where: { $0.anahtar == current }) {
            store.rateMemorization(k, p)
        }
        if cursor + 1 < index.count {
            expanded = []
            cursor += 1
        } else {
            close()
        }
    }

    /// Next interval for the subline („1 gün“, „4 gün“) - same calculation as when saving.
    private func nextText(_ p: MemorizationScheduler.Rating) -> String {
        guard let k = store.memorizationCards().first(where: { $0.anahtar == current }) else { return "" }
        let day = MemorizationScheduler.next(
            interval: k.aralik, ease: k.kolaylik, repetition: k.tekrar, score: p
        )
        .interval
        return Duration.seconds(day * 86400).formatted(
            .units(allowed: [.days], width: .abbreviated).locale(AppLanguage.locale))
    }

    private func name(_ p: MemorizationScheduler.Rating) -> LocalizedStringKey {
        switch p {
        case .zor: "ezber.zor"
        case .good: "ezber.iyi"
        case .kolay: "ezber.kolay"
        }
    }

    private func nameText(_ p: MemorizationScheduler.Rating) -> String.LocalizationValue {
        switch p {
        case .zor: "ezber.zor"
        case .good: "ezber.iyi"
        case .kolay: "ezber.kolay"
        }
    }

    /// Roles instead of accent colors: dark text on a light tone, ≥ 4.5:1 in all themes (A13).
    private func background(_ p: MemorizationScheduler.Rating) -> Color {
        switch p {
        case .zor: theme.colors.errorBackground
        case .good: theme.colors.warningBackground
        case .kolay: theme.colors.successBackground
        }
    }

    private func text(_ p: MemorizationScheduler.Rating) -> Color {
        switch p {
        case .zor: theme.colors.errorText
        case .good: theme.colors.warningText
        case .kolay: theme.colors.successText
        }
    }

    private func largeRating(_ p: MemorizationScheduler.Rating) -> some View {
        Button {
            rate(p)
        } label: {
            VStack(spacing: 2) {
                Text(app: name(p)).typography(.emphasized)
                Text(verbatim: nextText(p)).typography(.footnote)
            }
            .foregroundStyle(text(p))
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(background(p), in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    /// Escape hatch for VoiceOver, large text and everyone who does not want to swipe (variant 09 B).
    private func smallRating(_ p: MemorizationScheduler.Rating, _ ok: String) -> some View {
        Button {
            rate(p)
        } label: {
            Label {
                Text(app: name(p))
            } icon: {
                Image(systemName: ok)
            }
            .typography(.secondary)
            .foregroundStyle(text(p))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(background(p).opacity(voiceOver ? 1 : 0.7), in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
