import AVFoundation
import Core
import Foundation
import Observation
import os

#if os(iOS)
    import MediaPlayer
#endif

@MainActor @Observable public final class RecitationPlayer {
    public struct QueueItem: Equatable, Sendable {
        public let surah: Int
        public let verse: Int
        /// The prepended basmala (shows verse 1, plays 1:1).
        public let basmala: Bool
    }

    /// One step of the plan: which entry of the Kuyruk plays and how many passes of this
    /// verse or of the whole range are still pending, counting the current one.
    public struct Step: Equatable, Sendable {
        public var location: Int
        public var remainingRepeats: Int
        public var remainingRange: Int

        public init(location: Int, remainingRepeats: Int, remainingRange: Int) {
            self.location = location
            self.remainingRepeats = remainingRepeats
            self.remainingRange = remainingRange
        }
    }

    /// A piece scheduled on the node: step, start point in the verse (ms) and position in the
    /// node's timeline (frames since the last start).
    private struct Segment {
        let step: Step
        /// Where this pass began (repetitions start there again).
        let start: Int
        /// Where the piece actually starts (after a resume in the middle of a verse later than `start`).
        let realStart: Int
        let startFrame: AVAudioFramePosition
        let length: AVAudioFramePosition
        let ratio: Double
    }

    public private(set) var queue: [QueueItem] = []
    public private(set) var location = 0
    public private(set) var isPlaying = false
    public private(set) var offlineError = false
    /// `fullSurah` reciter: the verse timings for this surah have not been computed yet.
    public private(set) var zamanYok = false
    public var reciter: Reciter = .standard {
        didSet { reschedule() }
    }
    /// How often each verse is played (1 = no repetition).
    public var repetition = 1 {
        didSet { reschedule() }
    }
    /// How often the whole range is played.
    public var rangeRepeat = 1 {
        didSet { reschedule() }
    }
    /// Seconds of silence after each pass of a verse (for repeating aloud).
    public var delay: Double = 0 {
        didSet { reschedule() }
    }
    /// The word being spoken right now (position in the verse), if word timings are available.
    public private(set) var currentWord: Int?
    public var speed: Float = 1 {
        didSet {
            tempo.rate = speed
            if isPlaying, reciter.fullSurah != nil { player.rate = speed }
        }
    }
    /// How often it was loaded from the start (test runs: gapless means exactly once per start).
    public private(set) var downloadCount = 0
    /// The last transitions in memory (filled only in DEBUG), for test runs – mirror of the os_log.
    public private(set) var track: [String] = []

    public var current: QueueItem? { queue.indices.contains(location) ? queue[location] : nil }
    public var isActive: Bool { !queue.isEmpty }

    private let motor = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    /// Tempo without pitch change (`speed`).
    private let tempo = AVAudioUnitTimePitch()
    private var connectedFormat: AVAudioFormat?
    /// The scheduled pieces, the current one first.
    private var scheduled: [Segment] = []
    private var totalFrames: AVAudioFramePosition = 0
    /// Last measured position in the timeline (the node only reports it while playing).
    private var sonFrame: AVAudioFramePosition = 0
    /// Every restart counts up; old callbacks and loaders use this to recognize that they run into nothing.
    private var generation = 0
    private var filler: (generation: Int, task: Task<Void, Never>)?
    /// Resume in the middle of a verse (ms), e.g. after a changed setting or an interruption.
    private var continueMs: Int?
    private var positionTimer: Timer?
    private let cache: AudioCache

    private let player = AVQueuePlayer()
    /// The surah-file item whose end triggers `finished()`.
    private var playingItem: ObjectIdentifier?
    private let store: AudioStore
    private var remainingRepeats = 1
    private var remainingRange = 1
    private var observers: [NSObjectProtocol] = []
    private var timeObserver: Any?
    private var pending: Task<Void, Never>?
    /// What follows after the repeat-aloud pause. Stays put on "Pause" and runs immediately on "Weiter",
    /// so that state and player do not drift apart.
    private var resume: (() -> Void)?
    private var startMs = 0
    /// Word timings of the current surah (key `reciter-surah`).
    private var timings: (key: String, verses: [Int: [WordTimings.Word]])?
    public let wordTimings = WordTimings()
    public let surahTimings = SurahTimings()
    /// For `fullSurah`: end of the current verse in the surah file.
    private var endMs: Int?
    /// Transitions with timestamp (DEBUG only): `log stream --predicate 'subsystem == "dev.ms-solutions.kiblegah"'`.
    private static let daily = Logger(subsystem: "dev.ms-solutions.kiblegah", category: "oynatici")

    /// The current step as a whole.
    private var step: Step {
        get { Step(location: location, remainingRepeats: remainingRepeats, remainingRange: remainingRange) }
        set {
            location = newValue.location
            remainingRepeats = newValue.remainingRepeats
            remainingRange = newValue.remainingRange
        }
    }

    public init(store: AudioStore, cache: AudioCache = AudioCache()) {
        self.store = store
        self.cache = cache
        motor.attach(node)
        motor.attach(tempo)
        observers.append(
            NotificationCenter.default.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main
            ) { [weak self] notification in
                let item = (notification.object as AnyObject?).map(ObjectIdentifier.init)
                MainActor.assumeIsolated {
                    guard let self, item == self.playingItem else { return }
                    self.finished()
                }
            })
        observers.append(
            NotificationCenter.default.addObserver(
                forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: nil, queue: .main
            ) { [weak self] notification in
                let item = (notification.object as AnyObject?).map(ObjectIdentifier.init)
                MainActor.assumeIsolated {
                    guard let self, item == self.playingItem else { return }
                    self.hold(zamanYok: false)
                }
            })
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: motor, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.engineChanged() }
            })
        #if os(iOS)
            remoteCommands()
            observers.append(
                NotificationCenter.default.addObserver(
                    forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(),
                    queue: .main
                ) { [weak self] notification in
                    let tip = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                        .flatMap { AVAudioSession.InterruptionType(rawValue: $0) }
                    let option =
                        (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
                        .map { AVAudioSession.InterruptionOptions(rawValue: $0) } ?? []
                    MainActor.assumeIsolated {
                        self?.interruption(started: tip == .began, resumption: option.contains(.shouldResume))
                    }
                })
            // Headphones/Bluetooth disconnected: pause like Apple's player, instead of continuing
            // loudly over the speaker (the audio engine does not do this by itself).
            observers.append(
                NotificationCenter.default.addObserver(
                    forName: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance(),
                    queue: .main
                ) { [weak self] notification in
                    let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                        .flatMap { AVAudioSession.RouteChangeReason(rawValue: $0) }
                    guard reason == .oldDeviceUnavailable else { return }
                    MainActor.assumeIsolated {
                        guard let self, self.isPlaying else { return }
                        self.togglePause()
                    }
                })
        #endif
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 10), queue: .main
        ) { [weak self] t in
            MainActor.assumeIsolated { self?.timeAdvanced(t) }
        }
        Task { await cache.clear() }
    }

    /// Kuyruk over an arbitrary range (also across surahs, e.g. up to the end of the juz);
    /// basmala before verse 1 of every surah except Fâtiha and Tevbe.
    public nonisolated static func queue(
        verses: [(surah: Int, verse: Int)], withBasmala: Bool = true
    ) -> [QueueItem] {
        verses.flatMap { a -> [QueueItem] in
            let b = withBasmala && a.verse == 1 && a.surah != 1 && a.surah != 9
            return (b ? [QueueItem(surah: a.surah, verse: 1, basmala: true)] : []) + [
                QueueItem(surah: a.surah, verse: a.verse, basmala: false)
            ]
        }
    }

    /// Passes of an entry: the basmala only ever plays once.
    nonisolated static func repeatCount(_ s: QueueItem, repetition: Int) -> Int {
        s.basmala ? 1 : max(1, repetition)
    }

    /// The step after `a`: first the remaining passes of the same verse, then the next
    /// entry, at the end once more from the start as long as the range is repeated; `nil` = end.
    public nonisolated static func nextStep(_ a: Step, queue: [QueueItem], repetition: Int) -> Step? {
        if a.remainingRepeats > 1 {
            return Step(
                location: a.location, remainingRepeats: a.remainingRepeats - 1,
                remainingRange: a.remainingRange)
        }
        if a.location + 1 < queue.count {
            return Step(
                location: a.location + 1,
                remainingRepeats: repeatCount(queue[a.location + 1], repetition: repetition),
                remainingRange: a.remainingRange)
        }
        guard a.remainingRange > 1, let first = queue.first else { return nil }
        return Step(
            location: 0, remainingRepeats: repeatCount(first, repetition: repetition),
            remainingRange: a.remainingRange - 1)
    }

    /// Plays a finished Kuyruk; `word` > 1 starts in the first verse at this word.
    public func play(queue k: [QueueItem], word: Int = 1) {
        queue = k
        location = 0
        remainingRange = max(1, rangeRepeat)
        activateSession()
        load(word: word)
    }

    /// Kuyruk for a surah from `verse`; basmala before verse 1, except for Fâtiha (where it is verse 1) and Tevbe.
    public nonisolated static func queue(
        surah: Int, verseCount: Int, verse: Int, end: Int? = nil
    ) -> [QueueItem] {
        var k: [QueueItem] = []
        if verse == 1 && surah != 1 && surah != 9 && end == nil {
            k.append(QueueItem(surah: surah, verse: 1, basmala: true))
        }
        k += (verse...min(end ?? verseCount, verseCount)).map {
            QueueItem(surah: surah, verse: $0, basmala: false)
        }
        return k
    }

    /// Plays from `verse`; with `end` only up to there (dualar), then without basmala.
    public func play(surah: Int, verseCount: Int, verse: Int, end: Int? = nil) {
        play(queue: Self.queue(surah: surah, verseCount: verseCount, verse: verse, end: end))
    }

    public func togglePause() {
        pending?.cancel()
        pending = nil
        if isPlaying {
            if reciter.fullSurah != nil { player.pause() } else { node.pause() }
            isPlaying = false
        } else if isActive {
            if offlineError || zamanYok { return load(continueMs: continueMs) }
            isPlaying = true
            if let d = resume {
                resume = nil
                d()
            } else if reciter.fullSurah != nil {
                player.playImmediately(atRate: speed)
            } else {
                playNode()
            }
        }
        updateInfo()
    }

    /// To the next entry, remaining passes of the current verse skipped.
    public func next() {
        releasePause()
        let forNow = Step(location: location, remainingRepeats: 1, remainingRange: remainingRange)
        guard let n = Self.nextStep(forNow, queue: queue, repetition: repetition) else { return stop() }
        step = n
        load()
    }

    public func previous() {
        releasePause()
        guard location > 0 else { return load() }
        location -= 1
        load()
    }

    /// Stops, but leaves the bar in place so that it can say why nothing is playing.
    private func hold(zamanYok: Bool) {
        self.zamanYok = zamanYok
        offlineError = !zamanYok
        player.pause()
        node.pause()
        isPlaying = false
        updateInfo()
    }

    public func stop() {
        releasePause()
        currentWord = nil
        resetEngine()
        motor.stop()
        player.pause()
        player.removeAllItems()
        playingItem = nil
        isPlaying = false
        queue = []
        location = 0
        updateInfo()
    }

    private func releasePause() {
        pending?.cancel()
        pending = nil
        resume = nil
    }

    /// Deletes everything scheduled and resets the node's timeline; running loaders
    /// and callbacks of the old generation expire.
    private func resetEngine() {
        generation += 1
        filler?.task.cancel()
        filler = nil
        node.stop()
        scheduled = []
        totalFrames = 0
        sonFrame = 0
        positionTimer?.invalidate()
        positionTimer = nil
    }

    /// Starts the current step from the beginning (or from `continueMs`), for verse files via the
    /// store, for surah files streamed.
    private func load(word: Int = 1, continueMs: Int? = nil) {
        guard let s = current else { return stop() }
        releasePause()
        currentWord = nil
        startMs = 0
        endMs = nil
        self.continueMs = continueMs
        resetEngine()
        downloadCount += 1
        offlineError = false
        zamanYok = false
        if reciter.fullSurah != nil { return fromSurahFile(s) }
        player.pause()
        player.removeAllItems()
        playingItem = nil
        remainingRepeats = Self.repeatCount(s, repetition: repetition)
        let key = "\(reciter.id)-\(s.surah)"
        if !s.basmala, word > 1,
            let ms = timings.flatMap({ $0.key == key ? $0.verses[s.verse] : nil })?
                .first(where: { $0.index == word })?.start
        {
            startMs = ms
        }
        isPlaying = true
        updateInfo()
        loadWordTimings(s)
        log("yükle \(s.surah):\(s.verse)\(s.basmala ? " besmele" : "") ab \(continueMs ?? startMs) ms")
        fill()
    }

    /// The file of an entry: from the downloaded surahs, otherwise from the store (loads it).
    private func localFile(_ s: QueueItem) async -> URL? {
        let (surah, verse) = s.basmala ? (1, 1) : (s.surah, s.verse)
        if store.exists(reciter, surah: surah, verse: verse) {
            return store.local(reciter, surah: surah, verse: verse)
        }
        return await cache.fetch(reciter.remote(surah: surah, verse: verse))
    }

    private func loadWordTimings(_ s: QueueItem) {
        let key = "\(reciter.id)-\(s.surah)"
        if timings?.key != key, reciter.qcID != nil {
            let k = reciter
            Task {
                guard let z = await wordTimings.surah(s.surah, reciter: k) else { return }
                timings = (key, z)
            }
        }
    }

    /// The step after the last scheduled one – or the current one if nothing is scheduled –
    /// including its start point: a repetition begins where the first pass began.
    private func nextPlan() -> (step: Step, start: Int)? {
        guard let end = scheduled.last else { return (step, startMs) }
        guard let n = Self.nextStep(end.step, queue: queue, repetition: repetition) else { return nil }
        return (n, n.location == end.step.location ? end.start : 0)
    }

    /// Keeps store and plan filled: up to three files ahead in the store, up to two pieces ahead
    /// on the node – during a repeat-aloud pause only the current one, since the silence after it is intended.
    /// Runs once per generation; whoever sees the end of a piece triggers it again.
    private func fill() {
        guard reciter.fullSurah == nil, isActive, filler?.generation != generation else { return }
        let n = generation
        let task = Task { [weak self] in
            guard let self else { return }
            defer { if self.filler?.generation == n { self.filler = nil } }
            fillStock()
            while generation == n, !Task.isCancelled {
                let goal = delay > 0 ? 1 : 3
                guard scheduled.count < goal, let (a, start) = nextPlan() else { return }
                let entry = queue[a.location]
                guard let url = await localFile(entry), generation == n,
                    let file = try? AVAudioFile(forReading: url)
                else {
                    if generation == n, scheduled.isEmpty { hold(zamanYok: false) }
                    return
                }
                if file.processingFormat != connectedFormat {
                    guard scheduled.isEmpty else { return }
                    connect(file.processingFormat)
                }
                addPart(file, step: a, start: start, generation: n)
            }
        }
        filler = (n, task)
    }

    /// Fetch the files of the next steps in advance, independent of scheduling.
    private func fillStock() {
        var a: Step? = scheduled.last?.step ?? step
        for _ in 0..<3 {
            guard let x = a, let n = Self.nextStep(x, queue: queue, repetition: repetition) else { return }
            let entry = queue[n.location]
            Task { _ = await localFile(entry) }
            a = n
        }
    }

    /// Node → tempo → mixer in the file's format; a change is only possible with an empty plan.
    private func connect(_ format: AVAudioFormat) {
        motor.connect(node, to: tempo, format: format)
        motor.connect(tempo, to: motor.mainMixerNode, format: format)
        tempo.rate = speed
        connectedFormat = format
    }

    /// Schedules a piece after the existing ones; the first piece takes `continueMs` along and starts
    /// the node.
    private func addPart(_ file: AVAudioFile, step a: Step, start: Int, generation n: Int) {
        let ratio = file.processingFormat.sampleRate
        let start = scheduled.isEmpty ? (continueMs ?? start) : start
        continueMs = nil
        let ilkFrame = min(AVAudioFramePosition(Double(start) / 1000 * ratio), max(0, file.length - 1))
        let length = max(1, file.length - ilkFrame)
        let part = Segment(
            step: a, start: start, realStart: start, startFrame: totalFrames, length: length, ratio: ratio)
        scheduled.append(part)
        totalFrames += length
        let index = scheduled.count - 1
        node.scheduleSegment(
            file, startingFrame: ilkFrame, frameCount: AVAudioFrameCount(length), at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            Task { @MainActor in self?.partFinished(generation: n, part: part) }
        }
        log(
            "plan[\(index)] \(queue[a.location].surah):\(queue[a.location].verse) ab \(start) ms, \(length) Frames, tekrar \(a.remainingRepeats)"
        )
        if index == 0, isPlaying { playNode() }
    }

    /// Lets the node play (engine on, wall clock on).
    private func playNode() {
        if !motor.isRunning {
            do { try motor.start() } catch { return hold(zamanYok: false) }
        }
        node.play()
        if positionTimer == nil {
            positionTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.engineAdvanced() }
            }
            positionTimer?.tolerance = 0.02
        }
    }

    /// Position in the node's timeline; fresh while playing, otherwise the last measured one.
    private var motorFrame: AVAudioFramePosition {
        if node.isPlaying, let n = node.lastRenderTime, let p = node.playerTime(forNodeTime: n) {
            sonFrame = p.sampleTime
        }
        return sonFrame
    }

    /// Position in the current verse in ms, from the first scheduled piece.
    private var verseMs: Int? {
        guard let p = scheduled.first else { return nil }
        let f = max(0, motorFrame - p.startFrame)
        return p.realStart + Int(Double(f) / p.ratio * 1000)
    }

    /// Every 100 ms: the current word from the word timings.
    private func engineAdvanced() {
        guard isPlaying, resume == nil, let ms = verseMs, let s = current, !s.basmala,
            let l = timings.flatMap({ $0.key == "\(reciter.id)-\(s.surah)" ? $0.verses[s.verse] : nil })
        else { return }
        let yeni = WordTimings.word(l, ms: ms)
        if yeni != currentWord { currentWord = yeni }
    }

    /// End of a piece (real verse boundary). The next one is already playing if it was scheduled;
    /// otherwise – end, repeat-aloud pause, file not there yet – the timeline is started anew.
    private func partFinished(generation n: Int, part: Segment) {
        guard n == generation, let first = scheduled.first, first.startFrame == part.startFrame else {
            return
        }
        scheduled.removeFirst()
        let finishedBasmala = current?.basmala == true
        log(
            "ende \(current.map { "\($0.surah):\($0.verse)" } ?? "-") eingeplant=\(scheduled.count) frame=\(motorFrame)"
        )
        let resumption = { [weak self] in
            guard let self, self.generation == n else { return }
            if let next = self.scheduled.first {
                self.goToStep(next.step, start: next.start)
                return
            }
            guard let s = Self.nextStep(self.step, queue: self.queue, repetition: self.repetition) else {
                return self.stop()
            }
            self.resetEngine()
            self.goToStep(s, start: 0)
            self.fill()
        }
        guard delay > 0, !finishedBasmala else { return resumption() }
        node.pause()
        afterGap(resumption)
    }

    /// Adopts a step as the current one.
    private func goToStep(_ a: Step, start: Int) {
        step = a
        startMs = start
        currentWord = nil
        if let s = current { loadWordTimings(s) }
        updateInfo()
        fill()
        log("weiter \(current.map { "\($0.surah):\($0.verse)" } ?? "-") tekrar \(remainingRepeats)")
    }

    /// Repetition, pause, range or reciter were changed during playback: the
    /// current verse continues at its position, the rest is replanned. During a
    /// repeat-aloud pause the old plan stays.
    private func reschedule() {
        guard isActive, resume == nil else { return }
        if reciter.fullSurah != nil { return }
        guard !scheduled.isEmpty else { return }
        load(continueMs: verseMs)
    }

    /// Output changed (headphones, speaker): the engine is stopped; continue from the same position.
    private func engineChanged() {
        guard isActive, reciter.fullSurah == nil, !scheduled.isEmpty else { return }
        let ms = verseMs
        let shouldPlay = isPlaying
        load(continueMs: ms)
        if !shouldPlay { togglePause() }
    }

    #if os(iOS)
        /// Call or another app: pause; then resume if the system offers it.
        private func interruption(started: Bool, resumption: Bool) {
            if started, isPlaying {
                togglePause()
            } else if !started, resumption, !isPlaying, isActive {
                togglePause()
            }
        }
    #endif

    /// Preloads the word timings of a surah (e.g. before „ab diesem Wort“ is offered).
    public func prepareTimings(surah: Int) async -> Bool {
        let key = "\(reciter.id)-\(surah)"
        if timings?.key == key { return true }
        guard let z = await wordTimings.surah(surah, reciter: reciter) else { return false }
        timings = (key, z)
        return true
    }

    /// Whole surah in one file: jump to the start of the verse and trigger `finished()` at the end of the verse
    /// as with a single file. If the next verse follows directly, the file simply keeps playing.
    private func fromSurahFile(_ s: QueueItem, repeatPlayback: Bool = false) {
        guard let url = reciter.surahFile(s.surah) else { return stop() }
        let k = reciter
        Task {
            let result = await surahTimings.surah(s.surah, reciter: k)
            // Meanwhile another surah was selected: do not stop its playback.
            guard current == s else { return }
            let z: [Int: SurahTimings.VerseTiming]
            switch result {
            case .ready(let h): z = h
            case .notYet: return hold(zamanYok: true)
            case .unreachable: return hold(zamanYok: false)
            }
            let first = z[1]?.start ?? 0
            let (start, end) = s.basmala ? (0, first) : (z[s.verse]?.start ?? 0, z[s.verse]?.end ?? Int.max)
            startMs = start
            endMs = end
            if !repeatPlayback { remainingRepeats = Self.repeatCount(s, repetition: repetition) }
            let same = (player.currentItem?.asset as? AVURLAsset)?.url == url
            if !same {
                player.removeAllItems()
                let item = AVPlayerItem(url: url)
                player.insert(item, after: nil)
                playingItem = ObjectIdentifier(item)
            }
            let now = Int(player.currentTime().seconds * 1000)
            if !same || abs(now - start) > 400 {
                await player.seek(to: CMTime(value: CMTimeValue(start), timescale: 1000))
            }
            player.playImmediately(atRate: speed)
            isPlaying = true
            updateInfo()
            log("sure-dosyası \(s.surah):\(s.verse) \(start)–\(end) ms, stand \(now) ms")
        }
    }

    private func timeAdvanced(_ t: CMTime) {
        guard isPlaying, resume == nil, reciter.fullSurah != nil else { return }
        if let b = endMs, Int(t.seconds * 1000) >= b {
            endMs = nil
            finished()
            return
        }
        guard let s = current, !s.basmala,
            let l = timings.flatMap({ $0.key == "\(reciter.id)-\(s.surah)" ? $0.verses[s.verse] : nil })
        else { return }
        let yeni = WordTimings.word(l, ms: Int(t.seconds * 1000))
        if yeni != currentWord { currentWord = yeni }
    }

    /// End of verse in the surah file (time observer) or end of the file itself.
    private func finished() {
        remainingRepeats -= 1
        // The surah file would otherwise simply keep playing during the pause or repetition.
        if delay > 0 || remainingRepeats > 0 { player.pause() }
        let resumption = { [weak self] in
            guard let self else { return }
            if self.remainingRepeats > 0, let s = self.current {
                self.fromSurahFile(s, repeatPlayback: true)
            } else {
                self.next()
            }
        }
        guard delay > 0, current?.basmala == false else { return resumption() }
        afterGap(resumption)
    }

    /// Repeat-aloud pause: `resumption` runs after `delay` seconds, or immediately on "Weiter".
    private func afterGap(_ resumption: @escaping () -> Void) {
        currentWord = nil
        resume = resumption
        pending = Task { [delay] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let d = resume else { return }
            resume = nil
            d()
        }
    }

    private func log(_ message: String) {
        #if DEBUG
            let t = CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock()))
            Self.daily.info(
                "\(t, format: .fixed(precision: 3), privacy: .public) \(message, privacy: .public)")
            track.append(String(format: "%.3f ", t) + message)
            if track.count > 200 { track.removeFirst() }
        #endif
    }

    private func activateSession() {
        #if os(iOS)
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    private func updateInfo() {
        #if os(iOS)
            guard let s = current else {
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
                return
            }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = [
                MPMediaItemPropertyTitle: "\(s.surah):\(s.verse)",
                MPMediaItemPropertyArtist: reciter.name,
                MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? speed : 0,
            ]
        #endif
    }

    #if os(iOS)
        private func remoteCommands() {
            let m = MPRemoteCommandCenter.shared()
            m.togglePlayPauseCommand.addTarget { [weak self] _ in
                MainActor.assumeIsolated { self?.togglePause() }
                return .success
            }
            m.playCommand.addTarget { [weak self] _ in
                MainActor.assumeIsolated { if self?.isPlaying == false { self?.togglePause() } }
                return .success
            }
            m.pauseCommand.addTarget { [weak self] _ in
                MainActor.assumeIsolated { if self?.isPlaying == true { self?.togglePause() } }
                return .success
            }
            m.nextTrackCommand.addTarget { [weak self] _ in
                MainActor.assumeIsolated { self?.next() }
                return .success
            }
            m.previousTrackCommand.addTarget { [weak self] _ in
                MainActor.assumeIsolated { self?.previous() }
                return .success
            }
        }
    #endif
}
