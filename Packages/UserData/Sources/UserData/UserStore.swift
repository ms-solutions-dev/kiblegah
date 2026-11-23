import Foundation
import Observation
import SwiftData

/// Reading and writing the user data for the UI package.
@MainActor @Observable public final class UserStore {
    public let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    /// Counts changes so that views re-read.
    public private(set) var version = 0

    public init(container: ModelContainer) {
        self.container = container
    }

    private func save() {
        try? context.save()
        version += 1
    }

    func saveExternal() { save() }

    // MARK: Notum

    public func note(_ key: String) -> Notum? {
        var d = FetchDescriptor<Notum>(predicate: #Predicate { $0.anahtar == key })
        d.sortBy = [SortDescriptor(\.degisiklik, order: .reverse)]
        return try? context.fetch(d).first
    }

    /// Saves the text; an empty text deletes the note.
    public func saveNote(_ key: String, text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let n = note(key) {
            if cleaned.isEmpty {
                context.delete(n)
            } else {
                n.metin = text
                n.degisiklik = .now
            }
        } else if !cleaned.isEmpty {
            context.insert(Notum(anahtar: key, metin: text))
        }
        save()
    }

    public func archiveNote(_ key: String, _ archived: Bool) {
        guard let n = note(key) else { return }
        n.arsiv = archived
        n.degisiklik = .now
        save()
    }

    public func notes(archived: Bool? = nil) -> [Notum] {
        let d = FetchDescriptor<Notum>(sortBy: [SortDescriptor(\.degisiklik, order: .reverse)])
        let all = (try? context.fetch(d)) ?? []
        guard let archived else { return all }
        return all.filter { $0.arsiv == archived }
    }

    // MARK: Kaydedilen

    public func isSaved(_ key: String) -> Bool {
        ((try? context.fetchCount(FetchDescriptor<Kayit>(predicate: #Predicate { $0.anahtar == key })))
            ?? 0) > 0
    }

    public func toggleSaved(_ key: String) {
        let d = FetchDescriptor<Kayit>(predicate: #Predicate { $0.anahtar == key })
        let existing = (try? context.fetch(d)) ?? []
        if existing.isEmpty { context.insert(Kayit(anahtar: key)) } else { existing.forEach(context.delete) }
        save()
    }

    public func saved() -> [Kayit] {
        (try? context.fetch(FetchDescriptor<Kayit>(sortBy: [SortDescriptor(\.tarih, order: .reverse)]))) ?? []
    }

    // MARK: Reading

    public func lastPosition(khatm: String = "") -> String? {
        var d = FetchDescriptor<KaldiginYer>(predicate: #Predicate { $0.hatim == khatm })
        d.sortBy = [SortDescriptor(\.tarih, order: .reverse)]
        return (try? context.fetch(d).first)?.anahtar
    }

    public func saveLastPosition(_ key: String, khatm: String = "") {
        let d = FetchDescriptor<KaldiginYer>(predicate: #Predicate { $0.hatim == khatm })
        let existing = (try? context.fetch(d)) ?? []
        if let first = existing.first {
            first.anahtar = key
            first.tarih = .now
            existing.dropFirst().forEach(context.delete)
        } else {
            context.insert(KaldiginYer(anahtar: key, hatim: khatm))
        }
        save()
    }

    /// A section that was read; glances that are too short (under 3 s) do not count.
    public func addReading(
        firstIndex: Int, lastIndex: Int, seconds: Double, date: Date = .now, khatm: String = ""
    ) {
        guard seconds >= 3, firstIndex > 0, lastIndex >= firstIndex else { return }
        context.insert(
            OkumaOturumu(ilkSira: firstIndex, sonSira: lastIndex, saniye: seconds, tarih: date, hatim: khatm))
        save()
    }

    public func sessions(khatm: String = "") -> [OkumaOturumu] {
        let d = FetchDescriptor<OkumaOturumu>(
            predicate: #Predicate { $0.hatim == khatm }, sortBy: [SortDescriptor(\.tarih)])
        return (try? context.fetch(d)) ?? []
    }

    /// How many distinct verses have been read (khatm progress).
    public func versesReadCount(khatm: String = "") -> Int {
        ReadingStats.merged(sessions(khatm: khatm).map { $0.ilkSira...$0.sonSira })
    }

    /// On how many days of the current week reading took place.
    public func thisWeekDays(khatm: String = "", now: Date = .now, calendar: Calendar = .current) -> Int {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        let days = Set(
            sessions(khatm: khatm).filter { week.contains($0.tarih) }.map {
                calendar.startOfDay(for: $0.tarih)
            })
        return days.count
    }
}

extension UserStore {
    nonisolated static func dayText(_ t: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: t)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    /// Counts `n` (also −1) for today; never below zero.
    public func addDhikr(_ dhikr: String, _ n: Int = 1, date: Date = .now, calendar: Calendar = .current) {
        let g = Self.dayText(date, calendar)
        let d = FetchDescriptor<ZikirGunu>(predicate: #Predicate { $0.gun == g && $0.zikir == dhikr })
        if let k = try? container.mainContext.fetch(d).first {
            k.adet = max(0, k.adet + n)
        } else if n > 0 {
            container.mainContext.insert(ZikirGunu(gun: g, zikir: dhikr, adet: n))
        }
        try? container.mainContext.save()
    }

    public func dhikrTotal(days: Int, now: Date = .now, calendar: Calendar = .current) -> Int {
        let first = calendar.date(byAdding: .day, value: -(days - 1), to: now) ?? now
        let limit = Self.dayText(first, calendar)
        let d = FetchDescriptor<ZikirGunu>(predicate: #Predicate { $0.gun >= limit })
        return ((try? container.mainContext.fetch(d)) ?? []).reduce(0) { $0 + $1.adet }
    }
}

extension UserStore {
    public func collections() -> [Koleksiyon] {
        (try? container.mainContext.fetch(
            FetchDescriptor<Koleksiyon>(sortBy: [SortDescriptor(\.sira), SortDescriptor(\.olusturma)]))) ?? []
    }

    @discardableResult
    public func createCollection(_ name: String) -> Koleksiyon {
        let k = Koleksiyon(ad: name, sira: collections().count)
        container.mainContext.insert(k)
        saveExternal()
        return k
    }

    public func renameCollection(_ k: Koleksiyon, _ name: String) {
        k.ad = name
        saveExternal()
    }

    public func deleteCollection(_ k: Koleksiyon) {
        let identifier = k.kimlik
        for o
            in (try? container.mainContext.fetch(
                FetchDescriptor<KoleksiyonOgesi>(predicate: #Predicate { $0.koleksiyon == identifier })))
            ?? []
        {
            container.mainContext.delete(o)
        }
        container.mainContext.delete(k)
        saveExternal()
    }

    public func items(_ k: Koleksiyon) -> [String] {
        let identifier = k.kimlik
        let d = FetchDescriptor<KoleksiyonOgesi>(
            predicate: #Predicate { $0.koleksiyon == identifier },
            sortBy: [SortDescriptor(\.tarih, order: .reverse)])
        return ((try? container.mainContext.fetch(d)) ?? []).map(\.anahtar)
    }

    public func contains(_ key: String, _ k: Koleksiyon) -> Bool {
        let identifier = k.kimlik
        return
            ((try? container.mainContext.fetchCount(
                FetchDescriptor<KoleksiyonOgesi>(
                    predicate: #Predicate { $0.koleksiyon == identifier && $0.anahtar == key }))) ?? 0) > 0
    }

    /// Add or remove (toggle in the menu).
    public func toggleCollection(_ key: String, _ k: Koleksiyon) {
        let identifier = k.kimlik
        let d = FetchDescriptor<KoleksiyonOgesi>(
            predicate: #Predicate { $0.koleksiyon == identifier && $0.anahtar == key })
        let existingItems = (try? container.mainContext.fetch(d)) ?? []
        if existingItems.isEmpty {
            container.mainContext.insert(KoleksiyonOgesi(koleksiyon: identifier, anahtar: key))
        } else {
            existingItems.forEach(container.mainContext.delete)
        }
        saveExternal()
    }
}

extension UserStore {
    /// Own reading positions (without the default khatm).
    public func khatms() -> [Hatim] {
        let d = FetchDescriptor<Hatim>(
            predicate: #Predicate { $0.kimlik != "" }, sortBy: [SortDescriptor(\.baslangic)])
        return (try? container.mainContext.fetch(d)) ?? []
    }

    /// Goal of a reading position, without creating anything (for views).
    public func goal(_ identifier: String) -> ReadingGoal? {
        let d = FetchDescriptor<Hatim>(predicate: #Predicate { $0.kimlik == identifier })
        return (try? container.mainContext.fetch(d).first)?.goal
    }

    /// The entry of a reading position; for the default khatm it is created on demand.
    public func khatm(_ identifier: String) -> Hatim? {
        let d = FetchDescriptor<Hatim>(predicate: #Predicate { $0.kimlik == identifier })
        if let h = try? container.mainContext.fetch(d).first { return h }
        guard identifier.isEmpty else { return nil }
        let h = Hatim(kimlik: "", ad: "")
        container.mainContext.insert(h)
        saveExternal()
        return h
    }

    @discardableResult
    public func createKhatm(_ name: String, goal: ReadingGoal?) -> Hatim {
        let h = Hatim(ad: name)
        container.mainContext.insert(h)
        saveGoal(h, goal)
        return h
    }

    public func saveGoal(_ h: Hatim, _ goal: ReadingGoal?) {
        h.hedefTuru = goal?.kind.rawValue ?? ""
        h.hedefDeger = goal?.value ?? 0
        h.bitis = goal?.end
        saveExternal()
    }

    /// Deletes the reading position together with reading events and Kaldığın-yer.
    public func deleteKhatm(_ h: Hatim) {
        let k = h.kimlik
        for o
            in (try? container.mainContext.fetch(
                FetchDescriptor<OkumaOturumu>(predicate: #Predicate { $0.hatim == k }))) ?? []
        {
            container.mainContext.delete(o)
        }
        for o
            in (try? container.mainContext.fetch(
                FetchDescriptor<KaldiginYer>(predicate: #Predicate { $0.hatim == k }))) ?? []
        {
            container.mainContext.delete(o)
        }
        container.mainContext.delete(h)
        saveExternal()
    }
}

extension UserStore {
    /// Memorization cards, due ones first.
    public func memorizationCards() -> [EzberKarti] {
        (try? container.mainContext.fetch(FetchDescriptor<EzberKarti>(sortBy: [SortDescriptor(\.sonraki)])))
            ?? []
    }

    public func isMemorizing(_ key: String) -> Bool {
        ((try? container.mainContext.fetchCount(
            FetchDescriptor<EzberKarti>(predicate: #Predicate { $0.anahtar == key }))) ?? 0) > 0
    }

    public func addToMemorization(_ key: String) {
        guard !isMemorizing(key) else { return }
        container.mainContext.insert(EzberKarti(anahtar: key))
        saveExternal()
    }

    public func removeFromMemorization(_ k: EzberKarti) {
        container.mainContext.delete(k)
        saveExternal()
    }

    public func rateMemorization(_ k: EzberKarti, _ score: MemorizationScheduler.Rating, now: Date = .now) {
        let y = MemorizationScheduler.next(
            interval: k.aralik, ease: k.kolaylik, repetition: k.tekrar, score: score)
        k.aralik = y.interval
        k.kolaylik = y.ease
        k.tekrar = y.repetition
        k.sonraki = now.addingTimeInterval(y.interval * 86400)
        saveExternal()
    }
}

/// Repetition at growing intervals (simplified SM-2): „Zor“ resets to tomorrow,
/// „İyi“ and „Kolay“ extend; „Kolay“ additionally with a bonus.
public enum MemorizationScheduler {
    public enum Rating: Sendable, CaseIterable { case zor, good, kolay }

    public static func next(
        interval: Double, ease: Double, repetition: Int, score: Rating
    )
        -> (interval: Double, ease: Double, repetition: Int)
    {
        switch score {
        case .zor:
            return (1, max(1.3, ease - 0.2), 0)
        case .good, .kolay:
            let bonus = score == .kolay ? 1.3 : 1.0
            let newEase = min(3.0, ease + (score == .kolay ? 0.15 : 0))
            let yeni: Double =
                switch repetition {
                case 0: score == .kolay ? 4 : 1
                case 1: score == .kolay ? 7 : 3
                default: (interval * ease * bonus).rounded()
                }
            return (min(yeni, 365), newEase, repetition + 1)
        }
    }

    /// Due by the end of the day.
    public static func isDue(_ next: Date, now: Date = .now, calendar: Calendar = .current) -> Bool {
        next <= (calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now)
    }
}

public enum ReadingStats {
    /// State of a day in the week bar.
    public enum Day: Sendable, Equatable {
        case done, partial, empty, upcoming
    }

    public struct DaySummary: Sendable, Equatable {
        public var verse = 0
        public var page = 0
        public var seconds = 0.0
    }

    /// What was read on a day. `pageStarts`: first Sıra per mushaf page (ascending).
    public static func summary(
        _ sessions: [OkumaOturumu], day: Date, pageStarts: [Int], calendar: Calendar = .current
    ) -> DaySummary {
        let o = sessions.filter { calendar.isDate($0.tarih, inSameDayAs: day) }
        let intervals = o.map { $0.ilkSira...$0.sonSira }
        var pages = Set<Int>()
        for a in intervals {
            let first = page(a.lowerBound, pageStarts)
            let end = page(a.upperBound, pageStarts)
            pages.formUnion(first...end)
        }
        return DaySummary(
            verse: merged(intervals), page: pages.count, seconds: o.reduce(0) { $0 + $1.saniye })
    }

    /// Page (1-based) of a verse.
    static func page(_ index: Int, _ starts: [Int]) -> Int {
        var lo = 0
        var hi = starts.count
        while lo < hi {
            let m = (lo + hi) / 2
            if starts[m] <= index { lo = m + 1 } else { hi = m }
        }
        return max(1, lo)
    }

    /// Daily goal in the unit of the goal; with `end` the remainder divided by the remaining days (including today).
    public static func dailyGoal(
        _ h: ReadingGoal, readCount: Int, readToday: Int = 0, total: Int = 6236, now: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        switch h.kind {
        case .verses, .pages, .minutes: return max(1, h.value)
        case .finishDate:
            guard let b = h.end else { return 0 }
            let day =
                (calendar.dateComponents(
                    [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: b)
                ).day ?? 0) + 1
            let remaining = max(0, total - (readCount - readToday))
            return Int((Double(remaining) / Double(max(1, day))).rounded(.up))
        }
    }

    /// Progress of a day in the unit of the goal (with `end`: verses).
    public static func value(_ o: DaySummary, _ kind: GoalKind) -> Int {
        switch kind {
        case .verses, .finishDate: o.verse
        case .pages: o.page
        case .minutes: Int(o.seconds / 60)
        }
    }

    /// The current week (by calendar, e.g. Mon–Sun) with four states.
    public static func week(
        _ sessions: [OkumaOturumu], goal: ReadingGoal?, readCount: Int, pageStarts: [Int],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [(day: Date, status: Day)] {
        guard let w = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
        let today = calendar.startOfDay(for: now)
        return (0..<7).compactMap { i -> (Date, Day)? in
            guard let g = calendar.date(byAdding: .day, value: i, to: w.start) else { return nil }
            if g > today { return (g, .upcoming) }
            let o = summary(sessions, day: g, pageStarts: pageStarts, calendar: calendar)
            if o.verse == 0 && o.seconds == 0 { return (g, .empty) }
            guard let goal else { return (g, .done) }
            let target = dailyGoal(goal, readCount: readCount, readToday: o.verse, now: g, calendar: calendar)
            return (g, value(o, goal.kind) >= target ? .done : .partial)
        }
    }

    /// Consecutive days with reading; keeps counting up to yesterday as long as nothing has been read today yet.
    public static func streak(
        _ sessions: [OkumaOturumu], now: Date = .now, calendar: Calendar = .current
    ) -> Int {
        let days = Set(sessions.map { calendar.startOfDay(for: $0.tarih) })
        var g = calendar.startOfDay(for: now)
        if !days.contains(g) { g = calendar.date(byAdding: .day, value: -1, to: g) ?? g }
        var n = 0
        while days.contains(g) {
            n += 1
            g = calendar.date(byAdding: .day, value: -1, to: g) ?? g
        }
        return n
    }

    /// Number of verses in the union of the ranges.
    public static func merged(_ intervals: [ClosedRange<Int>]) -> Int {
        let ordered = intervals.sorted { $0.lowerBound < $1.lowerBound }
        var total = 0
        var current: ClosedRange<Int>?
        for a in ordered {
            if let s = current, a.lowerBound <= s.upperBound + 1 {
                current = s.lowerBound...max(s.upperBound, a.upperBound)
            } else {
                if let s = current { total += s.count }
                current = a
            }
        }
        if let s = current { total += s.count }
        return total
    }
}

extension UserStore {
    /// AI conversations, most recently active first.
    public func aiChats() -> [KiSohbeti] {
        (try? container.mainContext.fetch(
            FetchDescriptor<KiSohbeti>(sortBy: [SortDescriptor(\.guncelleme, order: .reverse)]))) ?? []
    }

    public func aiChat(_ identifier: String) -> KiSohbeti? {
        try? container.mainContext.fetch(
            FetchDescriptor<KiSohbeti>(predicate: #Predicate { $0.kimlik == identifier })
        )
        .first
    }

    /// Creates the conversation or continues writing it.
    public func saveAIChat(
        _ identifier: String, title: String, verse: String, session: String, messages: Data
    ) {
        let s =
            aiChat(identifier)
            ?? {
                let yeni = KiSohbeti(kimlik: identifier)
                container.mainContext.insert(yeni)
                return yeni
            }()
        if s.baslik.isEmpty { s.baslik = String(title.prefix(120)) }
        s.ayet = verse
        s.oturum = session
        s.mesajlar = messages
        s.guncelleme = .now
        saveExternal()
    }

    public func deleteAIChat(_ s: KiSohbeti) {
        container.mainContext.delete(s)
        saveExternal()
    }

    // MARK: - Books ()

    public func bookBookmarks(_ book: String? = nil) -> [KitapIsareti] {
        let d =
            book.map { k in FetchDescriptor<KitapIsareti>(predicate: #Predicate { $0.kitap == k }) }
            ?? FetchDescriptor<KitapIsareti>(sortBy: [SortDescriptor(\.tarih, order: .reverse)])
        return (try? context.fetch(d)) ?? []
    }

    /// Highlights from tafsir books whose passage deals with this verse.
    public func verseBookmarks(surah: Int, verse: Int) -> [KitapIsareti] {
        let d = FetchDescriptor<KitapIsareti>(
            predicate: #Predicate { $0.ayetSure == surah && $0.ayetIlk <= verse && $0.ayetSon >= verse },
            sortBy: [SortDescriptor(\.tarih, order: .reverse)])
        return (try? context.fetch(d)) ?? []
    }

    /// Creates or replaces (same `identifier`).
    public func saveBookBookmark(
        identifier: String, book: String, kind: String, location: String, text: String, note: String,
        fraction: Double,
        section: String, verse: (surah: Int, first: Int, end: Int)?, date: Date
    ) {
        let d = FetchDescriptor<KitapIsareti>(predicate: #Predicate { $0.kimlik == identifier })
        let i: KitapIsareti
        if let existing = try? context.fetch(d).first {
            i = existing
        } else {
            i = KitapIsareti(
                kimlik: identifier, kitap: book, tur: kind, konum: location, metin: text, anteil: fraction)
            context.insert(i)
        }
        i.tur = kind
        i.not = note
        i.bolum = section
        i.tarih = date
        if let verse {
            i.ayetSure = verse.surah
            i.ayetIlk = verse.first
            i.ayetSon = verse.end
        }
        save()
    }

    public func deleteBookBookmark(_ identifier: String) {
        let d = FetchDescriptor<KitapIsareti>(predicate: #Predicate { $0.kimlik == identifier })
        ((try? context.fetch(d)) ?? []).forEach(context.delete)
        save()
    }

    public func bookPosition(_ book: String) -> KitapKonumu? {
        let d = FetchDescriptor<KitapKonumu>(
            predicate: #Predicate { $0.kitap == book }, sortBy: [SortDescriptor(\.tarih, order: .reverse)])
        return try? context.fetch(d).first
    }

    public func lastBookPosition() -> KitapKonumu? {
        var d = FetchDescriptor<KitapKonumu>(sortBy: [SortDescriptor(\.tarih, order: .reverse)])
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    public func saveBookPosition(_ book: String, location: String, fraction: Double) {
        let d = FetchDescriptor<KitapKonumu>(predicate: #Predicate { $0.kitap == book })
        let existing = (try? context.fetch(d)) ?? []
        if let k = existing.first {
            k.konum = location
            k.anteil = fraction
            k.tarih = .now
            // Merge duplicates from two devices
            existing.dropFirst().forEach(context.delete)
        } else {
            context.insert(KitapKonumu(kitap: book, konum: location, anteil: fraction))
        }
        save()
    }
}
