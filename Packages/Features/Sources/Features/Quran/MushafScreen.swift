import ContentPacks
import Core
import CoreText
import DesignSystem
import Quran
import SwiftUI
import Synchronization
import UserData

/// Line layout of a Mushaf page from the own service.
/// `words` (from format 2) carries per line the QCF glyphs in reading direction, `typography` the font edition.
struct MushafPageLayout: Codable, Sendable {
    struct Glyph: Codable, Sendable {
        /// `s:a:w` with the QF word position; at the end of a verse the position after the last word.
        let k: String
        /// Character of the page font p{N}.ttf (`code_v1`).
        let c: String
        let end: Bool

        enum CodingKeys: String, CodingKey {
            case k, c
            case end = "son"
        }
    }
    struct Line: Codable, Sendable {
        let number: Int
        let first: String
        let end: String
        let words: [Glyph]?

        enum CodingKeys: String, CodingKey {
            case number = "no"
            case first = "ilk"
            case end = "son"
            case words = "kelimeler"
        }
    }
    let page: Int
    let typography: String?
    let rows: [Line]

    enum CodingKeys: String, CodingKey {
        case page = "sayfa"
        case typography = "yazi"
        case rows = "satirlar"
    }
}

/// The service for mushaf page layouts: the Quran Foundation routes of the relay; a plugin may name
/// another service with the same paths and format.
public enum MushafLayoutSource {
    nonisolated(unsafe) public static var server: @Sendable () -> String = { Relay.qfBase }
}

/// Fetches and stores layouts and QCF page fonts - for at most one week (QF terms, as on the server).
actor MushafLayoutStore {
    static let shared = MushafLayoutStore()
    static let lifetime: TimeInterval = 7 * 86400
    private let folder = URL.cachesDirectory.appending(path: "MushafDuzeni")
    private let fontFolder = URL.cachesDirectory.appending(path: "MushafYazi")
    private var cached: [String: MushafPageLayout] = [:]
    /// All pages of the edition from its bundle (), read once.
    private var pack: (edition: MushafEdition, pages: [Int: MushafPageLayout])?
    private var packGeneration = 0
    private static let packCounter = Mutex(0)

    /// After a new bundle: re-read on next access.
    nonisolated static func forgetPack() { packCounter.withLock { $0 += 1 } }

    private func fromPack(_ n: Int, edition: MushafEdition) -> MushafPageLayout? {
        let number = Self.packCounter.withLock { $0 }
        if pack?.edition != edition || packGeneration != number {
            packGeneration = number
            pack = MushafPack.file(edition, "duzen.json")
                .flatMap { try? Data(contentsOf: $0, options: .mappedIfSafe) }
                .flatMap { try? JSONDecoder().decode([MushafPageLayout].self, from: $0) }
                .map { (edition, Dictionary($0.map { ($0.page, $0) }, uniquingKeysWith: { a, _ in a })) }
        }
        return pack?.pages[n]
    }

    /// Where a layout without a bundle comes from (``MushafLayoutSource``); empty = bundle only.
    nonisolated static func server() -> String { MushafLayoutSource.server() }

    func layout(_ n: Int, server: String, edition: MushafEdition = .v1) async -> MushafPageLayout? {
        if let d = fromPack(n, edition: edition) { return d }
        let key = edition == .v1 ? "\(n)-2" : "\(n)-v2-2"
        if let d = cached[key] { return d }
        // „-2“: format with glyphs; older files without them expire via `clear`.
        let file = folder.appending(path: "\(key).json")
        if fresh(file), let v = try? Data(contentsOf: file),
            let d = try? JSONDecoder().decode(MushafPageLayout.self, from: v), d.typography != nil
        {
            cached[key] = d
            return d
        }
        // Without a query for V1: `appending(queryItems: [])` appends an empty „?“, which the service
        // rejected as an unknown path - every V1 page not yet stored fell back to the fallback font.
        guard !server.isEmpty, let base = URL(string: server)?.appending(path: "v1/mushaf/\(n)"),
            case let url = edition == .v1
                ? base : base.appending(queryItems: [URLQueryItem(name: "surum", value: edition.raster)]),
            // Own task: if the user pages on, the fetch runs to completion and ends up in the cache.
            let (v, y) = try? await Task(operation: { try await URLSession.shared.data(from: url) }).value,
            (y as? HTTPURLResponse)?.statusCode == 200,
            let d = try? JSONDecoder().decode(MushafPageLayout.self, from: v), !d.rows.isEmpty
        else { return nil }
        // Response from an older service without glyphs is used, but not remembered.
        guard d.typography != nil else { return d }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? v.write(to: file)
        cached[key] = d
        return d
    }

    /// File of the QCF page font (KFGQPC, one font per page) from verses.quran.foundation;
    /// nil without network and without a fresh copy. V4 (tajweed) exists as OT-SVG for light and dark -
    /// both carry the same PostScript name, so the app does not register them but builds
    /// the font directly from the file (`MushafPage.loadFont`).
    func typography(_ n: Int, edition: MushafEdition, dark: Bool) async -> URL? {
        if let u = MushafPack.file(edition, "yazi/p\(n).woff2") { return u }
        let path =
            switch edition {
            case .v1: "v1/ttf"
            case .v2: "v2/ttf"
            case .v4: "v4/ot-svg/\(dark ? "dark" : "light")/ttf"
            }
        let file = fontFolder.appending(path: path.replacingOccurrences(of: "/", with: "-") + "-p\(n).ttf")
        if !fresh(file) {
            guard
                let url = URL(
                    string: "https://verses.quran.foundation/fonts/quran/hafs/\(path)/p\(n).ttf")
            else { return nil }
            var request = URLRequest(url: url)
            // Without a browser identifier the font server responds with 403.
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            guard
                let (v, y) = try? await Task(operation: { try await URLSession.shared.data(for: request) })
                    .value,
                (y as? HTTPURLResponse)?.statusCode == 200, v.count > 1000
            else { return nil }
            try? FileManager.default.createDirectory(at: fontFolder, withIntermediateDirectories: true)
            try? v.write(to: file)
        }
        guard (CTFontManagerCreateFontDescriptorsFromURL(file as CFURL) as? [CTFontDescriptor])?.first != nil
        else {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
        return file
    }

    private func fresh(_ file: URL) -> Bool {
        guard let a = try? FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false)),
            let t = a[.modificationDate] as? Date
        else { return false }
        return Date.now.timeIntervalSince(t) < Self.lifetime
    }

    /// Delete expired items (layouts and fonts).
    func clear() {
        for k in [folder, fontFolder] {
            let l =
                (try? FileManager.default.contentsOfDirectory(
                    at: k, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for d in l {
                let t =
                    (try? d.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    ?? .distantPast
                if Date.now.timeIntervalSince(t) >= Self.lifetime {
                    try? FileManager.default.removeItem(at: d)
                }
            }
        }
    }
}

/// A character of the QCF page font: a word or an end-of-verse mark.
struct MushafGlyph: Identifiable, Sendable {
    let id: Int
    let code: String
    let surah: Int
    let verse: Int
    /// QF word position (for Tanzil via `MushafBuilder.tanzil`).
    let word: Int
    let end: Bool
}

/// A finished line, ready to draw.
enum MushafLine: Identifiable {
    case words(number: Int, [Word])
    case glyphs(number: Int, [MushafGlyph])
    case surahTitle(number: Int, surah: Int)
    case basmala(number: Int)

    var id: Int {
        switch self {
        case .words(let n, _), .glyphs(let n, _), .surahTitle(let n, _), .basmala(let n): n
        }
    }
}

enum MushafBuilder {
    /// Word position per QF → word positions in the Tanzil text. Only 37:130 differs:
    /// QPC writes „إِلْ يَاسِينَ“ as one word, Tanzil as two.
    static func tanzil(_ s: Int, _ a: Int, _ w: Int) -> ClosedRange<Int> {
        guard s == 37, a == 130 else { return w...w }
        return w == 1 ? 1...1 : w >= 3 ? (w + 1)...(w + 1) : 2...3
    }

    static func parseMarker(_ m: String) -> (Int, Int, Int)? {
        let p = m.split(separator: ":").compactMap { Int($0) }
        return p.count == 3 ? (p[0], p[1], p[2]) : nil
    }

    /// Lines 1…15 of a page; gaps before the first verse of a surah become a header (and basmala).
    /// With `withGlyphs` the lines are QCF glyphs, otherwise Tanzil words.
    static func rows(
        _ d: MushafPageLayout, _ contentProvider: any ContentProvider, withGlyphs: Bool = false
    ) -> [MushafLine] {
        var result: [MushafLine] = []
        var full: [Int: MushafLine] = [:]
        for s in d.rows {
            if withGlyphs, let g = s.words, !g.isEmpty {
                full[s.number] = .glyphs(
                    number: s.number,
                    g.enumerated().compactMap { i, k in
                        parseMarker(k.k).map {
                            MushafGlyph(id: i, code: k.c, surah: $0.0, verse: $0.1, word: $0.2, end: k.end)
                        }
                    })
                continue
            }
            guard let (s1, a1, w1) = parseMarker(s.first), let (s2, a2, w2) = parseMarker(s.end) else {
                continue
            }
            var words: [Word] = []
            var su = s1
            var month = a1
            while (su, month) <= (s2, a2) {
                if let verse = contentProvider.verse(.verse(surah: su, verse: month)) {
                    let start = (su, month) == (s1, a1) ? tanzil(su, month, w1).lowerBound : 1
                    let end = (su, month) == (s2, a2) ? tanzil(su, month, w2).upperBound : verse.words.count
                    words += verse.words.enumerated().filter {
                        $0.offset + 1 >= start && $0.offset + 1 <= end
                    }.map(\.element)
                }
                let n = contentProvider.surah(su)?.verseCount ?? 0
                if month < n { month += 1 } else { su += 1; month = 1 }
                if su > 114 { break }
            }
            full[s.number] = .words(number: s.number, words)
        }
        // Empty lines before a starting surah: header, below it (except 1 and 9) the basmala.
        let filled = d.rows.map(\.number).sorted()
        for number in 1...15 {
            if let z = full[number] {
                result.append(z)
                continue
            }
            guard let next = filled.first(where: { $0 > number }),
                let first = d.rows.first(where: { $0.number == next }).flatMap({ parseMarker($0.first) }),
                first.1 == 1, first.2 == 1
            else {
                // Page end after the last line (page 1/2 or end of a surah): header of the next surah if there is room.
                if let end = filled.last, number > end, let s = d.rows.last.flatMap({ parseMarker($0.end) }),
                    s.0 < 114, s.1 == (contentProvider.surah(s.0)?.verseCount ?? -1), number == end + 1,
                    d.page > 2
                {
                    result.append(.surahTitle(number: number, surah: s.0 + 1))
                }
                continue
            }
            let hasBasmala = first.0 != 1 && first.0 != 9
            if hasBasmala && number == next - 1 {
                result.append(.basmala(number: number))
            } else if number == next - (hasBasmala ? 2 : 1) {
                result.append(.surahTitle(number: number, surah: first.0))
            }
        }
        return result
    }

    /// For wrapping: consecutive word lines merged into one flow,
    /// surah header and basmala as separate blocks in between.
    static func blocks(_ rows: [MushafLine]) -> [MushafBlock] {
        var result: [MushafBlock] = []
        var timeline: [MushafBlock.Item] = []
        var first = 0
        func purge() {
            if !timeline.isEmpty { result.append(.text(number: first, timeline)) }
            timeline = []
        }
        for s in rows.sorted(by: { $0.id < $1.id }) {
            switch s {
            case .glyphs(let n, let l):
                if timeline.isEmpty { first = n }
                timeline += l.map { .glyph($0) }
            case .words(let n, let l):
                if timeline.isEmpty { first = n }
                timeline += l.map { .word($0) }
            case .surahTitle(let n, let su):
                purge()
                result.append(.title(number: n, surah: su))
            case .basmala(let n):
                purge()
                result.append(.basmala(number: n))
            }
        }
        purge()
        return result
    }
}

/// A block of the wrapped page (zoom > 1).
enum MushafBlock: Identifiable {
    /// A paragraph seen as a line (for VoiceOver): glyphs or Tanzil words.
    static func row(_ items: [Item]) -> MushafLine {
        let glyphs = items.compactMap { if case .glyph(let g) = $0 { g } else { nil } }
        if glyphs.count == items.count { return .glyphs(number: 0, glyphs) }
        return .words(number: 0, items.compactMap { if case .word(let k) = $0 { k } else { nil } })
    }

    enum Item {
        case glyph(MushafGlyph)
        case word(Word)

        /// Surah and verse of the element.
        var verse: (Int, Int) {
            switch self {
            case .glyph(let g): (g.surah, g.verse)
            case .word(let k):
                if case .word(let s, let a, _) = k.key { (s, a) } else { (0, 0) }
            }
        }
    }
    case title(number: Int, surah: Int)
    case basmala(number: Int)
    case text(number: Int, [Item])

    var id: Int {
        switch self {
        case .title(let n, _), .basmala(let n), .text(let n, _): n
        }
    }
}

/// Line-faithful Mushaf: 604 pages, per line the words of the Medina print, justified.
/// Without a layout (no service, offline for longer than a week) the page text reflows.
/// Tapping a word opens the verse sheet, a long press offers listen/bookmark.
struct MushafScreen: View {
    @Environment(\.contentProvider) private var contentProvider
    @Environment(AppSettings.self) private var settings
    @Environment(UserStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(RecitationPlayer.self) private var player
    @State private var page: Int?
    @State private var firstLaunch: Date?
    @State private var settingOpen = false
    @State private var selected: Verse?
    /// The verse in the open verse sheet: highlighted and paged along, also after swiping ().
    @State private var light: ContentKey?
    /// Zoom (1…3): 1× is the printed page, above that the text reflows. Also applies to the next
    /// page and the next opening.
    @AppStorage("mushafOlcek", store: GroupDefaults.d) private var scale: Double = 1
    @State private var goOpen = false
    @State private var editionSelect = false
    @AppStorage("mushafZoomIpucu", store: GroupDefaults.d) private var zoomHintSeen = false
    @State private var zoomHint = false
    @State private var readingVerse: Verse?
    /// Follow as in map navigation: pages along with the verse being played until the user pages
    /// or scrolls in the wrapped layout; the center button turns it back on, as does a new playback.
    @State private var following = true
    /// Page in the app's numbering (V1); with tajweed the Mushaf shows the V2 page on which it begins.
    let start: Int

    /// Tajweed on: V4 color font on the V2 grid; otherwise V1. `page` counts in this edition.
    private var edition: MushafEdition { MushafEdition(setting: settings.mushafEdition) }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(1...604, id: \.self) { n in
                    MushafPage(
                        number: n, edition: edition, scale: $scale, following: following,
                        scrolledManually: { if player.isActive { withAnimation { following = false } } }
                    ) { selected = $0 }
                    .containerRelativeFrame(.horizontal)
                    .id(n)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $page)
        .scrollIndicators(.hidden)
        // Paged manually (not our paging along): following paused.
        .onScrollPhaseChange { _, y in
            if y == .interacting, player.isActive { withAnimation { following = false } }
        }
        // Arabic book: the next page is on the left.
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear {
            if let first = firstLaunch {
                // Back from the surah view: adopt its position.
                if let s = QuranPosition.shared.fromOther(.mushaf, after: first), let contentProvider,
                    let n = edition.page(index: s, contentProvider), n != page
                {
                    page = n
                }
                firstLaunch = .now
                return
            }
            firstLaunch = .now
            if page == nil, let contentProvider {
                page = MushafEdition.v1.convert(start, nach: edition, contentProvider)
            }
        }
        .onChange(of: page) { _, n in
            guard let n, let contentProvider, let b = edition.interval(n, contentProvider) else { return }
            QuranPosition.shared.save(b.first, .mushaf)
        }
        // Tajweed toggled: the same position in the other numbering.
        .onChange(of: edition) { old, yeni in
            guard let s = page, let contentProvider else { return }
            page = old.convert(s, nach: yeni, contentProvider)
        }
        // While listening, the page pages along when the verse being played is on the next one.
        .onChange(of: player.current) { _, s in
            guard following, let s else { return }
            pageAlong(s)
        }
        // New playback: follow again.
        .onChange(of: player.queue) { withAnimation { following = true } }
        #if DEBUG
            .task { await followCheck(player, contentProvider) { following = false } }
        #endif
        .overlay(alignment: .bottomTrailing) {
            if player.isActive && !following {
                FollowAlongButton {
                    withAnimation { following = true }
                    if let s = player.current { pageAlong(s) }
                }
            }
        }
        // Playback from the Mushaf („Buradan dinle“) needs pause/stop as in the reader.
        .safeAreaInset(edge: .bottom) { PlayerBar() }
        // One-time hint that the page can be enlarged.
        // At the top below the title bar so that it covers no surah band and no line at the page end.
        .overlay(alignment: .top) {
            if zoomHint {
                Text(app: "kuran.mushaf.zoom_ipucu")
                    .typography(.footnote)
                    .foregroundStyle(theme.colors.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: .capsule)
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                    .padding(.top, 8)
                    .transition(.opacity)
                    .onTapGesture { withAnimation { zoomHint = false } }
            }
        }
        .task {
            guard !zoomHintSeen else { return }
            zoomHintSeen = true
            withAnimation { zoomHint = true }
            try? await Task.sleep(for: .seconds(5))
            withAnimation { zoomHint = false }
        }
        .pageBackground()
        .navigationTitle(title)
        .smallTitle()
        .toolbar {
            // The title is a button: jump directly to surah, juz or page.
            ToolbarItem(placement: .principal) {
                Button {
                    goOpen = true
                } label: {
                    HStack(spacing: 4) {
                        Text(verbatim: title).font(.headline).lineLimit(1)
                        Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                            .foregroundStyle(theme.colors.text2)
                    }
                    .foregroundStyle(theme.colors.text)
                }
                .accessibilityHint(localized("kuran.mushaf.git.ipucu"))
            }
            // Listen as in the reader: Okuma Seçenekleri from the first verse of the page.
            ToolbarItem(placement: .primaryAction) {
                Button {
                    guard let contentProvider, let b = edition.interval(page ?? start, contentProvider),
                        let k = contentProvider.key(index: b.first)
                    else { return }
                    readingVerse = contentProvider.verse(k)
                } label: {
                    Image(systemName: "play.fill")
                }
                .accessibilityLabel(localized("kuran.oynatici.dinle"))
            }
            // The same menu as in the surah view; instead of „Mushaf“ it leads to the
            // surah view, plus the edition (V1/V2/V4 with tajweed,).
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if let contentProvider, let b = edition.interval(page ?? start, contentProvider),
                        let k = contentProvider.key(index: b.first)
                    {
                        SlotView(.verseMenuAction(k))
                        NavigationLink {
                            ReaderScreen(start: k)
                        } label: {
                            Label(localized("kuran.sure_gorunumu"), systemImage: "list.bullet.rectangle")
                        }
                    }
                    Button {
                        settingOpen = true
                    } label: {
                        Label(localized("kuran.okuma_ayarlari"), systemImage: "textformat.size")
                    }
                    Button {
                        editionSelect = true
                    } label: {
                        Label(localized("mushaf.fassung.baslik"), systemImage: "paintpalette")
                    }
                    NavigationLink(value: Goal.downloaded) {
                        Label(localized("kuran.indirilenler"), systemImage: "arrow.down.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(localized("kuran.daha_fazla"))
            }
        }
        .sheet(item: $selected, onDismiss: { light = nil }) { a in
            VerseSheet(verse: a) { y in
                light = y.key
                goToPage(surah: y.surah, verse: y.verse)
            }
        }
        .environment(\.openVerse, light)
        .sheet(item: $readingVerse) { ReadingOptions(verse: $0) }
        .sheet(isPresented: $settingOpen) { ReadingSettings() }
        .sheet(isPresented: $editionSelect) {
            NavigationStack { MushafPicker() }.presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $goOpen) {
            MushafJumpSheet(current: page ?? start, edition: edition) { page = $0 }
        }
        .task(id: page) {
            // Preload neighboring pages (layout and font) so paging does not wait for the network.
            if let page {
                let s = edition
                let dark = theme.colors.dark
                let server = MushafLayoutStore.server()
                Task(priority: .utility) {
                    let store = MushafLayoutStore.shared
                    for n in [page + 1, page - 1, page + 2] where (1...604).contains(n) {
                        _ = await store.layout(n, server: server, edition: s)
                        _ = await store.typography(n, edition: s, dark: dark)
                    }
                }
            }
            guard let page, let contentProvider, let b = edition.interval(page, contentProvider) else {
                return
            }
            if let k = contentProvider.key(index: b.first) {
                store.saveLastPosition(k.text, khatm: settings.activeKhatm)
            }
            // A page that is open for 8 s counts as read.
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            store.addReading(firstIndex: b.first, lastIndex: b.end, seconds: 8, khatm: settings.activeKhatm)
        }
        .task { await MushafLayoutStore.shared.clear() }
    }

    /// While listening, the page pages along when the verse being played is on a different one.
    private func pageAlong(_ s: RecitationPlayer.QueueItem) { goToPage(surah: s.surah, verse: s.verse) }

    private func goToPage(surah: Int, verse: Int) {
        guard let contentProvider,
            let yeni = edition.page(surah: surah, verse: max(verse, 1), contentProvider), yeni != page
        else { return }
        withAnimation { page = yeni }
    }

    private var title: String {
        guard let n = page ?? Optional(start), let contentProvider,
            let b = edition.interval(n, contentProvider),
            case .verse(let s, _) = contentProvider.key(index: b.first)
        else { return localized("kuran.mushaf") }
        return
            "\(contentProvider.surah(s)?.name(language: translationLanguage()) ?? "") · \(localized("kuran.sayfa_no \(n)"))"
    }
}

extension EnvironmentValues {
    /// The verse in the open verse sheet above the Mushaf ().
    @Entry var openVerse: ContentKey? = nil
}

struct MushafPage: View {
    @Environment(\.contentProvider) private var contentProvider
    @Environment(AppSettings.self) private var settings
    @Environment(UserStore.self) private var store
    @Environment(RecitationPlayer.self) private var player
    @Environment(\.theme) private var theme
    let number: Int
    /// V1 = printed numbering of the app, V4 = tajweed font on the V2 grid.
    let edition: MushafEdition
    @Binding var scale: Double
    /// Following on: in the wrapped layout the page scrolls to the verse being played.
    var following = true
    /// Scrolled manually in the wrapped layout - the screen then pauses following.
    var scrolledManually: () -> Void = {}
    let selectVerse: (Verse) -> Void
    @Environment(\.openVerse) private var openVerse
    @State private var rows: [MushafLine]?
    /// Ongoing pinch; `scale` adopts the value only at the end of the gesture.
    @GestureState private var liveScale: CGFloat = 1
    /// Page font at 100 pt, directly from the file; nil = ordinary Arabic font.
    @State private var typography: CTFont?
    /// The tajweed font from the bundle (COLRv1) knows only its light palette; CoreText cannot pick
    /// another. In the dark the line is therefore inverted and the hue rotated back:
    /// black becomes white, the tajweed colors keep their hue ().
    @State private var tajweedInverted = false
    @State private var loaded = false
    /// Edition/theme for which `rows` and `typography` are loaded; „tamam“ = finished with page font.
    @State private var loadingPack: String?
    @State private var done = false
    /// Failed load attempts; from three on the fallback counts as final (footer).
    @State private var attempt = 0
    @State private var metricsCache = MushafMetrics.Cache()

    var body: some View {
        GeometryReader { g in
            let z = Self.clamp(CGFloat(scale) * liveScale)
            Group {
                // 1×: the printed page; above that the same words reflow larger (as in the e-book reader).
                if z > 1.01, let rows {
                    timeline(rows, g.size, z: z)
                } else {
                    page(g.size)
                }
            }
            .frame(width: g.size.width, height: g.size.height)
            .contentShape(.rect)
            .onTapGesture(count: 2) { toggleMode() }
            .simultaneousGesture(
                MagnifyGesture()
                    .updating($liveScale) { v, s, _ in s = v.magnification }
                    .onEnded { v in
                        let y = Self.clamp(CGFloat(scale) * v.magnification)
                        scale = y < 1.1 ? 1 : Double(y)
                    }
            )
        }
        // Reload when tajweed toggles or (for V4) light/dark changes.
        .task(id: "\(edition.rawValue)-\(edition == .v4 && theme.colors.dark)") { await load() }
    }

    /// Load layout and page font. The fallback font applies only while something is missing: without network
    /// or service it retries with growing intervals, and as soon as the font is there, the page
    /// is laid out again. A cancellation (page paged away) writes nothing to the state - otherwise
    /// a half-loaded page would remain stuck in the fallback font.
    private func load() async {
        guard let contentProvider else { return }
        let key = "\(edition.rawValue)-\(edition == .v4 && theme.colors.dark)"
        if loadingPack == key && done { return }
        if loadingPack != key {
            rows = nil
            typography = nil
            done = false
        }
        let store = MushafLayoutStore.shared
        let server = MushafLayoutStore.server()
        var wait = 2.0
        while !Task.isCancelled {
            // Layout and page font at the same time; the font does not depend on the own service.
            async let layout = store.layout(number, server: server, edition: edition)
            async let file = store.typography(number, edition: edition, dark: theme.colors.dark)
            var d = await layout
            let u = await file
            var f: CTFont? = d?.typography == edition.raster ? Self.loadFont(u) : nil
            tajweedInverted = edition == .v4 && u?.pathExtension == "woff2"
            #if DEBUG
                // Force the fallback for screenshots: `-mushafRuckfall yazi` (without page font)
                // or `-mushafRuckfall duzen` (without layout, as offline on first opening).
                switch UserDefaults.standard.string(forKey: "mushafRuckfall") {
                case "yazi": f = nil
                case "duzen": d = nil
                default: break
                }
            #endif
            let withGlyphs = d?.typography == edition.raster
            guard !Task.isCancelled else { return }
            if let d {
                typography = f
                rows = MushafBuilder.rows(d, contentProvider, withGlyphs: f != nil)
            }
            loadingPack = key
            loaded = true
            // Done: with font, or an older service without glyphs (then the fallback font stays).
            if d != nil, f != nil || !withGlyphs {
                done = true
                return
            }
            // No relay configured and no page pack still on its way: the layout can never come, so the
            // reflowed text is the final state - no "could not be loaded" footer and no endless retries.
            // While a page pack is still downloading, the loop keeps waiting for it.
            if d == nil, server.isEmpty, MushafPack.isReady(edition) {
                done = true
                return
            }
            attempt += 1
            try? await Task.sleep(for: .seconds(wait))
            wait = min(wait * 2, 30)
        }
    }

    static func clamp(_ z: CGFloat) -> CGFloat { min(3, max(1, z)) }

    /// Font at 100 pt directly from the file (without login, see `MushafLayoutStore.typography`).
    static func loadFont(_ file: URL?) -> CTFont? {
        guard let file,
            let t = (CTFontManagerCreateFontDescriptorsFromURL(file as CFURL) as? [CTFontDescriptor])?.first
        else { return nil }
        return CTFontCreateWithFontDescriptor(t, 100, nil)
    }

    /// Double tap: 1× ↔ 2×.
    private func toggleMode() {
        withAnimation(.snappy) { scale = scale > 1 ? 1 : 2 }
    }

    /// The printed page: 15 lines of equal height.
    @ViewBuilder private func page(_ area: CGSize) -> some View {
        let width = area.width - 32
        let lineY = (area.height - 16 - 22) / 15
        VStack(spacing: 0) {
            if let rows {
                let metrics = metricsCache.metrics(
                    rows, page: number, contentProvider: contentProvider, typography: typography,
                    width: width,
                    lineHeight: lineY)
                // Pages 1-2 are centered in print; otherwise 15 lines from the top.
                let end = number <= 2 ? (rows.map(\.id).max() ?? 15) : 15
                VStack(spacing: 0) {
                    ForEach(1...max(end, 1), id: \.self) { n in
                        if let s = rows.first(where: { $0.id == n }) {
                            row(s, metrics: metrics, width: width, lineY: lineY)
                                .frame(width: width, height: lineY)
                                .modifier(RowAccessibility(surah: s, selectVerse: selectVerse))
                        } else {
                            Color.clear.frame(width: width, height: lineY)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            } else if loaded {
                flowingText
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // While the page font is missing, the footer says so instead of making the page look broken.
            Group {
                if loaded && !done && rows == nil && attempt >= 3 {
                    // After three attempts without a layout: final running text (retries continue in the background).
                    Text(app: "kuran.mushaf.akan")
                } else if loaded && !done {
                    Label(localized("kuran.mushaf.yukleniyor"), systemImage: "arrow.down.circle")
                        .labelStyle(.titleAndIcon)
                } else {
                    Text(verbatim: "\(number)")
                }
            }
            .typography(.footnote).foregroundStyle(theme.colors.text2)
            .lineLimit(1)
            .frame(height: 22)
        }
        .foregroundStyle(theme.colors.text)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// Wrapping from zoom > 1: the words of the page as running text at `z` times the size, vertically scrollable.
    /// Surah header and basmala interrupt the flow; verse ends stay as a glyph after their verse.
    private func timeline(_ rows: [MushafLine], _ area: CGSize, z: CGFloat) -> some View {
        // Page-font glyphs extend beyond their advance width: more margin than at 1×.
        let width = area.width - 48
        let base = metricsCache.metrics(
            rows, page: number, contentProvider: contentProvider, typography: typography, width: width,
            lineHeight: (area.height - 16 - 22) / 15)
        let size = base.size * z
        let lineY = size * 1.9
        return ScrollViewReader { scrollProxy in
            ScrollView(.vertical) {
                VStack(spacing: size * 0.3) {
                    ForEach(MushafBuilder.blocks(rows)) { b in
                        switch b {
                        case .title(_, let su):
                            // In the wrapped layout there is room: the full header band of the list with name and details.
                            if let s = contentProvider?.surah(su) {
                                SurahHeader(surah: s)
                            } else {
                                surahBanner(su, height: lineY)
                            }
                        case .basmala:
                            // As large as the words in the flow, not above.
                            Text(verbatim: contentProvider?.basmala ?? "")
                                .font(.custom(Typography.arabicFontName, fixedSize: size * 0.8))
                                .lineLimit(1)
                                .minimumScaleFactor(0.4)
                                .frame(maxWidth: .infinity)
                                .frame(height: lineY)
                        case .text(_, let items):
                            FlowLayout(interval: size * 0.25) {
                                ForEach(items.indices, id: \.self) { i in
                                    // The first word of a verse carries its identifier so that following can scroll there.
                                    let first = i == 0 || items[i - 1].verse != items[i].verse
                                    Group {
                                        switch items[i] {
                                        case .glyph(let g): glyph(g, size: size, lineY: lineY)
                                        case .word(let k): word(k, size: size * 1.1)
                                        }
                                    }
                                    .id(first ? Self.verseID(items[i].verse) : "\(i)-\(b.id)")
                                }
                            }
                            .frame(width: width)
                            // VoiceOver reads the paragraph like a line at 1× (words, verse numbers, actions).
                            .modifier(
                                RowAccessibility(surah: MushafBlock.row(items), selectVerse: selectVerse))
                        }
                    }
                    Text(verbatim: "\(number)").typography(.footnote).foregroundStyle(theme.colors.text2)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
                .foregroundStyle(theme.colors.text)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.automatic)
            // Text fades softly under the title bar instead of being cut off hard.
            .scrollEdgeEffectStyle(.soft, for: .top)
            .onScrollPhaseChange { _, y in if y == .interacting { scrolledManually() } }
            .onChange(of: player.current) { _, s in scrollToCurrent(s, scrollProxy) }
            .onChange(of: following) { _, t in if t { scrollToCurrent(player.current, scrollProxy) } }
            .onChange(of: openVerse) { _, a in
                guard case .verse(let su, let n)? = a else { return }
                withAnimation { scrollProxy.scrollTo(Self.verseID((su, n)), anchor: .top) }
            }
            .onAppear { scrollToCurrent(player.current, scrollProxy, animated: false) }
        }
    }

    static func verseID(_ a: (Int, Int)) -> String { "ayet-\(a.0):\(a.1)" }

    /// Word being played strongly, the verse of the open verse sheet lightly ().
    private func markerColor(_ playing: Bool, _ surah: Int, _ verse: Int) -> Color {
        if playing { return theme.colors.accent.opacity(0.25) }
        return openVerse == .verse(surah: surah, verse: verse) ? theme.colors.accent.opacity(0.13) : .clear
    }

    /// In the wrapped layout scroll to the verse being played, as long as following is on and it is on this page.
    private func scrollToCurrent(
        _ s: RecitationPlayer.QueueItem?, _ scrollProxy: ScrollViewProxy, animated: Bool = true
    ) {
        guard following, let s, !s.basmala, let contentProvider,
            let b = edition.interval(number, contentProvider),
            let su = contentProvider.surah(s.surah)
        else { return }
        let index = su.firstIndex + s.verse - 1
        guard (b.first...b.end).contains(index) else { return }
        if animated {
            withAnimation { scrollProxy.scrollTo(Self.verseID((s.surah, s.verse)), anchor: .center) }
        } else {
            scrollProxy.scrollTo(Self.verseID((s.surah, s.verse)), anchor: .center)
        }
    }

    /// The same ornamental band as in the list, fitted into the line height.
    /// At 1× number/name and Meccan/Medinan·verse count are shown small in the band (no extra line free).
    private func surahBanner(_ su: Int, height: CGFloat) -> some View {
        let s = contentProvider?.surah(su)
        return SurahBand(
            nameArabic: s?.nameArabic ?? "", height: height * 0.8,
            sol: s.map {
                Text(
                    app: $0.revelationPlace == .meccan
                        ? "kuran.sure.alt.mekki \($0.verseCount)" : "kuran.sure.alt.medeni \($0.verseCount)")
            },
            sag: s.map { Text(verbatim: "\($0.number) · \($0.name(language: translationLanguage()))") }
        )
        .frame(height: height)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private func row(
        _ s: MushafLine, metrics: MushafMetrics.Metrics, width: CGFloat, lineY: CGFloat
    ) -> some View {
        switch s {
        case .surahTitle(_, let su):
            surahBanner(su, height: lineY)
        case .basmala:
            Text(verbatim: contentProvider?.basmala ?? "")
                .font(.custom(Typography.arabicFontName, fixedSize: lineY * 0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .glyphs(let n, let l):
            JustifiedLine(centered: metrics.centeredLines.contains(n)) {
                ForEach(l) { glyph($0, size: metrics.size, lineY: lineY) }
            }
            .frame(width: width)
        case .words(let n, let l):
            JustifiedLine(centered: metrics.centeredLines.contains(n)) {
                ForEach(l) { word($0, size: metrics.lineSize[n] ?? metrics.size) }
            }
            .frame(width: width)
        }
    }

    private func glyph(_ g: MushafGlyph, size: CGFloat, lineY: CGFloat) -> some View {
        let tanzil = MushafBuilder.tanzil(g.surah, g.verse, g.word)
        let playing: Bool = {
            guard !g.end, let c = player.current, !c.basmala, c.surah == g.surah, c.verse == g.verse,
                let k = player.currentWord
            else { return false }
            return tanzil.contains(k)
        }()
        // Preview on long press: the word in the ordinary Arabic font (Tanzil text).
        let text =
            g.end
            ? nil
            : tanzil.compactMap {
                contentProvider?.words(.word(surah: g.surah, verse: g.verse, index: $0)).first?.text
            }.joined(separator: " ")
        return Text(verbatim: g.code)
            .font(
                typography.map { Font(CTFontCreateCopyWithAttributes($0, size, nil, nil)) }
                    ?? .custom(Typography.arabicFontName, fixedSize: size)
            )
            .modifier(TajweedOnDark(light: tajweedInverted && typography != nil && theme.colors.dark))
            .fixedSize()
            .frame(height: lineY)
            .background(markerColor(playing, g.surah, g.verse), in: .rect(cornerRadius: 4))
            .contentShape(.rect)
            .modifier(
                VerseTouch(
                    surah: g.surah, verse: g.verse,
                    word: g.end ? nil : .word(surah: g.surah, verse: g.verse, index: tanzil.lowerBound),
                    wordText: text, selectVerse: selectVerse, doubleTap: toggleMode))
    }

    private func word(_ k: Word, size: CGFloat) -> some View {
        let playing: Bool = {
            guard case .word(let s, let a, let n) = k.key, let c = player.current, !c.basmala else {
                return false
            }
            return c.surah == s && c.verse == a && player.currentWord == n
        }()
        let (s, a): (Int, Int) = {
            if case .word(let s, let a, _) = k.key { return (s, a) }
            return (0, 0)
        }()
        return Text(verbatim: MushafMetrics.wordText(k, contentProvider))
            .font(.custom(Typography.arabicFontName, fixedSize: size))
            .fixedSize()
            .frame(maxHeight: size * 2.2)
            .background(markerColor(playing, s, a), in: .rect(cornerRadius: 4))
            .contentShape(.rect)
            .modifier(
                VerseTouch(
                    surah: s, verse: a, word: k.key, wordText: k.text, selectVerse: selectVerse,
                    doubleTap: toggleMode))
    }

    /// Without a layout (offline on first opening): page text wrapped and scaled down so far
    /// that the whole page fits in the frame - nothing disappears under the tab bar.
    private var flowingText: some View {
        let verses: [Verse] = {
            guard let contentProvider, let b = edition.interval(number, contentProvider) else { return [] }
            return (b.first...b.end).compactMap {
                contentProvider.key(index: $0).flatMap { contentProvider.verse($0) }
            }
        }()
        return VStack(spacing: 8) {
            Text(verbatim: verses.map { $0.text + " " + verseEnd($0.verse) }.joined(separator: " "))
                .typography(.arabic(size: settings.arabicSize))
                .multilineTextAlignment(.trailing)
                .lineSpacing(settings.arabicSize * 0.2)
                .minimumScaleFactor(0.3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
    }
}

/// Tapping opens the verse sheet; a long press speaks the word (Quran.com word recording, as in
/// `WordFlow`) and offers listen from here/bookmark. A double tap zooms; the single tap
/// therefore waits until it is clear that no second one follows.
private struct VerseTouch: ViewModifier {
    @Environment(\.contentProvider) private var contentProvider
    @Environment(AppSettings.self) private var settings
    @Environment(UserStore.self) private var store
    @Environment(RecitationPlayer.self) private var player
    let surah: Int
    let verse: Int
    /// Tanzil word for the word recording; nil for the end-of-verse mark.
    let word: ContentKey?
    let wordText: String?
    let selectVerse: (Verse) -> Void
    let doubleTap: () -> Void

    func body(content: Content) -> some View {
        let tapped =
            content
            .gesture(
                TapGesture(count: 2).onEnded { doubleTap() }
                    .exclusively(
                        before: TapGesture().onEnded {
                            if let a = contentProvider?.verse(.verse(surah: surah, verse: verse)) {
                                selectVerse(a)
                            }
                        })
            )
        if let word, let wordText, !wordText.isEmpty {
            tapped
                .contextMenu {
                    Button(localized("kuran.kelime.dinle"), systemImage: "speaker.wave.2") {
                        WordAudio.shared.play(word)
                    }
                    menu
                } preview: {
                    Text(verbatim: wordText).typography(.arabic(size: 44))
                        .padding(24)
                        .onAppear { WordAudio.shared.play(word) }
                }
        } else {
            tapped.contextMenu { menu }
        }
    }

    @ViewBuilder private var menu: some View {
        if let su = contentProvider?.surah(surah) {
            Button(localized("kuran.oynatici.buradan"), systemImage: "play.fill") {
                player.reciter = Reciter.find(settings.reciter)
                player.play(surah: surah, verseCount: su.verseCount, verse: verse)
            }
            Button(localized("kuran.kaydet"), systemImage: "bookmark") {
                store.toggleSaved(ContentKey.verse(surah: surah, verse: verse).text)
            }
        }
    }
}

/// VoiceOver per Mushaf line: the page-font glyphs mean nothing to VoiceOver, so
/// the line reads the Tanzil words including verse numbers and offers verse sheet and listen as actions.
/// See `tajweedInverted`: invert plus 180° hue = same colors, inverted lightness.
private struct TajweedOnDark: ViewModifier {
    let light: Bool

    func body(content: Content) -> some View {
        if light { content.colorInvert().hueRotation(.degrees(180)) } else { content }
    }
}

private struct RowAccessibility: ViewModifier {
    @Environment(\.contentProvider) private var contentProvider
    @Environment(AppSettings.self) private var settings
    @Environment(RecitationPlayer.self) private var player
    let surah: MushafLine
    let selectVerse: (Verse) -> Void

    func body(content: Content) -> some View {
        switch surah {
        case .surahTitle, .basmala:
            content
        case .glyphs, .words:
            if let (s, a, text) = transliteration {
                content
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: text))
                    .accessibilityAction(named: localized("kuran.mushaf.ayet_ac")) {
                        if let verse = contentProvider?.verse(.verse(surah: s, verse: a)) {
                            selectVerse(verse)
                        }
                    }
                    .accessibilityAction(named: localized("kuran.oynatici.buradan")) {
                        guard let su = contentProvider?.surah(s) else { return }
                        player.reciter = Reciter.find(settings.reciter)
                        player.play(surah: s, verseCount: su.verseCount, verse: a)
                    }
            } else {
                content
            }
        }
    }

    /// First verse of the line and its text in Tanzil script, verse ends as „(n)“.
    private var transliteration: (Int, Int, String)? {
        guard let contentProvider else { return nil }
        var parts: [String] = []
        var first: (Int, Int)?
        switch surah {
        case .glyphs(_, let l):
            for g in l {
                if first == nil { first = (g.surah, g.verse) }
                if g.end {
                    parts.append("(\(g.verse))")
                } else {
                    parts += MushafBuilder.tanzil(g.surah, g.verse, g.word).compactMap {
                        contentProvider.words(.word(surah: g.surah, verse: g.verse, index: $0)).first?.text
                    }
                }
            }
        case .words(_, let l):
            for k in l {
                guard case .word(let s, let a, let n) = k.key else { continue }
                if first == nil { first = (s, a) }
                parts.append(k.text)
                if n == contentProvider.verse(.verse(surah: s, verse: a))?.words.count {
                    parts.append("(\(a))")
                }
            }
        default:
            return nil
        }
        guard let first else { return nil }
        return (first.0, first.1, parts.joined(separator: " "))
    }
}

/// Justified: words in reading direction, spacing distributed evenly (short lines centered).
/// If a line does not fit, the words move together down to 1 pt; `MushafMetrics` picks the size
/// so that this does not happen.
struct JustifiedLine: Layout {
    var centered: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let b = subviews.map { $0.sizeThatFits(.unspecified) }
        return CGSize(
            width: proposal.width ?? b.reduce(0) { $0 + $1.width }, height: b.map(\.height).max() ?? 0)
    }

    func placeSubviews(in r: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let b = subviews.map { $0.sizeThatFits(.unspecified) }
        let total = b.reduce(0) { $0 + $1.width }
        let interval = CGFloat(max(1, subviews.count - 1))
        let gap =
            centered || subviews.count < 2
            ? min(8, max(1, (r.width - total) / interval)) : max(1, (r.width - total) / interval)
        let full = total + gap * CGFloat(max(0, subviews.count - 1))
        // Layout is mirrored in RTL: x grows in reading direction.
        var x = r.minX + (centered ? max(0, (r.width - full) / 2) : 0)
        for (i, v) in subviews.enumerated() {
            v.place(at: CGPoint(x: x, y: r.midY), anchor: .leading, proposal: ProposedViewSize(b[i]))
            x += b[i].width + gap
        }
    }
}

/// One font size per page at which the longest line just fits; shorter lines are centered.
enum MushafMetrics {
    struct Metrics {
        let size: CGFloat
        /// Line numbers that are centered instead of justified.
        let centeredLines: Set<Int>
        /// Without QCF font: smaller size for lines that overflowed with `size`.
        let lineSize: [Int: CGFloat]

        /// The same measurement for the page enlarged `z` times (everything scales linearly).
        func carp(_ z: CGFloat) -> Metrics {
            Metrics(size: size * z, centeredLines: centeredLines, lineSize: lineSize.mapValues { $0 * z })
        }
    }

    /// Remembers the measurement per size so that highlighting during playback does not re-measure every time.
    @MainActor final class Cache {
        private var end: (key: String, metrics: Metrics)?

        func metrics(
            _ rows: [MushafLine], page: Int, contentProvider: (any ContentProvider)?, typography: CTFont?,
            width: CGFloat,
            lineHeight: CGFloat
        ) -> Metrics {
            let key =
                "\(typography.map { CTFontCopyPostScriptName($0) as String } ?? "-")|\(width)|\(lineHeight)|\(rows.count)"
            if let end, end.key == key { return end.metrics }
            let o = MushafMetrics.measure(
                rows, page: page, contentProvider: contentProvider, typography: typography, width: width,
                lineHeight: lineHeight)
            end = (key, o)
            return o
        }
    }

    /// Minimum spacing between two words, relative to 100 pt.
    static let gap: CGFloat = 10

    static func measureWidth(_ text: String, _ f: CTFont) -> CGFloat {
        let s = NSAttributedString(
            string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): f])
        return CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(s), nil, nil, nil))
    }

    /// Word together with the end-of-verse mark if it is the last of the verse (only without QCF font).
    @MainActor static func wordText(_ k: Word, _ contentProvider: (any ContentProvider)?) -> String {
        if case .word(let s, let a, let n) = k.key,
            n == (contentProvider?.verse(.verse(surah: s, verse: a))?.words.count ?? 0)
        {
            return k.text + " " + verseEnd(a)
        }
        return k.text
    }

    @MainActor static func measure(
        _ rows: [MushafLine], page: Int, contentProvider: (any ContentProvider)?, typography: CTFont?,
        width: CGFloat,
        lineHeight: CGFloat
    ) -> Metrics {
        let f = typography ?? CTFontCreateWithName(Typography.arabicFontName as CFString, 100, nil)
        // Height: with QCF the line carries harakat above and below the word; the width almost always binds.
        // Fallback font: from its real line measure (Amiri ≈ 1.8 em with harakat) so that 15 lines fit.
        let em = (CTFontGetAscent(f) + CTFontGetDescent(f)) / 100
        let parent = typography == nil ? min(30, lineHeight / max(1.2, em)) : min(60, lineHeight * 0.75)
        var widths: [Int: (CGFloat, Int)] = [:]
        for s in rows {
            switch s {
            case .glyphs(let n, let l):
                widths[n] = (l.map { measureWidth($0.code, f) }.reduce(0, +), l.count)
            case .words(let n, let l):
                widths[n] = (l.map { measureWidth(wordText($0, contentProvider), f) }.reduce(0, +), l.count)
            default:
                break
            }
        }
        let dogal = widths.mapValues { $0.0 + CGFloat(max(0, $0.1 - 1)) * gap }
        let longest = widths.filter { $0.value.1 > 3 }.keys.compactMap { dogal[$0] }.max() ?? 0
        // 4 % headroom: calligraphic glyphs extend beyond their advance width.
        let usable = width * 0.96
        let size = longest > 0 ? min(parent, 100 * usable / longest) : parent
        var centeredLines = Set<Int>()
        var lineSize: [Int: CGFloat] = [:]
        for (n, w) in dogal {
            let scaled = w * size / 100
            if scaled > usable { lineSize[n] = 100 * usable / w }
            // Short lines (pages 1-2, end of a surah) centered, everything else justified as in print.
            if page <= 2 || scaled < width * 0.7 { centeredLines.insert(n) }
        }
        return Metrics(size: size, centeredLines: centeredLines, lineSize: lineSize)
    }
}

extension CGSize {
    fileprivate static func + (l: CGSize, r: CGSize) -> CGSize {
        CGSize(width: l.width + r.width, height: l.height + r.height)
    }
}
