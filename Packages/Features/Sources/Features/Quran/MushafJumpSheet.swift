import ContentPacks
import Core
import DesignSystem
import SwiftUI

/// Jump sheet behind the Mushaf title: choose surah (with verse), juz or page, „Git“ pages there.
struct MushafJumpSheet: View {
    enum JumpSection: Hashable { case surah, juz, page }

    @Environment(\.contentProvider) private var contentProvider
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var close
    /// Current page in the numbering of `edition`.
    let current: Int
    let edition: MushafEdition
    let git: (Int) -> Void
    /// From the reader list (): instead of a page the position itself - verse, juz or the first
    /// verse of the chosen page. If set, „Git“ calls only this.
    var jumpTo: ((ContentKey) -> Void)? = nil
    @State private var section: JumpSection = .surah
    @State private var surah = 1
    @State private var verse = 1
    @State private var juz = 1
    @State private var page = 1

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker(localized("kuran.mushaf.git.baslik"), selection: $section) {
                    Text(app: "kuran.mushaf.git.sure").tag(JumpSection.surah)
                    Text(app: "kuran.cuz").tag(JumpSection.juz)
                    Text(app: "kuran.mushaf.git.sayfa").tag(JumpSection.page)
                }
                .pickerStyle(.segmented)
                Group {
                    switch section {
                    case .surah:
                        // On the left wide the surah, on the right narrow the verse.
                        HStack(spacing: 0) {
                            wheel(localized("kuran.mushaf.git.sure"), selection: $surah, interval: 1...114) {
                                surahLabel($0)
                            }
                            wheel(
                                localized("kuran.mushaf.git.ayet"), selection: $verse,
                                interval: 1...verseCount
                            ) {
                                Text(verbatim: "\($0)").monospacedDigit()
                            }
                            .frame(width: 80)
                        }
                    case .juz:
                        wheel(localized("kuran.cuz"), selection: $juz, interval: 1...30) {
                            Text(app: "kuran.cuz.no \($0)")
                        }
                    case .page:
                        wheel(localized("kuran.mushaf.git.sayfa"), selection: $page, interval: 1...604) {
                            Text(app: "kuran.sayfa_no \($0)")
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                Button {
                    if let jumpTo, let s = target {
                        jumpTo(s)
                        close()
                    } else if let n = goal {
                        git(n)
                        close()
                    }
                } label: {
                    Text(app: "kuran.mushaf.git").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButton())
                .disabled(jumpTo == nil ? goal == nil : target == nil)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .background(theme.colors.background)
            .navigationTitle(localized("kuran.mushaf.git.baslik"))
            .smallTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("genel.vazgec")) { close() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(theme.colors.background)
        .onAppear { prefill() }
        // New surah: verse back to 1.
        .onChange(of: surah) { verse = 1 }
    }

    private var verseCount: Int { max(1, contentProvider?.surah(surah)?.verseCount ?? 1) }

    /// Choice of the current page: surah and verse of its first verse, its juz, the page itself.
    private func prefill() {
        page = current
        guard let contentProvider, let b = edition.interval(current, contentProvider) else { return }
        juz = (1...30).last { (contentProvider.juz($0)?.firstIndex ?? .max) <= b.first } ?? 1
        if case .verse(let s, let a) = contentProvider.key(index: b.first) {
            surah = s
            // After the onChange(of: sure), which would otherwise reset the verse to 1.
            Task { @MainActor in verse = a }
        }
    }

    /// The position for the current choice (reader list).
    private var target: ContentKey? {
        guard let contentProvider else { return nil }
        switch section {
        case .surah: return .verse(surah: surah, verse: verse)
        case .juz: return .juz(juz)
        case .page:
            return edition.interval(page, contentProvider).flatMap { contentProvider.key(index: $0.first) }
        }
    }

    /// The Mushaf page for the current choice.
    private var goal: Int? {
        guard let contentProvider else { return nil }
        switch section {
        case .surah:
            return edition.page(surah: surah, verse: verse, contentProvider)
        case .juz:
            guard let b = contentProvider.juz(juz) else { return nil }
            return edition.page(index: b.firstIndex, contentProvider)
        case .page:
            return page
        }
    }

    private func surahLabel(_ n: Int) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: "\(n)").monospacedDigit().foregroundStyle(theme.colors.text2)
            Text(verbatim: contentProvider?.surah(n)?.name(language: translationLanguage()) ?? "")
            Text(verbatim: contentProvider?.surah(n)?.nameArabic ?? "").font(
                .custom(Typography.arabicFontName, size: 19))
        }
        .lineLimit(1)
    }

    private func wheel<E: View>(
        _ name: String, selection: Binding<Int>, interval: ClosedRange<Int>,
        @ViewBuilder label: @escaping (Int) -> E
    ) -> some View {
        Picker(name, selection: selection) {
            ForEach(Array(interval), id: \.self) { label($0).tag($0) }
        }
        #if os(iOS)
            .pickerStyle(.wheel)
        #endif
    }
}
