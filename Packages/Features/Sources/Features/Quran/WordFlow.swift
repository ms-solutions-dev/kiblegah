import ContentPacks
import DesignSystem
import Quran
import SwiftUI

extension EnvironmentValues {
    /// Word-by-word meanings (Quran.com, cached for at most 7 days).
    @Entry public var wordByWord: WordTranslations? = nil
}

/// Words with the meaning below them, wrapped right to left.
struct WordFlow: View {
    @Environment(\.theme) private var theme
    let words: [Word]
    let meanings: [WordMeaning]
    let size: Double
    /// Tajweed spans across the whole verse (words joined with a space).
    var tajweed: [TajweedSpan] = []
    let translationSize: Double
    /// The word currently being recited (1-based), highlighted.
    var accent: Int? = nil
    /// „Bu kelimeden dinle“; nil if the reciter has no word timings.
    var listenFromWord: ((Int) -> Void)? = nil
    /// End-of-verse mark after the last word (without Kelime meali, as in running text).
    var end: String? = nil
    var interval: CGFloat = 10

    /// The verse's tajweed spans shifted to one word: offset = length of all words before it
    /// plus one space each (this is how `Verse.text` builds the verse).
    static func colored(
        _ text: String, word i: Int, words: [Word], tajweed: [TajweedSpan], dark: Bool
    ) -> AttributedString {
        guard !tajweed.isEmpty else { return AttributedString(text) }
        let start = words.prefix(i).reduce(0) { $0 + $1.text.unicodeScalars.count + 1 }
        let end = start + text.unicodeScalars.count
        let local = tajweed.compactMap { t -> TajweedSpan? in
            let a = max(t.interval.lowerBound, start)
            let b = min(t.interval.upperBound, end)
            return a < b ? TajweedSpan(rule: t.rule, interval: (a - start)..<(b - start)) : nil
        }
        return tajweedText(text, spans: local, dark: dark)
    }

    var body: some View {
        FlowLayout(interval: interval) {
            ForEach(Array(words.enumerated()), id: \.offset) { i, k in
                VStack(spacing: 2) {
                    Text(
                        Self.colored(
                            k.text, word: i, words: words, tajweed: tajweed, dark: theme.colors.dark)
                    )
                    .typography(.arabic(size: size))
                    if !meanings.isEmpty {
                        let meaning = i < meanings.count ? meanings[i] : WordMeaning(text: "")
                        // English fallback where Quran.com has no Turkish: italic and quieter.
                        Text(verbatim: meaning.text)
                            .font(.custom("Plus Jakarta Sans", size: translationSize, relativeTo: .footnote))
                            .italic(meaning.fallback)
                            .foregroundStyle(theme.colors.text2.opacity(meaning.fallback ? 0.7 : 1))
                            .multilineTextAlignment(.center)
                            // Wrap long meanings instead of „the Sustainer of all th…“.
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 140)
                    }
                }
                .padding(.horizontal, meanings.isEmpty ? 0 : 4)
                .background(
                    accent == i + 1 ? theme.colors.accent.opacity(0.2) : .clear, in: .rect(cornerRadius: 8)
                )
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(localized("kuran.kelime.dinle"))
                // A long press speaks the word (Quran.com word recording), a tap remains the
                // verse menu of the row. The preview plays on appearing.
                .contentShape(.rect)
                .contextMenu {
                    Button(localized("kuran.kelime.dinle"), systemImage: "speaker.wave.2") {
                        WordAudio.shared.play(k.key)
                    }
                    if let listenFromWord {
                        Button(localized("kuran.oynatici.kelimeden"), systemImage: "play.fill") {
                            listenFromWord(i + 1)
                        }
                    }
                } preview: {
                    VStack(spacing: 6) {
                        Text(verbatim: k.text).typography(.arabic(size: 44))
                        if i < meanings.count, !meanings[i].text.isEmpty {
                            Text(verbatim: meanings[i].text).typography(.secondary).foregroundStyle(
                                theme.colors.text2)
                        }
                    }
                    .padding(24)
                    .onAppear { WordAudio.shared.play(k.key) }
                }
            }
            if let end {
                // Standing alone, the character has no strong letter; without an RLM the
                // script reads it left-to-right and flips the ornamental brackets.
                Text(verbatim: "\u{200F}" + end).typography(.arabic(size: size)).accessibilityHidden(true)
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// Simple flow layout: fill lines, then wrap; direction follows `layoutDirection`.
struct FlowLayout: Layout {
    var interval: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let rows = breakLines(subviews, width: width)
        let height =
            rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * interval
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in breakLines(subviews, width: bounds.width) {
            var x = bounds.minX
            for i in row.items {
                let b = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(b))
                x += b.width + interval
            }
            y += row.height + interval
        }
    }

    private struct Line {
        var items: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func breakLines(_ subviews: Subviews, width: CGFloat) -> [Line] {
        var rows: [Line] = [Line()]
        for (i, v) in subviews.enumerated() {
            let b = v.sizeThatFits(.unspecified)
            if rows[rows.count - 1].width + b.width > width
                && !rows[rows.count - 1].items.isEmpty
            {
                rows.append(Line())
            }
            rows[rows.count - 1].items.append(i)
            rows[rows.count - 1].width += b.width + interval
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, b.height)
        }
        return rows
    }
}
