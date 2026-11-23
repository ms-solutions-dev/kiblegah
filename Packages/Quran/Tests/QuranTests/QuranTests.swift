import Core
import Foundation
import Testing

@testable import Quran

@Suite struct KariTests {
    @Test func addressAndFile() {
        let k = Reciter.find("alafasy")
        #expect(
            k.remote(surah: 2, verse: 255).absoluteString
                == "https://verses.quran.com/Alafasy/mp3/002255.mp3")
        #expect(Reciter.find("yok").id == Reciter.standard.id)
        #expect(Reciter.all.allSatisfy { !$0.storeEligible })
    }

    @Test func queueWithBasmala() {
        let b = RecitationPlayer.queue(surah: 2, verseCount: 5, verse: 1)
        #expect(b.first?.basmala == true && b.count == 6)
        #expect(RecitationPlayer.queue(surah: 1, verseCount: 7, verse: 1).first?.basmala == false)
        #expect(RecitationPlayer.queue(surah: 9, verseCount: 3, verse: 1).count == 3)
        #expect(RecitationPlayer.queue(surah: 2, verseCount: 5, verse: 3).map(\.verse) == [3, 4, 5])
    }

    /// Up to the end of the juz across surahs: basmala before every new surah, not before Tevbe.
    @Test func queueAcrossSurahs() {
        let k = RecitationPlayer.queue(verses: [(2, 285), (2, 286), (3, 1), (8, 75), (9, 1)])
        #expect(k.map(\.basmala) == [false, false, true, false, false, false])
        #expect(k.filter { !$0.basmala }.map(\.surah) == [2, 2, 3, 8, 9])
    }

    /// Plan of the queue: repetitions of the same verse, then on, basmala only once,
    /// at the end the range from the start again, finally the end.
    @Test func nextStep() {
        typealias A = RecitationPlayer.Step
        let k = RecitationPlayer.queue(surah: 2, verseCount: 2, verse: 1)  // Basmala, 2:1, 2:2
        let start = A(location: 0, remainingRepeats: 1, remainingRange: 1)
        #expect(
            RecitationPlayer.nextStep(start, queue: k, repetition: 1)
                == A(location: 1, remainingRepeats: 1, remainingRange: 1))
        #expect(
            RecitationPlayer.nextStep(start, queue: k, repetition: 3)
                == A(location: 1, remainingRepeats: 3, remainingRange: 1))
        let v1 = A(location: 1, remainingRepeats: 3, remainingRange: 1)
        #expect(
            RecitationPlayer.nextStep(v1, queue: k, repetition: 3)
                == A(location: 1, remainingRepeats: 2, remainingRange: 1))
        let lastItem = A(location: 2, remainingRepeats: 1, remainingRange: 1)
        #expect(RecitationPlayer.nextStep(lastItem, queue: k, repetition: 3) == nil)
        let range = A(location: 2, remainingRepeats: 1, remainingRange: 2)
        #expect(
            RecitationPlayer.nextStep(range, queue: k, repetition: 2)
                == A(location: 0, remainingRepeats: 1, remainingRange: 1)
        )
        #expect(RecitationPlayer.nextStep(start, queue: [], repetition: 1) == nil)
        var a: RecitationPlayer.Step? = A(location: 0, remainingRepeats: 1, remainingRange: 2)
        var steps: [Int] = []
        while let x = a {
            steps.append(x.location)
            a = RecitationPlayer.nextStep(x, queue: k, repetition: 2)
        }
        #expect(steps == [0, 1, 1, 2, 2, 0, 1, 1, 2, 2])
    }

    @Test func wordTimings() throws {
        let json =
            #"{"audio_files":[{"verse_key":"112:1","segments":[[0,1,30,390],[1,2,400,790],[2,3,800,1640],[3,4,1650,2300]]},{"verse_key":"112:2","segments":[[0,1,40,980],[9]]}],"pagination":{"next_page":null}}"#
        let c = try JSONDecoder().decode(WordTimings.Response.self, from: Data(json.utf8))
        let z = WordTimings.parse(c)
        #expect(z[1]?.map(\.index) == [1, 2, 3, 4])
        #expect(z[2]?.count == 1)  // incomplete segment is dropped
        #expect(WordTimings.word(z[1]!, ms: 10) == nil)
        #expect(WordTimings.word(z[1]!, ms: 820) == 3)
        #expect(
            Reciter.all.allSatisfy { $0.qcID != nil || $0.fullSurah != nil }
                && Reciter.find("alafasy").qcID == 7)
    }
}

@MainActor @Suite struct AudioStoreTests {
    @Test func statusAndDelete() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ses \(UUID())")
        let d = AudioStore(root: root)
        let k = Reciter.standard
        #expect(d.status(k, surah: 1, verseCount: 2) == .yok)
        try FileManager.default.createDirectory(
            at: root.appending(path: k.id), withIntermediateDirectories: true)
        for a in 1...2 { try Data([1, 2, 3]).write(to: d.local(k, surah: 1, verse: a)) }
        #expect(d.status(k, surah: 1, verseCount: 2) == .ready)
        #expect(d.downloaded().first?.surah == 1)
        d.delete(k, surah: 1, verseCount: 2)
        #expect(d.status(k, surah: 1, verseCount: 2) == .yok)
    }
}

/// Real download of the Fâtiha (only with `KIBLEGAH_AG=1`, so that the tests run without network).
@MainActor @Suite struct AudioDownloadTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["KIBLEGAH_AG"] == "1"))
    func fatihaOfflineReady() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ses ag \(UUID())")
        let d = AudioStore(root: root)
        d.download(.standard, surah: 1, verseCount: 7)
        for _ in 0..<300 {
            if d.status(.standard, surah: 1, verseCount: 7) == .ready { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(d.status(.standard, surah: 1, verseCount: 7) == .ready)
        #expect((d.downloaded().first?.bytes ?? 0) > 100_000)
    }
}

@Suite struct WordTranslationsTests {
    let sample = Data(
        """
        {"verses":[{"verse_number":2,"words":[
          {"position":2,"char_type_name":"word","translation":{"text":"Allah'a","language_name":"turkish"}},
          {"position":1,"char_type_name":"word","translation":{"text":"hamdolsun","language_name":"turkish"}},
          {"position":3,"char_type_name":"end","translation":{"text":"(2)","language_name":"english"}}]}]}
        """.utf8)

    @Test func decodeIndexAndEndMarker() {
        #expect(WordTranslations.parse(sample)?[2]?.map(\.text) == ["hamdolsun", "Allah'a"])
        #expect(WordTranslations.sourceLanguage("de") == "en")
    }

    @Test func cacheDeletedAfterOneWeek() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "km \(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let old = WordTranslations.CacheEntry(
            date: Date(timeIntervalSinceNow: -8 * 86400), language: "tr",
            verses: [1: [WordMeaning(text: "x")]]
        )
        try JSONEncoder().encode(old).write(to: root.appending(path: "tr-1.json"))
        let k = WordTranslations(folder: root)
        await k.clear()
        #expect(
            !FileManager.default.fileExists(
                atPath: root.appending(path: "tr-1.json").path(percentEncoded: false)))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["KIBLEGAH_AG"] == "1"))
    func fatihaReal() async throws {
        let k = WordTranslations(
            folder: FileManager.default.temporaryDirectory.appending(path: "km ag \(UUID())"))
        let s = try #require(await k.surah(1, language: "tr"))
        #expect(s[2]?.count == 4)
    }

    /// Mixed language in one verse: Turkish stays, only the English word is the fallback.
    @Test func wordMeaningMixedVerseFallbackWord() {
        let veri = Data(
            """
            {"verses":[{"verse_number":1,"words":[
              {"position":1,"char_type_name":"word","translation":{"text":"hamd","language_name":"turkish"}}]},
             {"verse_number":2,"words":[
              {"position":1,"char_type_name":"word","translation":{"text":"Rab","language_name":"turkish"}},
              {"position":2,"char_type_name":"word","translation":{"text":"the worlds","language_name":"english"}}]}]}
            """.utf8)
        let tr = WordTranslations.parse(veri, language: "tr")
        #expect(tr?[1] == [WordMeaning(text: "hamd")])
        #expect(tr?[2] == [WordMeaning(text: "Rab"), WordMeaning(text: "the worlds", fallback: true)])
        #expect(WordTranslations.verseCount(veri) == 2)
    }

    @Test func wordAudioAddress() {
        #expect(
            WordAudio.address(surah: 2, verse: 255, word: 1)?.absoluteString
                == "https://audio.qurancdn.com/wbw/002_255_001.mp3")
    }

    @Test func reciterAddresses() {
        #expect(
            Reciter.find("shatri").remote(surah: 2, verse: 255).absoluteString
                == "https://verses.quran.com/Shatri/mp3/002255.mp3")
        #expect(
            Reciter.find("husary").remote(surah: 1, verse: 1).absoluteString
                == "https://mirrors.quranicaudio.com/everyayah/Husary_64kbps/001001.mp3")
        #expect(Set(Reciter.all.map(\.id)).count == Reciter.all.count)
    }

    @Test func fullSurahFile() {
        let k = Reciter.hasFullSurah(
            id: "ornek", name: "Örnek", style: "Murattal", address: "https://ornek.invalid/r2/")
        #expect(k.remote(surah: 2, verse: 255).absoluteString == "https://ornek.invalid/r2/002.mp3")
        #expect(Reciter.find("alafasy").surahFile(1) == nil)
    }

    /// Without the switch (Store, Preview) there is only the catalog; a stored extra reciter
    /// falls back to the default instead of loading from its source.
    @Test func extraRecitersOnlyWithSwitch() {
        #expect(!FeatureFlags.enabled.contains(.extraReciters))
        #expect(Reciter.all == Reciter.catalog)
        #expect(Reciter.catalog.allSatisfy { $0.fullSurah == nil })
        #expect(Reciter.find("okasha") == Reciter.standard)
    }
}

/// Real playback via the AVQueuePlayer with local verse files (Alafasy, surah 36:1–3 and
/// 2:1–3) from `KIBLEGAH_SES_KLASOR`. Proves that verses connect without reloading,
/// repetition and repeat-aloud pause run via the queue. Runs only on request,
/// because it needs real time.
@MainActor @Suite(.serialized) struct PlayerPlaybackTests {
    nonisolated static let folder = ProcessInfo.processInfo.environment["KIBLEGAH_SES_KLASOR"]

    /// Logs every change of `current` with wall time since start.
    private func run(
        _ o: RecitationPlayer, queue: [RecitationPlayer.QueueItem], maximum: Double
    ) async -> (switchOver: [(verse: Int, t: Double)], duration: Double) {
        let start = Date()
        o.play(queue: queue)
        var switchOver: [(Int, Double)] = []
        var lastOne: RecitationPlayer.QueueItem?
        while o.isActive, Date().timeIntervalSince(start) < maximum {
            if let s = o.current, s != lastOne {
                lastOne = s
                switchOver.append((s.verse, Date().timeIntervalSince(start)))
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return (switchOver, Date().timeIntervalSince(start))
    }

    private func store() throws -> AudioStore {
        let root = FileManager.default.temporaryDirectory.appending(path: "ses calma \(UUID())")
        let target = root.appending(path: Reciter.standard.id)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        for d in ["036001", "036002", "036003", "002001", "002002", "002003"] {
            try FileManager.default.copyItem(
                at: URL(fileURLWithPath: Self.folder!).appending(path: "\(d).mp3"),
                to: target.appending(path: "\(d).mp3"))
        }
        return AudioStore(root: root)
    }

    /// 36:1–3 (4.56 + 4.78 + 5.81 s): a single load, changes in step with the file lengths.
    @Test(.enabled(if: folder != nil)) func gapless() async throws {
        let o = RecitationPlayer(store: try store())
        let (w, duration) = await run(
            o, queue: RecitationPlayer.queue(verses: [(36, 1), (36, 2), (36, 3)], withBasmala: false),
            maximum: 30)
        print("Wechsel:", w.map { "\($0.verse)@\(String(format: "%.3f", $0.t))" }, "Dauer", duration)
        #expect(w.map(\.verse) == [1, 2, 3])
        #expect(o.downloadCount == 1)
        #expect(abs((w[1].t - w[0].t) - 4.563) < 0.3)
        #expect(abs((w[2].t - w[1].t) - 4.775) < 0.3)
        #expect(abs(duration - 15.15) < 0.6)
        #expect(!o.isActive)
    }

    /// Twice per verse: the repetition comes as another item, without reloading.
    @Test(.enabled(if: folder != nil)) func repeatQueue() async throws {
        let o = RecitationPlayer(store: try store())
        o.repetition = 2
        let (w, duration) = await run(
            o, queue: RecitationPlayer.queue(verses: [(36, 1), (36, 2)], withBasmala: false), maximum: 30)
        print("Wechsel:", w.map { "\($0.verse)@\(String(format: "%.3f", $0.t))" }, "Dauer", duration)
        #expect(w.map(\.verse) == [1, 2])
        #expect(o.downloadCount == 1)
        #expect(abs((w[1].t - w[0].t) - 2 * 4.563) < 0.4)
        #expect(abs(duration - 2 * (4.563 + 4.775)) < 0.8)
    }

    /// Repeat-aloud pause: the verse just heard stays highlighted during the silence, then it continues.
    @Test(.enabled(if: folder != nil)) func pauseMarkerStays() async throws {
        let o = RecitationPlayer(store: try store())
        o.delay = 1
        let (w, duration) = await run(
            o, queue: RecitationPlayer.queue(verses: [(36, 1), (36, 2)], withBasmala: false), maximum: 30)
        print("Wechsel:", w.map { "\($0.verse)@\(String(format: "%.3f", $0.t))" }, "Dauer", duration)
        #expect(w.map(\.verse) == [1, 2])
        #expect(o.downloadCount == 1)
        #expect(abs((w[1].t - w[0].t) - (4.563 + 1)) < 0.4)
        #expect(abs(duration - (4.563 + 1 + 4.775 + 1)) < 0.8)
    }

    /// Range twice (aralikTekrar) over basmala + 2:1: jump back without reloading.
    @Test(.enabled(if: folder != nil)) func rangeRepeatJumpsBack() async throws {
        let o = RecitationPlayer(store: try store())
        o.rangeRepeat = 2
        let (w, duration) = await run(o, queue: RecitationPlayer.queue(verses: [(2, 1)]), maximum: 40)
        print(
            "Wechsel:", w.map { "\($0.verse)@\(String(format: "%.3f", $0.t)) b=\($0.verse)" }, "Dauer",
            duration)
        #expect(w.count == 4)
        #expect(o.downloadCount == 1)
        #expect(abs(duration - 2 * (6.031 + 7.605)) < 0.8)
    }

    @Test(.enabled(if: folder != nil)) func duhaWithBasmalaFromNetwork() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ses leer \(UUID())")
        let o = RecitationPlayer(
            store: AudioStore(root: root), cache: AudioCache(root: root.appending(path: "vorrat")))
        let (w, duration) = await run(
            o, queue: RecitationPlayer.queue(surah: 93, verseCount: 11, verse: 1), maximum: 90)
        print(
            "Wechsel:", w.map { "\($0.verse)@\(String(format: "%.2f", $0.t))" }, "Dauer", duration, "lade",
            o.downloadCount, "aktif", o.isActive, "caliyor", o.isPlaying)
        #if DEBUG
            for z in o.track { print("  iz:", z) }
        #endif
        #expect(w.map(\.verse) == [1] + Array(1...11))
        #expect(o.downloadCount == 1)
        #expect(!o.isActive)
    }
}
