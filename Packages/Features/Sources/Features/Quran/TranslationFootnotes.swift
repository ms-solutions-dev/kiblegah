import ContentPacks
import DesignSystem
import SwiftUI

/// The footnotes of a translation under its text, numbered like the superscript markers in
/// `TranslationText.markedText`. Nothing when the translation has no notes for the verse.
struct TranslationFootnotes: View {
    @Environment(\.theme) private var theme
    let notes: [TranslationText.Footnote]

    var body: some View {
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(notes, id: \.number) { n in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: "\(n.number)").monospacedDigit()
                        Text(verbatim: n.text).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .typography(.footnote)
            .foregroundStyle(theme.colors.text2)
        }
    }
}
