import Testing

@testable import ContentPacks

/// Footnote markers of the translation (Saheeh International via QuranEnc) never show up as raw text.
@Suite struct TranslationTextTests {
    @Test func markersBecomeFootnotes() {
        let t = TranslationText(
            pack: "meal-en-saheeh", rawText: "By the wise[1261] Qur’ān,",
            footnote: "[1261]- See footnote to 10:1.")
        #expect(t.text == "By the wise Qur’ān,")
        #expect(t.markedText == "By the wise¹ Qur’ān,")
        #expect(t.footnotes == [.init(number: 1, text: "See footnote to 10:1.")])
        #expect(t.rawText == "By the wise[1261] Qur’ān,")
    }

    @Test func severalNotesInTextOrder() {
        let t = TranslationText(
            pack: "meal-en-saheeh",
            rawText:
                "Who believe in the unseen, establish prayer,[9] and spend out of what We[10] have provided for them,",
            footnote: "[9]- At its proper times.\n[10]- It is to be noted that …")
        #expect(
            t.text
                == "Who believe in the unseen, establish prayer, and spend out of what We have provided for them,"
        )
        #expect(t.markedText.contains("prayer,¹ and") && t.markedText.contains("We² have"))
        #expect(t.footnotes.map(\.text) == ["At its proper times.", "It is to be noted that …"])
    }

    @Test func withoutNotesNothingChanges() {
        let raw = "Indeed you, [O Muḥammad], are from among the messengers,"
        let t = TranslationText(pack: "meal-en-saheeh", rawText: raw, footnote: nil)
        #expect(t.text == raw && t.markedText == raw && t.footnotes.isEmpty)
        // A bracketed number without a matching note stays.
        let u = TranslationText(pack: "x", rawText: "a[12] b", footnote: "[3]- other")
        #expect(u.text == "a[12] b")
    }
}
