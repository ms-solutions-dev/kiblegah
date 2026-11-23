import ContentPacks
import Core
import DesignSystem
import NaturalLanguage
import SwiftUI
import UserData

/// „Her şeyde ara“: verses, Okunuş, duas, Esma – grouped, hits highlighted.
struct SearchScreen: View {
    @Environment(\.contentProvider) private var contentProvider
    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme
    @State private var search: String
    @State private var result: [SearchResult] = []
    @State private var meaning: [SearchResult] = []

    init(start: String = "") { _search = State(initialValue: start) }

    var body: some View {
        List {
            if search.trimmingCharacters(in: .whitespaces).count < 2 {
                Text(app: "arama.ipucu").foregroundStyle(theme.colors.text2)
            } else if result.isEmpty && meaning.isEmpty {
                Text(app: "dua.ara.yok").foregroundStyle(theme.colors.text2)
            }
            SearchSections(result: result, queryText: search)
            if !meaning.isEmpty {
                Section {
                    ForEach(meaning) { s in
                        NavigationLink(value: Goal.verse(s.key)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: verseName(s.key, contentProvider!)).typography(.footnote)
                                    .foregroundStyle(
                                        theme.colors.label)
                                Text(verbatim: s.text).typography(.secondary).lineLimit(3)
                            }
                        }
                    }
                } header: {
                    Text(app: "arama.anlam")
                } footer: {
                    Text(app: "arama.anlam.not")
                }
            }
        }
        .alwaysSearchable($search, prompt: localized("arama.istem"))
        .pageBackground()
        .navigationTitle(localized("arama.baslik"))
        .task(id: search) {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let contentProvider else { return }
            meaning = []
            result = contentProvider.search(
                search,
                preferred: activeTranslations(contentProvider, settings).map(\.id) + [
                    "okunus-\(transliterationLanguage(settings))", "hadis-\(translationLanguage())",
                ], limit: 60)
            // Meaning search in the first active translation, off the main thread (first call loads ~0.2 s).
            let queryText = search
            let translation = meaningTranslation(search, contentProvider, settings)
            let known = Set(result.map(\.key))
            let yakin = await Task.detached(priority: .userInitiated) {
                contentProvider.searchMeaning(queryText, pack: translation, limit: 12)
            }.value
            guard !Task.isCancelled else { return }
            meaning = Array(yakin.filter { !known.contains($0.key) }.prefix(8))
        }
    }
}

/// Translation for the meaning search: in the language of the query, not of the app – someone set
/// to German who types „rızık kaygısı“ searches in the Turkish translation. If detection is
/// uncertain (short queries), it stays with the first active translation.
@MainActor func meaningTranslation(
    _ queryText: String, _ contentProvider: any ContentProvider, _ settings: AppSettings
) -> String {
    let active = activeTranslations(contentProvider, settings)
    let r = NLLanguageRecognizer()
    r.languageConstraints = [.turkish, .german, .english]
    r.processString(queryText)
    if let (language, probability) = r.languageHypotheses(withMaximum: 1).first, probability > 0.6,
        let m = active.first(where: { $0.language == language.rawValue })
            ?? contentProvider.packs.first(where: { $0.kind == "meal" && $0.language == language.rawValue })
    {
        return m.id
    }
    return active.first?.id ?? ""
}

/// Hits grouped by kind; also used in the Quran tab below the surah names.
struct SearchSections: View {
    @Environment(\.contentProvider) private var contentProvider
    @Environment(\.theme) private var theme
    let result: [SearchResult]
    let queryText: String

    var body: some View {
        ForEach(
            [SearchResult.Kind.verse, .translation, .transliteration, .dua, .hadith, .divineName], id: \.self
        ) { kind in
            let l = result.filter { $0.kind == kind }
            if !l.isEmpty {
                Section {
                    ForEach(l) { s in
                        NavigationLink(value: goal(s)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: title(s)).typography(.footnote).foregroundStyle(
                                    theme.colors.label)
                                Text(
                                    highlight(
                                        summary(s.text, queryText), queryText, color: theme.colors.accent)
                                )
                                .typography(
                                    .secondary
                                ).lineLimit(3)
                            }
                        }
                    }
                } header: {
                    Text(
                        verbatim: AppLanguage.bundle.localizedString(
                            forKey: "arama.tur.\(kind.rawValue)", value: nil, table: nil))
                }
            }
        }
    }

    private func goal(_ s: SearchResult) -> Goal {
        switch s.key {
        case .dua(let slug): .dua(slug)
        case .divineName(let n): .divineNameDetail(n)
        case .hadith(_, let n): .hadithDetail(n)
        default: .verse(s.key)
        }
    }

    private func title(_ s: SearchResult) -> String {
        switch s.key {
        case .verse(let su, let a):
            let name = contentProvider?.surah(su)?.name(language: translationLanguage()) ?? ""
            let source = contentProvider?.packs.first { $0.id == s.pack }?.title ?? ""
            return s.kind == .verse ? "\(name) \(su):\(a)" : "\(name) \(su):\(a) · \(source)"
        case .dua(let slug):
            return contentProvider.flatMap { b in b.duas().first { $0.slug == slug }.map { duaSource($0, b) }
            }
                ?? slug
        case .divineName(let n): return "\(n)"
        case .hadith(_, let n):
            let h = contentProvider?.hadith(n, language: String(s.pack.dropFirst("hadis-".count)))
            return [h?.source, h?.degrees].compactMap { $0 }.joined(separator: " · ")
        default: return s.key.text
        }
    }
}

/// A window of ~160 characters around the first hit.
func summary(_ text: String, _ queryText: String) -> String {
    let folded = foldCharacter(text)
    guard let first = TurkishText.searchForm(queryText).split(separator: " ").first.map(String.init),
        let r = folded.range(of: first) ?? folded.range(of: String(first.prefix(max(3, first.count - 2))))
    else { return String(text.prefix(160)) }
    let i = folded.distance(from: folded.startIndex, to: r.lowerBound)
    let start = max(0, i - 60)
    let chars = Array(text)
    let part = String(chars[start..<min(chars.count, start + 160)])
    return (start > 0 ? "…" : "") + part + (start + 160 < chars.count ? "…" : "")
}

/// Folded character by character so that positions in the original are correct (same length).
func foldCharacter(_ text: String) -> String {
    String(
        text.map { c -> Character in
            let k = TurkishText.searchForm(String(c))
            return k.count == 1 ? k.first! : (c.isWhitespace || "'’-".contains(c) ? " " : c)
        })
}

/// Highlights every occurrence of the search words in bold and in color.
func highlight(_ text: String, _ queryText: String, color: Color) -> AttributedString {
    var a = AttributedString(text)
    let folded = Array(foldCharacter(text))
    let words = TurkishText.searchForm(queryText).split(separator: " ").map { Array($0) }.filter {
        $0.count >= 2
    }
    let chars = Array(a.characters.indices)
    guard chars.count == folded.count else { return a }
    for k in words {
        var i = 0
        while i + k.count <= folded.count {
            if Array(folded[i..<(i + k.count)]) == k {
                let end = i + k.count < chars.count ? chars[i + k.count] : a.endIndex
                a[chars[i]..<end].inlinePresentationIntent = .stronglyEmphasized
                a[chars[i]..<end].foregroundColor = color
                i += k.count
            } else {
                i += 1
            }
        }
    }
    return a
}
