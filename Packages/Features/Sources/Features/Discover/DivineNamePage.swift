import ContentPacks
import Core
import DesignSystem
import SwiftUI
import UserData

/// The page of a name as a one-pager:
/// name large on a quiet star pattern, below it the meaning and two to three sentences of explanation,
/// then the verses with the word to swipe through, and at the bottom dhikr and the neighboring names.
///
/// Before, there was only the first citation, a red button and fine print, and half the
/// page stayed empty. The source is not gone, but behind „Kaynak ⓘ“.
struct DivineNameDetailScreen: View {
    @Environment(\.contentProvider) private var contentProvider
    @Environment(\.theme) private var theme
    @Environment(AppSettings.self) private var settings
    @State private var number: Int
    @State private var verses: [ContentKey]?
    @State private var dhikr = 0
    @State private var sourceOpen = false
    @State private var page: ContentKey?

    init(number: Int) { _number = State(initialValue: number) }

    var body: some View {
        if let e = contentProvider?.divineNames().first(where: { $0.number == number }) {
            ScrollView {
                VStack(spacing: 8) {
                    nameView(e)
                    VStack(spacing: 2) {
                        Text(verbatim: name(e)).typography(.title1).foregroundStyle(theme.colors.text)
                        Text(verbatim: e.displayMeaning).typography(.body)
                            .foregroundStyle(
                                theme.colors.text2)
                        if let note = e.pairNote {
                            Text(verbatim: note).typography(.footnote).foregroundStyle(theme.colors.text2)
                                .padding(.top, 4)
                        }
                    }
                    .multilineTextAlignment(.center)
                    explanation(e)
                    verseSection(e)
                    bottomRow(e)
                }
                .padding(.horizontal, 20)
                .padding(.top, 0).padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
            .background { StarPattern().opacity(theme.colors.dark ? 0.06 : 0.08).ignoresSafeArea() }
            .pageBackground()
            .smallTitle()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(verbatim: "\(e.number) / 99").typography(.footnote).bold().monospacedDigit()
                        .foregroundStyle(theme.colors.label)
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareButton(
                        .divineName(
                            arabic: e.displayArabic, name: name(e), meaning: e.displayMeaning,
                            source: divineNameSource(e),
                            number: e.number))
                }
            }
            .sheet(isPresented: $sourceOpen) { sourceSheet(e) }
            .task(id: number) {
                page = nil
                dhikr = 0
                guard let contentProvider else { return }
                // Already searched: immediately, without a loading spinner ().
                verses = DivineNameVerseCache.result[e.arabic]
                if verses == nil { verses = await DivineNameVerseCache.verses(e.arabic, contentProvider) }
                // The neighbors in advance so that paging does not wait.
                let all = contentProvider.divineNames()
                for n in [number % 99 + 1, (number + 97) % 99 + 1] {
                    if let k = all.first(where: { $0.number == n }) {
                        Task { _ = await DivineNameVerseCache.verses(k.arabic, contentProvider) }
                    }
                }
            }
        }
    }

    /// ed-Dârr always with en-Nâfi‘ (`DivineName.namedWithPartner`), here and on the neighbor buttons.
    private func name(_ e: DivineName) -> String { e.displayName }

    /// The name is also the dhikr: each tap counts once, the ring fills up to 33.
    private func nameView(_ e: DivineName) -> some View {
        let kind = dhikr % 33
        return Button {
            dhikr += 1
        } label: {
            Text(verbatim: e.displayArabic).typography(.arabic(size: e.partner == nil ? 46 : 34))
                .foregroundStyle(theme.colors.text)
                .padding(14)
                .background {
                    ZStack {
                        Circle().stroke(theme.colors.accent.opacity(0.12), lineWidth: 3)
                        Circle().trim(from: 0, to: CGFloat(dhikr > 0 && kind == 0 ? 33 : kind) / 33)
                            .stroke(theme.colors.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.easeOut(duration: 0.2), value: dhikr)
                    }
                    .opacity(dhikr > 0 ? 1 : 0.6)
                }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: dhikr % 33 == 0 ? .heavy : .light), trigger: dhikr)
        .overlay(alignment: .bottom) {
            Text(
                app: dhikr > 0 ? "esma.zikir.sayac \(dhikr % 33 == 0 ? 33 : dhikr % 33)" : "esma.zikir.dokun"
            )
            .typography(.footnote).foregroundStyle(theme.colors.accent).fixedSize().offset(y: 16)
        }
        .padding(.bottom, 14)
        .accessibilityLabel(Text(verbatim: "\(name(e)), \(e.displayMeaning)"))
        .accessibilityHint(Text(app: "esma.zikir.ipucu"))
    }

    /// A further explanation, if a plugin provides one; it can open the source sheet.
    private func explanation(_ e: DivineName) -> some View {
        SlotView(.divineNameExplanation(e.number))
            .environment(\.divineNameSourceAction, DivineNameSourceAction { sourceOpen = true })
    }

    @ViewBuilder private func verseSection(_ e: DivineName) -> some View {
        if let verses, !verses.isEmpty {
            VStack(spacing: 8) {
                HStack {
                    Text(app: "esma.kuranda").typography(.emphasized).foregroundStyle(theme.colors.text)
                    Spacer()
                    Text(app: "esma.kelime_ayetleri \(verses.count)").typography(.footnote)
                        .foregroundStyle(theme.colors.text2)
                }
                TabView(selection: $page) {
                    ForEach(verses, id: \.self) { a in
                        DivineNameVerseCard(key: a, goal: WordSearch.goal(e.arabic))
                            .padding(.horizontal, 2)
                            .tag(Optional(a))
                    }
                }
                #if os(iOS)
                    .tabViewStyle(.page(indexDisplayMode: .never))
                #endif
                .frame(height: 160)
                if verses.count > 1 {
                    let i = (page.flatMap { verses.firstIndex(of: $0) } ?? 0) + 1
                    Text(verbatim: "‹  \(i) / \(verses.count)  ›").typography(.footnote).monospacedDigit()
                        .foregroundStyle(theme.colors.text2)
                }
            }
            .padding(.top, 8)
        } else if verses != nil, let k = e.source, e.sourceVerse == nil {
            Text(app: "esma.hadis \(k)").typography(.footnote).foregroundStyle(theme.colors.text2)
        }
    }

    private func bottomRow(_ e: DivineName) -> some View {
        HStack(spacing: 8) {
            neighbor(e.number - 1, advanced: false)
            Spacer(minLength: 0)
            NavigationLink(value: Goal.dhikrDivineName(e.number)) {
                Label(localized("esma.zikre_basla"), systemImage: "sparkles").typography(.footnote).bold()
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(theme.colors.accent, in: .capsule).foregroundStyle(theme.colors.onAccent)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            neighbor(e.number + 1, advanced: true)
        }
        .padding(.top, 8)
    }

    @ViewBuilder private func neighbor(_ n: Int, advanced: Bool) -> some View {
        if let k = contentProvider?.divineNames().first(where: { $0.number == n }) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { number = n }
            } label: {
                Text(verbatim: advanced ? "\(name(k)) ›" : "‹ \(name(k))").typography(.footnote).lineLimit(1)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(theme.colors.surface, in: .capsule)
                    .overlay(Capsule().strokeBorder(theme.colors.line))
                    .foregroundStyle(theme.colors.text)
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(width: 60, height: 1)
        }
    }

    private func sourceSheet(_ e: DivineName) -> some View {
        NavigationStack {
            List {
                SlotView(.divineNameSource(e.number))
                Section {
                    if let a = e.sourceVerse, case .verse(let s, let n) = a {
                        Text(
                            app:
                                "esma.ayet \(contentProvider?.surah(s)?.name(language: translationLanguage()) ?? "") \(s) \(n)"
                        )
                    } else if let k = e.source {
                        Text(app: "esma.hadis \(k)")
                    }
                    Text(app: "esma.kaynak").typography(.footnote).foregroundStyle(theme.colors.text2)
                } header: {
                    Text(app: "esma.isim_ve_anlam")
                }
            }
            .navigationTitle(Text(app: "esma.kaynak.kisa"))
            .smallTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("genel.bitti")) { sourceOpen = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Citation for the share card: verse with surah name or the hadith reference of the source.
    private func divineNameSource(_ e: DivineName) -> String {
        if let a = e.sourceVerse, case .verse(let s, let n) = a, let contentProvider {
            return
                "\(contentProvider.surah(s)?.name(language: translationLanguage()) ?? "") \(s):\(n) · \(localized("sekme.esma"))"
        }
        if let k = e.source { return "\(k) · \(localized("sekme.esma"))" }
        return localized("sekme.esma")
    }
}

extension DivineName {
    /// The name itself in the app language (Turkish transliteration in Turkish).
    var ownName: String {
        translationLanguage() == "tr" ? (transliterationTR ?? latin) : latin
    }

    /// The meaning in the app language. Where the pack has none (Turkish), the English meaning is
    /// shown and marked as English („The Unique (İngilizce)“) instead of posing as a translation.
    var ownMeaning: String {
        let language = translationLanguage()
        guard let m = meaning(language) else { return "" }
        return meaningIsEnglishFallback(language) ? localized("esma.anlam.ingilizce \(m)") : m
    }

    /// The name together with its partner, if it is never named alone (`namedWithPartner`).
    private var shownWith: [DivineName] { [self] + (partner.map { [$0] } ?? []) }

    /// What the screens show as the name: „ed-Dârr · en-Nâfi‘“ for ed-Dârr, otherwise the name.
    var displayName: String { shownWith.map(\.ownName).joined(separator: " · ") }

    /// The meanings in the same order as ``displayName``.
    var displayMeaning: String { shownWith.map(\.ownMeaning).filter { !$0.isEmpty }.joined(separator: " · ") }

    /// The Arabic as shown: both names for a pair (الضَّارُّ النَّافِعُ).
    var displayArabic: String { shownWith.map(\.arabic).joined(separator: " ") }

    /// The sentence under a paired name, nil for all others.
    var pairNote: String? {
        partner.map { localized("esma.cift.not \(ownName) \($0.ownName)") }
    }
}

/// A verse with the word: an excerpt around the word (up to four words before and after), the word
/// in the accent color, below it the first selected translation and the location; tap opens the verse.
struct DivineNameVerseCard: View {
    @Environment(\.contentProvider) private var contentProvider
    @Environment(\.theme) private var theme
    @Environment(AppSettings.self) private var settings
    let key: ContentKey
    let goal: String

    var body: some View {
        NavigationLink(value: Goal.verse(key)) {
            VStack(spacing: 8) {
                arabic.typography(.arabic(size: 22)).multilineTextAlignment(.center).lineLimit(1)
                    .environment(\.layoutDirection, .rightToLeft)
                if let contentProvider,
                    let translation = activeTranslations(contentProvider, settings).first.flatMap({
                        contentProvider.translation(key, pack: $0.id)
                    })
                {
                    Text(verbatim: translation.text).typography(.footnote).foregroundStyle(theme.colors.text2)
                        .multilineTextAlignment(.center).lineLimit(2)
                }
                if case .verse(let s, let a) = key {
                    Text(
                        verbatim:
                            "\(contentProvider?.surah(s)?.name(language: translationLanguage()) ?? "") \(s):\(a) ›"
                    ).typography(
                        .footnote
                    )
                    .bold()
                    .foregroundStyle(theme.colors.accent)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: 155)
            .background(theme.colors.surface, in: .rect(cornerRadius: 18))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var arabic: Text {
        let k = (contentProvider?.verse(key)?.words ?? []).map(\.text)
        let i = k.firstIndex { WordSearch.occurs(goal, verse: $0) } ?? 0
        let start = max(0, i - 4)
        let end = min(k.count, i + 5)
        var t = AttributedString(start > 0 ? "… " : "")
        for j in start..<end {
            var w = AttributedString(k[j] + (j < end - 1 ? " " : ""))
            w.foregroundColor = j == i ? theme.colors.accent : theme.colors.text
            t += w
        }
        t += AttributedString(end < k.count ? " …" : "")
        return Text(t)
    }
}

/// Quiet pattern of eight-pointed stars (two rotated squares per tile).
struct StarPattern: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Canvas { c, size in
            let k: CGFloat = 56
            let r = CGRect(x: -12, y: -12, width: 24, height: 24)
            let square = Path(r)
            var y: CGFloat = 0
            while y < size.height + k {
                var x: CGFloat = 0
                while x < size.width + k {
                    let t = CGAffineTransform(translationX: x + k / 2, y: y + k / 2)
                    c.stroke(square.applying(t), with: .color(theme.colors.text), lineWidth: 1)
                    c.stroke(
                        square.applying(CGAffineTransform(rotationAngle: .pi / 4).concatenating(t)),
                        with: .color(theme.colors.text), lineWidth: 1)
                    x += k
                }
                y += k
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The verses per name, searched once:
/// the search across the whole Quran takes about half a second per name in the debug build. A
/// second call during the search waits for the same search instead of restarting it.
@MainActor enum DivineNameVerseCache {
    static var result: [String: [ContentKey]] = fromDisk()
    private static var inFlight: [String: Task<[ContentKey], Never>] = [:]

    /// Remembered in Caches (); the key depends on the state of the content packs in the bundle.
    private static var file: URL { URL.cachesDirectory.appending(path: "esma-ayetler-\(packVersion).json") }
    private static var packVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    private static func fromDisk() -> [String: [ContentKey]] {
        (try? Data(contentsOf: file)).flatMap {
            try? JSONDecoder().decode([String: [ContentKey]].self, from: $0)
        }
            ?? [:]
    }

    /// Search all 99 names one after another and write them to disk once (``Prewarm``).
    static func prepareAll(_ contentProvider: any ContentProvider) async {
        let missing = contentProvider.divineNames().map(\.arabic).filter { result[$0] == nil }
        guard !missing.isEmpty else { return }
        for a in missing { _ = await verses(a, contentProvider) }
        if let v = try? JSONEncoder().encode(result) { try? v.write(to: file, options: .atomic) }
    }

    static func verses(_ arabic: String, _ contentProvider: any ContentProvider) async -> [ContentKey] {
        if let s = result[arabic] { return s }
        if let t = inFlight[arabic] { return await t.value }
        let t = Task.detached(priority: .userInitiated) { contentProvider.versesContainingWord(arabic) }
        inFlight[arabic] = t
        let s = await t.value
        result[arabic] = s
        inFlight[arabic] = nil
        return s
    }
}
