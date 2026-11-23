import Testing

@testable import Features

@MainActor struct ReadingOptionsTests {
    /// Verse 2:255 has the sequential number 262; page 42 = 260…264, Bakara 8…293, Juz 3 = 260…385.
    let index = 262, surah = 8...293, page = 260...264, juz = 260...385

    @Test func pageStartToPageEnd() {
        #expect(
            ReadingOptions.interval(
                index: index, surah: surah, page: page, juz: juz, start: .page, end: .page) == 260...264
        )
    }

    @Test func onlyThisVerse() {
        #expect(
            ReadingOptions.interval(
                index: index, surah: surah, page: page, juz: juz, start: .verse, end: .verse) == 262...262)
    }

    @Test func juzStartToSurahEnd() {
        #expect(
            ReadingOptions.interval(
                index: index, surah: surah, page: page, juz: juz, start: .juz, end: .surah) == 260...293)
    }
}
