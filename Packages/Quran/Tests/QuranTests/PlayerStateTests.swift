import Foundation
import Testing

@testable import Quran

/// Pause, interruption and restart, without real audio: only the state right after each call counts,
/// before any file could have arrived.
@MainActor @Suite(.serialized) struct PlayerStateTests {
    private let items = RecitationPlayer.queue(verses: [(36, 1), (36, 2), (36, 3)], withBasmala: false)

    private let surahFiles = Reciter(
        id: "test-surah-files", name: "Test", style: "", folder: "", fullSurah: "https://example.invalid/")

    private func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "player-state-\(UUID())"))
    }

    private func player(_ d: UserDefaults) -> RecitationPlayer {
        let root = FileManager.default.temporaryDirectory.appending(path: "player-state \(UUID())")
        return RecitationPlayer(store: AudioStore(root: root), defaults: d)
    }

    /// A player as after an app restart: at verse 36:2, paused.
    private func restored(_ d: UserDefaults) -> RecitationPlayer {
        let first = player(d)
        first.play(queue: items)
        first.next()
        let second = player(d)
        second.restoreLastPlayback()
        return second
    }

    @Test func restartContinuesPausedAtTheSameVerse() throws {
        let o = restored(try defaults())
        #expect(o.isActive)
        #expect(o.current?.verse == 2)
        #expect(!o.isPlaying)
    }

    @Test func oldPlaybackIsNotRestored() throws {
        let d = try defaults()
        player(d).play(queue: items)
        let o = player(d)
        o.restoreLastPlayback(now: .now.addingTimeInterval(RecitationPlayer.savedPlaybackLifetime + 1))
        #expect(!o.isActive)
    }

    @Test func stopForgetsThePlayback() throws {
        let d = try defaults()
        let first = player(d)
        first.play(queue: items)
        first.stop()
        let second = player(d)
        second.restoreLastPlayback()
        #expect(!second.isActive)
    }

    @Test func callResumesWhatItInterrupted() throws {
        let o = player(try defaults())
        o.play(queue: items)
        #expect(o.isPlaying)
        o.interruption(started: true, resumption: false)
        #expect(!o.isPlaying)
        #expect(o.isActive)
        o.interruption(started: false, resumption: true)
        #expect(o.isPlaying)
        o.stop()
    }

    @Test func callWithoutSystemOfferStaysPausedButReady() throws {
        let o = player(try defaults())
        o.play(queue: items)
        o.interruption(started: true, resumption: false)
        o.interruption(started: false, resumption: false)
        #expect(!o.isPlaying)
        #expect(!o.offlineError)
        o.togglePause()
        #expect(o.isPlaying)
        o.stop()
    }

    @Test func pauseByTheUserSurvivesACall() throws {
        let o = restored(try defaults())
        o.interruption(started: true, resumption: false)
        o.interruption(started: false, resumption: true)
        #expect(!o.isPlaying)
    }

    @Test func settingTheSameValuesDoesNotReload() throws {
        let o = restored(try defaults())
        let before = o.downloadCount
        o.reciter = o.reciter
        o.repetition = o.repetition
        o.rangeRepeat = o.rangeRepeat
        o.delay = o.delay
        #expect(o.downloadCount == before)
    }

    @Test func changingSettingsKeepsThePause() throws {
        let o = restored(try defaults())
        o.repetition = 3
        o.delay = 2
        #expect(!o.isPlaying)
    }

    @Test func changingBetweenVerseAndSurahFilesKeepsThePause() throws {
        let o = restored(try defaults())
        o.reciter = surahFiles
        #expect(!o.isPlaying)
        #expect(o.current?.verse == 2)
        o.stop()
    }

    @Test func pauseDuringASurahFileLoadCounts() throws {
        let o = restored(try defaults())
        o.reciter = surahFiles
        o.togglePause()
        #expect(o.isPlaying)
        o.togglePause()
        #expect(!o.isPlaying)
        o.stop()
    }

    @Test func videoPausesTheQuran() throws {
        let o = player(try defaults())
        o.play(queue: items)
        NotificationCenter.default.post(name: .videoPlaybackWillStart, object: nil)
        // macOS has no audio session here; the observer exists on iOS only.
        #if os(iOS)
            #expect(!o.isPlaying)
        #endif
        o.stop()
    }
}
