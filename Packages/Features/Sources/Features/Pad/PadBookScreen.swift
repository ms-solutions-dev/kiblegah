import ContentPacks
import Core
import DesignSystem
import Quran
import SwiftUI
import UserData

#if os(iOS)
    import UIKit

    /// „Seite“ on the iPad.
    /// Landscape shows the open spread, portrait a single page; pages turn with a curl. A tap on the spine (in
    /// portrait at the bottom center) brings the controls. There is no permanent bar: the next prayer sits in the
    /// controls. Above 1× the words reflow, which no curl can carry; then it pages sideways and scrolls.
    struct PadBookScreen: View {
        @Environment(\.contentProvider) private var contentProvider
        @Environment(AppSettings.self) private var settings
        @Environment(UserStore.self) private var store
        @Environment(RecitationPlayer.self) private var player
        @Environment(\.theme) private var theme
        @Environment(\.dismiss) private var dismiss
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        /// Page in the app's numbering (V1).
        let start: Int
        /// Back to the verse mode, with the verse on top of the page.
        let closeAt: (ContentKey?) -> Void

        @State private var page = 1
        @State private var started = false
        @State private var chrome = false
        @State private var selected: Verse?
        @State private var aaOpen = false
        @State private var jumpOpen = false
        @State private var settingsOpen = false
        @State private var readingVerse: Verse?
        @State private var following = true
        @State private var turn = PadBookTurn()
        @AppStorage("mushafOlcek", store: GroupDefaults.d) private var scale: Double = 1
        @AppStorage("ipad.buch.hinweis", store: GroupDefaults.d) private var hintSeen = false
        @State private var showHint = false

        private var edition: MushafEdition { MushafEdition(setting: settings.mushafEdition) }

        /// Auto is the bright paper on a light theme, the dark one otherwise.
        private var tokens: ColorTokens {
            let paper = ReadingPaper(setting: settings.readingPaper)
            if paper == .auto {
                return (theme.colors.dark ? ReadingPaper.dark : .paper).tokens(base: theme.colors)
            }
            return paper.tokens(base: theme.colors)
        }

        private var bookTheme: Theme {
            Theme(colors: tokens, largeAndSimple: theme.largeAndSimple, force: theme.force)
        }

        var body: some View {
            GeometryReader { g in
                let spread = g.size.width > g.size.height && g.size.width >= 900
                ZStack {
                    desk.ignoresSafeArea()
                    book(g.size, spread: spread)
                    controls(spread: spread)
                    followButton
                    if let selected { detail(selected) }
                }
            }
            .ignoresSafeArea()
            .statusBarHidden(true)
            .persistentSystemOverlays(chrome ? .automatic : .hidden)
            .sheet(item: $readingVerse) { ReadingOptions(verse: $0) }
            .sheet(isPresented: $settingsOpen) { ReadingSettings() }
            .onAppear {
                guard !started else { return }
                started = true
                // The first time the controls show themselves, with a word on how they come back.
                if !hintSeen {
                    hintSeen = true
                    chrome = true
                    showHint = true
                    Task {
                        try? await Task.sleep(for: .seconds(5))
                        withAnimation { showHint = false }
                    }
                }
                if let contentProvider {
                    page = MushafEdition.v1.convert(start, nach: edition, contentProvider)
                }
                #if DEBUG
                    let d = UserDefaults.standard
                    if d.bool(forKey: "ipadSteuerung") { chrome = true }
                    if d.bool(forKey: "ipadVers"), let v = firstVerse { selected = v }
                #endif
            }
            .onChange(of: page) { _, n in
                guard let contentProvider, let b = edition.interval(n, contentProvider) else { return }
                QuranPosition.shared.save(b.first, .mushaf)
            }
            .onChange(of: edition) { old, yeni in
                guard let contentProvider else { return }
                page = old.convert(page, nach: yeni, contentProvider)
            }
            .onChange(of: player.current) { _, s in
                guard following, let s else { return }
                goToPage(surah: s.surah, verse: s.verse)
            }
            .onChange(of: player.queue) { following = true }
            .task(id: page) { await read(page) }
            .task { await MushafLayoutStore.shared.clear() }
            .environment(\.openVerse, selected?.key)
        }

        /// While listening and paged away: back to the verse being read, as in the reader.
        @ViewBuilder private var followButton: some View {
            if player.isActive, !following {
                FollowAlongButton {
                    following = true
                    if let s = player.current { goToPage(surah: s.surah, verse: s.verse) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.bottom, chrome ? 80 : 12)
            }
        }

        private var desk: some View {
            RadialGradient(
                colors: PadColor.desk,
                center: UnitPoint(x: 0.5, y: 0), startRadius: 0, endRadius: 1000)
        }

        @ViewBuilder private func book(_ size: CGSize, spread: Bool) -> some View {
            let margin = EdgeInsets(
                top: 26, leading: spread ? 30 : 28, bottom: 26, trailing: spread ? 30 : 28)
            ZStack {
                if scale > 1.01 {
                    reflowPager
                } else {
                    #if os(iOS)
                        PadCurlPager(
                            page: $page, spread: spread, turn: turn,
                            makePage: { n in AnyView(pageHost(n, spread: spread)) },
                            userTurned: { if player.isActive { following = false } }
                        )
                        .id(spread)
                    #endif
                }
                if spread {
                    // The fold in the middle of the open book.
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.20), location: 0.46),
                            .init(color: .black.opacity(0.30), location: 0.5),
                            .init(color: .black.opacity(0.20), location: 0.54),
                            .init(color: .clear, location: 1),
                        ], startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: 70)
                    .allowsHitTesting(false)
                }
                turnZones(spread: spread)
            }
            .clipShape(.rect(cornerRadius: 6))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 24)
            .padding(margin)
        }

        /// Reflowed text: one page, side by side as on the iPhone.
        private var reflowPager: some View {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(1...604, id: \.self) { n in
                        pageHost(n, spread: false)
                            .containerRelativeFrame(.horizontal)
                            .id(n)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: Binding(get: { page }, set: { if let n = $0 { page = n } }))
            .scrollIndicators(.hidden)
            .environment(\.layoutDirection, .rightToLeft)
        }

        /// One page on the paper: head with juz and surah, the page itself, optionally the transcription.
        private func pageHost(_ n: Int, spread: Bool) -> some View {
            PadBookPage(
                number: n, edition: edition, scale: $scale, following: following,
                scrolledManually: { if player.isActive { following = false } },
                select: { selected = $0 }
            )
            .environment(\.theme, bookTheme)
            .environment(settings)
            .environment(store)
            .environment(player)
            .environment(\.contentProvider, contentProvider)
            .environment(\.openVerse, selected?.key)
        }

        /// Corners turn the page, the spine (in portrait the bottom center) brings the controls.
        private func turnZones(spread: Bool) -> some View {
            ZStack {
                HStack {
                    corner(leading: true) { turn.forward?() }
                    Spacer()
                    corner(leading: false) { turn.backward?() }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                Button {
                    toggleChrome()
                } label: {
                    Color.clear.contentShape(.rect)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: spread ? 60 : nil)
                .frame(width: spread ? 60 : nil, height: spread ? nil : 90)
                .padding(.horizontal, spread ? 0 : 190)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .accessibilityLabel(localized("ipad.buch.steuerung"))
            }
        }

        private func corner(leading: Bool, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                LinearGradient(
                    colors: [.black.opacity(0.3), .clear],
                    startPoint: leading ? .bottomLeading : .bottomTrailing, endPoint: .center
                )
                .clipShape(PadCorner(leading: leading))
                .frame(width: 96, height: 96)
                .contentShape(PadCorner(leading: leading))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localized(leading ? "ipad.buch.weiter" : "ipad.buch.zurueck"))
        }

        private func toggleChrome() {
            withAnimation(reduceMotion ? nil : .timingCurve(0.3, 0.9, 0.3, 1, duration: 0.45)) {
                chrome.toggle()
            }
        }

        // MARK: Controls

        @ViewBuilder private func controls(spread: Bool) -> some View {
            VStack(spacing: 0) {
                if chrome {
                    topControls
                        .padding(.horizontal, 24).padding(.top, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer(minLength: 0)
                if showHint {
                    Text(app: spread ? "ipad.buch.hinweis.falz" : "ipad.buch.hinweis.unten")
                        .typography(.label(size: 15))
                        .foregroundStyle(theme.colors.text)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.bottom, 12)
                        .transition(.opacity)
                }
                if chrome {
                    bottomControls(spread: spread)
                        .padding(.horizontal, 24).padding(.bottom, 14)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }

        private var topControls: some View {
            HStack {
                Button {
                    close()
                } label: {
                    Label(localized("genel.kapat"), systemImage: "chevron.left")
                        .typography(.label(size: 15))
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .glassEffect(.regular, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                Spacer()
                HStack(spacing: 8) {
                    Button {
                        jumpOpen = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "text.justify.left")
                            Text(verbatim: spreadTitle).lineLimit(1)
                            Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                        }
                        .typography(.label(size: 15))
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .glassEffect(.regular, in: .capsule)
                        .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(localized("kuran.mushaf.git.ipucu"))
                    .popover(isPresented: $jumpOpen) {
                        MushafJumpSheet(current: page, edition: edition, git: { page = $0 })
                            .frame(width: 400, height: 480)
                            .presentationCompactAdaptation(.popover)
                    }
                    HStack(spacing: 0) {
                        Button {
                            close()
                        } label: {
                            Text(app: "ipad.koran.vers").typography(.label(size: 15))
                                .padding(.horizontal, 18).frame(minHeight: 44)
                                .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        Text(app: "ipad.koran.seite").typography(.label(size: 15))
                            .padding(.horizontal, 18).frame(minHeight: 44)
                            .background(theme.colors.surface, in: .capsule)
                            .accessibilityAddTraits(.isSelected)
                    }
                    .padding(4)
                    .glassEffect(.regular, in: .capsule)
                }
                Spacer()
                Button {
                    aaOpen = true
                } label: {
                    Text(verbatim: "Aa").typography(.display(size: 17))
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular, in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(localized("kuran.okuma_ayarlari"))
                .popover(isPresented: $aaOpen) {
                    PadAaPopover(forBook: true) { settingsOpen = true }
                }
            }
            .foregroundStyle(theme.colors.text)
        }

        private func bottomControls(spread: Bool) -> some View {
            let slider = HStack(spacing: 14) {
                // The book reads from the right, so does the slider: the current page stands on that side.
                Text(verbatim: "604").typography(.label(size: 13)).monospacedDigit()
                    .foregroundStyle(theme.colors.text2)
                Slider(
                    value: Binding(
                        get: { Double(page) },
                        set: { page = Int($0) }),
                    in: 1...604, step: 1
                )
                .environment(\.layoutDirection, .rightToLeft)
                .tint(theme.colors.accent)
                .accessibilityLabel(localized("ipad.buch.seite_waehlen"))
                .accessibilityValue("\(page)")
                Text(verbatim: pageLabel(spread: spread)).typography(.label(size: 13)).monospacedDigit()
                    .frame(minWidth: 56, alignment: .trailing)
            }
            .padding(.horizontal, 24)
            .frame(height: 64)
            .glassEffect(.regular, in: .capsule)
            let rest = HStack(spacing: 12) {
                PrayerBand(style: .chip)
                if player.isActive {
                    PadPlayerBar(width: 300, compact: true)
                } else if let v = firstVerse {
                    PadListenCapsule(
                        title: localized("ipad.koran.hoeren \(currentSurahName)"), width: 300,
                        framed: false
                    ) { readingVerse = v }
                }
            }
            return Group {
                if spread {
                    HStack(spacing: 12) {
                        slider
                        rest
                    }
                } else {
                    VStack(spacing: 10) {
                        slider
                        rest
                    }
                }
            }
            .foregroundStyle(theme.colors.text)
        }

        /// The verse detail lies over the book; „Meal der Seite“ is the list for the page, the book itself only
        /// ever shows the Quran.
        private func detail(_ verse: Verse) -> some View {
            ZStack {
                Color.black.opacity(0.35).ignoresSafeArea()
                    .onTapGesture { selected = nil }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(localized("genel.kapat"))
                // Links in the detail (hadith, source) need a stack; the book is not inside one.
                NavigationStack {
                    VerseSheet(
                        verse: verse, embedded: true, closeEmbedded: { selected = nil },
                        pageVerses: versesOfVisiblePages,
                        changed: { y in
                            if selected?.index != y.index {
                                selected = y
                                goToPage(surah: y.surah, verse: y.verse)
                            }
                        }
                    )
                    .hideTopBar()
                    .navigationDestination(for: Goal.self) { GoalScreen(goal: $0) }
                }
                .frame(width: 500)
                .frame(maxHeight: 620)
                .background(theme.colors.surface, in: .rect(cornerRadius: 26))
                .clipShape(.rect(cornerRadius: 26))
                .shadow(color: .black.opacity(0.28), radius: 30, y: 20)
                .transition(.scale(scale: 0.97).combined(with: .opacity))
            }
        }

        // MARK: Position

        private func close() {
            closeAt(firstVerse?.key)
            dismiss()
        }

        private var firstVerse: Verse? {
            guard let contentProvider, let b = edition.interval(page, contentProvider),
                let k = contentProvider.key(index: b.first)
            else { return nil }
            return contentProvider.verse(k)
        }

        private var versesOfVisiblePages: [Verse] {
            guard let contentProvider, let b = edition.interval(page, contentProvider) else { return [] }
            var last = b.end
            if let n = edition.interval(PadCurlPager.partner(of: page), contentProvider) {
                last = max(last, n.end)
            }
            let first = min(
                b.first, edition.interval(PadCurlPager.partner(of: page), contentProvider)?.first ?? b.first)
            return (first...last).compactMap {
                contentProvider.key(index: $0).flatMap { contentProvider.verse($0) }
            }
        }

        private var currentSurahName: String {
            guard let v = firstVerse else { return "" }
            return contentProvider?.surah(v.surah)?.name(language: translationLanguage()) ?? ""
        }

        private var spreadTitle: String {
            guard let contentProvider, let b = edition.interval(page, contentProvider),
                case .verse(let s, _) = contentProvider.key(index: b.first)
            else { return localized("kuran.mushaf") }
            return contentProvider.surah(s)?.name(language: translationLanguage()) ?? ""
        }

        private func pageLabel(spread: Bool) -> String {
            guard spread else { return localized("kuran.sayfa.kisa \(page)") }
            let other = PadCurlPager.partner(of: page)
            return localized("ipad.buch.seiten \(min(page, other)) \(max(page, other))")
        }

        private func goToPage(surah: Int, verse: Int) {
            guard let contentProvider,
                let yeni = edition.page(surah: surah, verse: max(verse, 1), contentProvider), yeni != page
            else { return }
            page = yeni
        }

        /// The same bookkeeping as the Mushaf: preload, last position, a page open for 8 s counts as read.
        private func read(_ page: Int) async {
            let s = edition
            let dark = bookTheme.colors.dark
            let server = MushafLayoutStore.server()
            Task(priority: .utility) {
                let store = MushafLayoutStore.shared
                for n in [page + 1, page - 1, page + 2, page + 3] where (1...604).contains(n) {
                    _ = await store.layout(n, server: server, edition: s)
                    _ = await store.typography(n, edition: s, dark: dark)
                }
            }
            guard let contentProvider, let b = edition.interval(page, contentProvider) else { return }
            if let k = contentProvider.key(index: b.first) {
                store.saveLastPosition(k.text, khatm: settings.activeKhatm)
            }
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            store.addReading(firstIndex: b.first, lastIndex: b.end, seconds: 8, khatm: settings.activeKhatm)
        }
    }

    /// Lets the corners turn the page of the pager, which holds the controller.
    @MainActor final class PadBookTurn {
        var forward: (() -> Void)?
        var backward: (() -> Void)?
    }

    /// The triangle of a page corner.
    struct PadCorner: Shape {
        let leading: Bool
        func path(in r: CGRect) -> Path {
            var p = Path()
            if leading {
                p.move(to: CGPoint(x: r.minX, y: r.maxY))
                p.addLine(to: CGPoint(x: r.minX, y: r.minY))
                p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            } else {
                p.move(to: CGPoint(x: r.maxX, y: r.maxY))
                p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
                p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            }
            p.closeSubpath()
            return p
        }
    }

    /// One page of the book on its paper.
    struct PadBookPage: View {
        @Environment(\.contentProvider) private var contentProvider
        @Environment(AppSettings.self) private var settings
        @Environment(\.theme) private var theme
        let number: Int
        let edition: MushafEdition
        @Binding var scale: Double
        let following: Bool
        let scrolledManually: () -> Void
        let select: (Verse) -> Void

        var body: some View {
            VStack(spacing: 0) {
                head
                if settings.bookTranscription {
                    PadTranscribedPage(number: number, edition: edition, select: select)
                } else {
                    MushafPage(
                        number: number, edition: edition, scale: $scale, following: following,
                        scrolledManually: scrolledManually, selectVerse: select
                    )
                }
            }
            .environment(\.layoutDirection, .leftToRight)
            .foregroundStyle(theme.colors.text)
            .background(theme.colors.background)
        }

        /// „Cüz 1“ and the surahs of the page, printed above the text as in a book.
        private var head: some View {
            let names: String = {
                guard let contentProvider, let b = edition.interval(number, contentProvider) else {
                    return ""
                }
                var surahs: [Int] = []
                for i in b.first...b.end {
                    if case .verse(let s, _)? = contentProvider.key(index: i), surahs.last != s {
                        surahs.append(s)
                    }
                }
                return surahs.compactMap { contentProvider.surah($0)?.name(language: translationLanguage()) }
                    .joined(separator: " · ")
            }()
            let juz: Int = {
                guard let contentProvider, let b = edition.interval(number, contentProvider),
                    let k = contentProvider.key(index: b.first)
                else { return 1 }
                return contentProvider.verse(k)?.juz ?? 1
            }()
            return HStack {
                Text(app: "ipad.buch.cuz \(juz)")
                Spacer()
                Text(verbatim: names).lineLimit(1)
            }
            .typography(.label(size: 13))
            .tracking(0.6)
            .foregroundStyle(theme.colors.label)
            .padding(.horizontal, 36).padding(.top, 24).padding(.bottom, 10)
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.colors.label.opacity(0.3)).frame(height: 1).padding(.horizontal, 36)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// With the transcription switched on there is no fixed grid of lines: verse, reading, verse, reading, scrolling
    /// inside the page. The reading follows the language of the app and is marked as unreviewed.
    struct PadTranscribedPage: View {
        @Environment(\.contentProvider) private var contentProvider
        @Environment(\.theme) private var theme
        let number: Int
        let edition: MushafEdition
        let select: (Verse) -> Void

        private var language: String { translationLanguage() == "tr" ? "tr" : "en" }

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(app: "ipad.aa.transkription.hinweis").typography(.footnote).foregroundStyle(
                        theme.colors.text2)
                    if let contentProvider, let b = edition.interval(number, contentProvider) {
                        ForEach(Array(b.first...b.end), id: \.self) { i in
                            if let k = contentProvider.key(index: i), let v = contentProvider.verse(k) {
                                Button {
                                    select(v)
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(verbatim: v.text + " " + verseEnd(v.verse))
                                            .typography(.arabic(size: 24))
                                            .multilineTextAlignment(.trailing)
                                            .frame(maxWidth: .infinity, alignment: .trailing)
                                        if let o = contentProvider.transliteration(v.key, language: language)
                                        {
                                            Text(verbatim: o.text).typography(.secondary).foregroundStyle(
                                                theme.colors.text2
                                            )
                                            .multilineTextAlignment(.leading)
                                        }
                                    }
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Text(verbatim: "\(number)").typography(.display(size: 15)).foregroundStyle(
                        theme.colors.label
                    )
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 36).padding(.vertical, 14)
            }
        }
    }

    /// The curl. UIKit has it, SwiftUI does not. The book reads from the right: the page controller's order runs
    /// from the end of the Quran to its start, so the leaf on the left is the next page, as in print.
    struct PadCurlPager: UIViewControllerRepresentable {
        @Binding var page: Int
        let spread: Bool
        let turn: PadBookTurn
        let makePage: (Int) -> AnyView
        let userTurned: () -> Void

        /// The other page of the open spread: odd pages lie on the right, the next even one on the left.
        static func partner(of page: Int) -> Int {
            page % 2 == 1 ? min(604, page + 1) : page - 1
        }

        func makeCoordinator() -> Coordinator { Coordinator(self) }

        func makeUIViewController(context: Context) -> UIPageViewController {
            let pager = UIPageViewController(
                transitionStyle: .pageCurl, navigationOrientation: .horizontal,
                options: [.spineLocation: (spread ? UIPageViewController.SpineLocation.mid : .max).rawValue])
            pager.isDoubleSided = spread
            pager.dataSource = context.coordinator
            pager.delegate = context.coordinator
            pager.view.backgroundColor = .clear
            // Taps belong to the words of the page; only dragging turns.
            for r in pager.gestureRecognizers where r is UITapGestureRecognizer { r.isEnabled = false }
            context.coordinator.show(page, in: pager, animated: false, direction: .forward)
            context.coordinator.shown = page
            turn.forward = { [weak pager, weak coordinator = context.coordinator] in
                guard let pager, let coordinator else { return }
                coordinator.step(+1, in: pager)
            }
            turn.backward = { [weak pager, weak coordinator = context.coordinator] in
                guard let pager, let coordinator else { return }
                coordinator.step(-1, in: pager)
            }
            return pager
        }

        func updateUIViewController(_ pager: UIPageViewController, context: Context) {
            let c = context.coordinator
            c.parent = self
            guard !c.turning, !c.showsPage(page) else { return }
            // Jump or slider: forward means toward the higher page, on the left.
            let forward = page > c.shown
            c.shown = page
            c.show(
                page, in: pager, animated: !UIAccessibility.isReduceMotionEnabled,
                direction: forward ? .reverse : .forward)
        }

        @MainActor
        final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
            var parent: PadCurlPager
            var shown = 1
            var turning = false
            private var cache: [Int: PageHost] = [:]

            init(_ parent: PadCurlPager) { self.parent = parent }

            /// The pages on screen, left then right; the first page of a spread is its right one.
            private func pages(for page: Int) -> [Int] {
                guard parent.spread else { return [page] }
                let right = page % 2 == 1 ? page : page - 1
                return right < 604 ? [right + 1, right] : [right]
            }

            func showsPage(_ page: Int) -> Bool {
                if parent.spread { return pages(for: shown).contains(page) }
                return shown == page
            }

            func show(
                _ page: Int, in pager: UIPageViewController, animated: Bool,
                direction: UIPageViewController.NavigationDirection
            ) {
                var list = pages(for: page).map { host($0) }
                // An odd count cannot lie on a two-sided spine (page 604 alone).
                if parent.spread, list.count == 1 { list.insert(blank(), at: 0) }
                pager.setViewControllers(list, direction: direction, animated: animated)
            }

            func step(_ delta: Int, in pager: UIPageViewController) {
                let base = parent.spread ? pages(for: shown).max() ?? shown : shown
                let next = parent.spread ? (delta > 0 ? base + 1 : base - 2) : shown + delta
                guard (1...604).contains(next) else { return }
                shown = next
                show(
                    next, in: pager, animated: !UIAccessibility.isReduceMotionEnabled,
                    direction: delta > 0 ? .reverse : .forward)
                parent.page = next
            }

            private func host(_ n: Int) -> PageHost {
                if let c = cache[n] { return c }
                if cache.count > 8 {
                    let keep = Set((shown - 3)...(shown + 3))
                    cache = cache.filter { keep.contains($0.key) }
                }
                let c = PageHost(number: n, content: parent.makePage(n))
                cache[n] = c
                return c
            }

            private func blank() -> PageHost {
                PageHost(number: 0, content: AnyView(Color.clear))
            }

            // In the controller's order the following page is the previous one of the book.
            func pageViewController(
                _ pager: UIPageViewController, viewControllerBefore vc: UIViewController
            ) -> UIViewController? {
                guard let n = (vc as? PageHost)?.number, n >= 1, n < 604 else { return nil }
                return host(n + 1)
            }

            func pageViewController(
                _ pager: UIPageViewController, viewControllerAfter vc: UIViewController
            ) -> UIViewController? {
                guard let n = (vc as? PageHost)?.number, n > 1 else { return nil }
                return host(n - 1)
            }

            func pageViewController(
                _ pager: UIPageViewController, willTransitionTo pending: [UIViewController]
            ) {
                turning = true
                parent.userTurned()
            }

            func pageViewController(
                _ pager: UIPageViewController, didFinishAnimating finished: Bool,
                previousViewControllers: [UIViewController], transitionCompleted completed: Bool
            ) {
                turning = false
                guard completed else { return }
                let visible = (pager.viewControllers ?? []).compactMap { ($0 as? PageHost)?.number }.filter {
                    $0 > 0
                }
                if let lowest = visible.min() {
                    shown = lowest
                    parent.page = lowest
                }
            }

            func pageViewController(
                _ pager: UIPageViewController, spineLocationFor orientation: UIInterfaceOrientation
            ) -> UIPageViewController.SpineLocation {
                parent.spread ? .mid : .max
            }
        }

        final class PageHost: UIHostingController<AnyView> {
            let number: Int

            init(number: Int, content: AnyView) {
                self.number = number
                super.init(rootView: content)
                view.backgroundColor = .clear
            }

            @MainActor @preconcurrency required dynamic init?(coder: NSCoder) { nil }
        }
    }
#endif
