import Foundation
import Testing

@testable import UserData

/// Highlights and reading position of the books (): verse mapping is kept on change, reading
/// position merges duplicates (two devices).
@MainActor @Suite struct BookBookmarksTests {
    @Test func verseAndModified() throws {
        let d = UserStore(container: try UserDataSchema.container(iCloud: false, inMemory: true))
        d.saveBookBookmark(
            identifier: "x", book: "Ornek_Kitap_02", kind: "sari", location: "{}",
            text: "Elhamdülillâh",
            note: "",
            fraction: 0.1, section: "", verse: (1, 2, 4), date: .now)
        #expect(d.verseBookmarks(surah: 1, verse: 3).map(\.kimlik) == ["x"])
        #expect(d.verseBookmarks(surah: 1, verse: 5).isEmpty)
        // Change color and note, without a verse: the mapping stays
        d.saveBookBookmark(
            identifier: "x", book: "Ornek_Kitap_02", kind: "yesil", location: "{}",
            text: "Elhamdülillâh",
            note: "Hamd ve şükür", fraction: 0.1, section: "", verse: nil, date: .now)
        let i = try #require(d.bookBookmarks("Ornek_Kitap_02").first)
        #expect(i.tur == "yesil" && i.not == "Hamd ve şükür" && i.ayetIlk == 2)
        #expect(d.bookBookmarks().count == 1)
        d.deleteBookBookmark("x")
        #expect(d.bookBookmarks().isEmpty)
    }

    @Test func location() throws {
        let d = UserStore(container: try UserDataSchema.container(iCloud: false, inMemory: true))
        #expect(d.lastBookPosition() == nil)
        d.saveBookPosition("A", location: "a1", fraction: 0.1)
        d.saveBookPosition("B", location: "b1", fraction: 0.2)
        d.saveBookPosition("A", location: "a2", fraction: 0.3)
        #expect(d.bookPosition("A")?.konum == "a2")
        #expect(d.lastBookPosition()?.kitap == "A")
    }
}
