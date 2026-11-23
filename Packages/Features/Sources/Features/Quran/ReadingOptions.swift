import ContentPacks
import Core
import DesignSystem
import Quran
import SwiftUI
import UserData

/// „Okuma Seçenekleri“ as in Diyanet's Quran app: start, end and how often
/// the whole range is read, instead of Play starting to read immediately.
///
/// The last choice stays saved; whoever picks „Sayfa başı → Sayfa sonu, 5×“ for
/// memorization will want that again for the next verse.
struct ReadingOptions: View {
    enum Start: String, CaseIterable { case verse = "ayet", page = "sayfa", surah = "sure", juz = "cuz" }
    enum End: String, CaseIterable { case verse = "ayet", page = "sayfa", surah = "sure", juz = "cuz" }

    @Environment(\.contentProvider) private var contentProvider
    @Environment(AppSettings.self) private var settings
    @Environment(RecitationPlayer.self) private var player
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var close

    let verse: Verse
    /// After „Oku“, e.g. to also close the verse sheet below it.
    var markRead: () -> Void = {}

    @State private var start =
        Start(rawValue: GroupDefaults.d.string(forKey: "okuma.baslangic") ?? "")
        ?? .verse
    @State private var end =
        End(rawValue: GroupDefaults.d.string(forKey: "okuma.bitis") ?? "") ?? .surah
    @State private var repetition = max(1, GroupDefaults.d.integer(forKey: "okuma.tekrar"))

    /// Calm like the other sheets: surface in `background` to the edges, no color block,
    /// only „Oku“ in the accent color.
    var body: some View {
        VStack(spacing: 16) {
            Label(localized("okuma.baslik"), systemImage: "play.circle.fill")
                .typography(.title2)
                .foregroundStyle(theme.colors.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 4) {
                HStack {
                    Text(app: "okuma.baslangic").frame(maxWidth: .infinity)
                    Text(app: "okuma.bitis").frame(maxWidth: .infinity)
                    Text(app: "okuma.tekrar").frame(maxWidth: .infinity)
                }
                .typography(.footnote).textCase(.uppercase)
                .foregroundStyle(theme.colors.label)
                HStack(spacing: 0) {
                    Picker(localized("okuma.baslangic"), selection: $start) {
                        ForEach(Start.allCases, id: \.self) { Text(verbatim: name($0)).tag($0) }
                    }
                    Picker(localized("okuma.bitis"), selection: $end) {
                        ForEach(End.allCases, id: \.self) { Text(verbatim: name($0)).tag($0) }
                    }
                    Picker(localized("okuma.tekrar"), selection: $repetition) {
                        ForEach(1...10, id: \.self) { Text(verbatim: "\($0)×").tag($0) }
                    }
                }
                #if os(iOS)
                    .pickerStyle(.wheel)
                #endif
                .frame(height: 170)
            }
            .padding(.vertical, 8)
            .background(theme.colors.surface, in: .rect(cornerRadius: 20))
            Button {
                load()
            } label: {
                Label(localized("okuma.oku"), systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButton())
        }
        .padding(20)
        .presentationDetents([.height(400)])
        .presentationDragIndicator(.visible)
        .presentationBackground(theme.colors.background)
    }

    private func name(_ b: Start) -> String {
        switch b {
        case .verse: localized("okuma.bas.ayet \(verse.verse)")
        case .page: localized("okuma.bas.sayfa")
        case .surah:
            contentProvider?.surah(verse.surah)?.name(language: translationLanguage())
                ?? localized("okuma.bas.sure")
        case .juz: localized("okuma.bas.cuz")
        }
    }

    private func name(_ b: End) -> String {
        switch b {
        case .verse: localized("okuma.son.ayet")
        case .page: localized("okuma.son.sayfa")
        case .surah: localized("okuma.son.sure")
        case .juz: localized("okuma.son.cuz")
        }
    }

    /// Consecutive numbers (1…6236) from start to end; the end is never before the verse.
    static func interval(
        index: Int, surah: ClosedRange<Int>, page: ClosedRange<Int>, juz: ClosedRange<Int>,
        start: Start, end: End
    ) -> ClosedRange<Int> {
        let lower =
            switch start {
            case .verse: index
            case .page: page.lowerBound
            case .surah: surah.lowerBound
            case .juz: juz.lowerBound
            }
        let upper =
            switch end {
            case .verse: index
            case .page: page.upperBound
            case .surah: surah.upperBound
            case .juz: juz.upperBound
            }
        return min(lower, index)...max(upper, index)
    }

    private func load() {
        defer {
            close()
            markRead()
        }
        let d = GroupDefaults.d
        d.set(start.rawValue, forKey: "okuma.baslangic")
        d.set(end.rawValue, forKey: "okuma.bitis")
        d.set(repetition, forKey: "okuma.tekrar")
        guard let contentProvider, let s = contentProvider.surah(verse.surah) else { return }
        let single = verse.index...verse.index
        let r = Self.interval(
            index: verse.index, surah: s.firstIndex...(s.firstIndex + s.verseCount - 1),
            page: contentProvider.page(verse.page).map { $0.firstIndex...$0.lastIndex } ?? single,
            juz: contentProvider.juz(verse.juz).map { $0.firstIndex...$0.lastIndex } ?? single,
            start: start, end: end)
        let verses = r.compactMap { n -> (surah: Int, verse: Int)? in
            if case .verse(let su, let a) = contentProvider.key(index: n) { return (su, a) }
            return nil
        }
        player.reciter = Reciter.find(settings.reciter)
        player.rangeRepeat = repetition
        player.play(queue: RecitationPlayer.queue(verses: verses, withBasmala: r.count > 1))
    }
}
