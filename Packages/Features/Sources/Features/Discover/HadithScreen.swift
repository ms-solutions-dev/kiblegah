import ContentPacks
import Core
import DesignSystem
import SwiftUI
import UserData

/// Hadith: categories → hadiths → detail with source, grade, explanation and verses.
struct HadithScreen: View {
    @Environment(\.contentProvider) private var contentProvider
    @Environment(\.theme) private var theme
    var parent: Int?
    var title: String?
    @State private var search = ""
    @State private var found: [Hadith]?

    var body: some View {
        Group {
            if parent == nil {
                list.alwaysSearchable($search, prompt: localized("hadis.ara"))
            } else {
                list
            }
        }
        .task(id: search) { await runSearch() }
        #if DEBUG
            // Screenshots of the search without typing: `-hadisAra komşu`.
            .onAppear {
                if parent == nil, search.isEmpty, let q = UserDefaults.standard.string(forKey: "hadisAra") {
                    search = q
                }
            }
        #endif
    }

    private func runSearch() async {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2, let contentProvider else {
            found = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }
        let language = translationLanguage()
        var seenRange = Set<Int>()
        found = contentProvider.search(q, preferred: ["hadis-\(language)"], limit: 400).compactMap { r in
            guard r.kind == .hadith, case .hadith(_, let n) = r.key, seenRange.insert(n).inserted else {
                return nil
            }
            return contentProvider.hadith(n, language: language)
        }
    }

    @ViewBuilder private var list: some View {
        if let found {
            List {
                if found.isEmpty {
                    Text(app: "hadis.ara.bos").foregroundStyle(theme.colors.text2)
                } else {
                    Section {
                        ForEach(found) { h in HadithRow(hadith: h) }
                    } header: {
                        Text(app: "hadis.ara.sonuc \(found.count)")
                    }
                }
            }
            .navigationTitle(title ?? localized("sekme.hadis"))
        } else {
            categoryList
        }
    }

    private var categoryList: some View {
        let categories =
            contentProvider?.hadithCategories(language: translationLanguage(), parent: parent) ?? []
        let hadiths =
            parent.map { contentProvider?.hadiths(category: $0, language: translationLanguage()) ?? [] } ?? []
        return List {
            if categories.isEmpty && hadiths.isEmpty {
                Text(app: "hadis.bos").foregroundStyle(theme.colors.text2)
            }
            if !categories.isEmpty {
                Section {
                    ForEach(categories) { k in
                        NavigationLink(value: Goal.hadithCategory(k.id, k.name)) {
                            if parent == nil, let g = Self.appearance(k.id) {
                                Label {
                                    LabeledContent(k.name, value: "\(k.count)")
                                } icon: {
                                    IconTile(g.icon, tone: g.ton)
                                }
                            } else {
                                LabeledContent(k.name, value: "\(k.count)")
                            }
                        }
                    }
                }
            }
            if !hadiths.isEmpty {
                Section {
                    ForEach(hadiths) { h in HadithRow(hadith: h) }
                }
            }
            Section { Text(app: "hadis.kaynak").typography(.footnote).foregroundStyle(theme.colors.text2) }
        }
        .navigationTitle(title ?? localized("sekme.hadis"))
    }

    /// Color field and symbol of the seven top-level HadeethEnc categories. The
    /// numbers are the fixed identifiers from `hadith/veri.sqlite`; subcategories stay plain.
    static func appearance(_ id: Int) -> (icon: String, ton: CategoryTone)? {
        switch id {
        case 1: ("book.closed", .sage)
        case 2: ("text.quote", .sea)
        case 3: ("checkmark.seal", .saffron)
        case 4: ("scalemass", .clay)
        case 5: ("leaf", .turquoise)
        case 6: ("megaphone", .purple)
        case 7: ("scroll", .rose)
        default: nil
        }
    }
}

struct HadithRow: View {
    @Environment(\.theme) private var theme
    let hadith: Hadith

    var body: some View {
        NavigationLink(value: Goal.hadithDetail(hadith.identifier)) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: hadith.title).typography(.emphasized).lineLimit(3)
                Text(verbatim: "\(hadith.source) · \(hadith.degrees)").typography(.footnote).foregroundStyle(
                    theme.colors.text2)
            }
        }
    }
}

struct HadithDetailScreen: View {
    @Environment(\.contentProvider) private var contentProvider
    @Environment(UserStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme
    let identifier: Int

    var body: some View {
        if let contentProvider, let h = contentProvider.hadith(identifier, language: translationLanguage()) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(verbatim: h.title).typography(.title2)
                    Text(verbatim: h.text).font(
                        .custom("Plus Jakarta Sans", size: settings.translationSize, relativeTo: .body))
                    HStack(spacing: 8) {
                        Label(h.degrees, systemImage: "checkmark.seal").typography(.footnote)
                        Text(verbatim: "·").accessibilityHidden(true)
                        Text(verbatim: h.source).typography(.footnote)
                    }
                    .foregroundStyle(theme.colors.sage)
                    if h.language != translationLanguage() {
                        Text(app: "hadis.dil_yok").typography(.footnote).foregroundStyle(theme.colors.text2)
                    }
                    if !h.arabic.isEmpty {
                        Text(verbatim: h.arabic).typography(.arabic(size: max(22, settings.arabicSize * 0.8)))
                            .multilineTextAlignment(.trailing).frame(
                                maxWidth: .infinity, alignment: .trailing)
                    }
                    if !h.explanation.isEmpty {
                        section("hadis.aciklama") { Text(verbatim: h.explanation).typography(.body) }
                    }
                    if !h.benefits.isEmpty {
                        section("hadis.faydalar") {
                            ForEach(Array(h.benefits.enumerated()), id: \.offset) { _, f in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(verbatim: "•").accessibilityHidden(true)
                                    Text(verbatim: f).typography(.body)
                                }
                            }
                        }
                    }
                    let verses = contentProvider.hadithVerses(h.identifier)
                    if !verses.isEmpty {
                        section("hadis.ayetler") {
                            ForEach(verses, id: \.self) { a in
                                NavigationLink(value: Goal.verse(firstVerse(a))) {
                                    Text(verbatim: verseName(a, contentProvider)).typography(.secondary)
                                }
                            }
                        }
                    }
                    Text(app: "hadis.kaynak").typography(.footnote).foregroundStyle(theme.colors.text2)
                }
                .padding(20)
            }
            .pageBackground()
            .smallTitle()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    let _ = store.version
                    let k = store.isSaved(h.key.text)
                    Button {
                        store.toggleSaved(h.key.text)
                    } label: {
                        Image(systemName: k ? "bookmark.fill" : "bookmark")
                    }
                    .accessibilityLabel(localized("kuran.kaydet"))
                    .accessibilityValue(localized(k ? "dua.favori.acik" : "dua.favori.kapali"))
                }
                ToolbarItem(placement: .primaryAction) {
                    CollectionMenu(key: h.key).labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareButton(
                        .hadith(
                            text: h.text, arabic: h.arabic,
                            source: "\(h.source) · \(h.degrees) · HadeethEnc.com", identifier: h.identifier))
                }
            }
        } else {
            EmptyState(title: "hadis.yok.baslik", explanation: "hadis.bos")
        }
    }

    private func section<I: View>(_ b: LocalizedStringKey, @ViewBuilder _ content: () -> I) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(app: b).typography(.footnote).textCase(.uppercase).foregroundStyle(theme.colors.label)
            content()
        }
    }
}

public func firstVerse(_ a: ContentKey) -> ContentKey {
    if case .verseRange(let s, let i, _) = a { return .verse(surah: s, verse: i) }
    return a
}

public func verseName(_ a: ContentKey, _ contentProvider: any ContentProvider) -> String {
    switch a {
    case .verse(let s, let n):
        return "\(contentProvider.surah(s)?.name(language: translationLanguage()) ?? "") \(s):\(n)"
    case .verseRange(let s, let i, let j):
        return "\(contentProvider.surah(s)?.name(language: translationLanguage()) ?? "") \(s):\(i)–\(j)"
    default: return a.text
    }
}
