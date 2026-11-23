import Foundation
import Testing

@testable import Quran

/// Move of the recitations into the App Group container.
@Suite struct AudioMigrationTests {
    private func temporary() -> URL {
        let u = URL.temporaryDirectory.appending(path: "ses-tasima-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    private func save(_ u: URL, _ text: String) throws {
        try FileManager.default.createDirectory(
            at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: u)
    }

    @Test func newFolderMissingIsRenamed() throws {
        let k = temporary()
        let old = k.appending(path: "eski/Sesler")
        let yeni = k.appending(path: "grup/Library/Application Support/Sesler")
        try save(old.appending(path: "alafasy/001001.mp3"), "a")
        AudioStore.migrate(old, yeni)
        #expect(
            FileManager.default.fileExists(
                atPath: yeni.appending(path: "alafasy/001001.mp3").path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: old.path(percentEncoded: false)))
    }

    @Test func bothPresentMissingMovesExistingStays() throws {
        let k = temporary()
        let old = k.appending(path: "eski/Sesler")
        let yeni = k.appending(path: "grup/Sesler")
        try save(old.appending(path: "alafasy/001001.mp3"), "alt")
        try save(old.appending(path: "alafasy/001002.mp3"), "b")
        try save(yeni.appending(path: "alafasy/001001.mp3"), "neu")
        AudioStore.migrate(old, yeni)
        #expect(try String(contentsOf: yeni.appending(path: "alafasy/001001.mp3"), encoding: .utf8) == "neu")
        #expect(try String(contentsOf: yeni.appending(path: "alafasy/001002.mp3"), encoding: .utf8) == "b")
        #expect(!FileManager.default.fileExists(atPath: old.path(percentEncoded: false)))
    }

    @Test func nothingWithoutOldFolder() {
        let k = temporary()
        AudioStore.migrate(k.appending(path: "yok"), k.appending(path: "yeni"))
        #expect(
            !FileManager.default.fileExists(atPath: k.appending(path: "yeni").path(percentEncoded: false)))
    }

    /// If a move fails, the file stays in the old folder – nothing is lost.
    @Test func failedMoveDeletesNothing() throws {
        let k = temporary()
        let old = k.appending(path: "eski/Sesler")
        let yeni = k.appending(path: "grup/Sesler")
        try save(old.appending(path: "alafasy/001003.mp3"), "c")
        // In the new folder `alafasy` is a file instead of a folder: moving is impossible.
        try save(yeni.appending(path: "alafasy"), "x")
        AudioStore.migrate(old, yeni)
        #expect(try String(contentsOf: old.appending(path: "alafasy/001003.mp3"), encoding: .utf8) == "c")
    }
}
