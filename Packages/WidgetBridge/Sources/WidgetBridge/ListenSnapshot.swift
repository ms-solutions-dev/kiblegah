import AppIntents
import Foundation

/// What was listened to last, for the widget „Kur'an dinle“ (following „Weiterhören“ from
/// StoryShelf). The app writes it when playback starts, pauses or the surah changes.
public struct ListenSnapshot: Codable, Sendable, Equatable {
    enum CodingKeys: String, CodingKey {
        case surah = "sure"
        case verse = "ayet"
        case surahName = "sureAdi"
        case verseCount = "ayetSayisi"
        case reciter = "kari"
        case isPlaying = "caliyor"
        case date = "tarih"
    }

    public let surah: Int
    public let verse: Int
    /// „Kehf“
    public let surahName: String
    public let verseCount: Int
    public let reciter: String
    public let isPlaying: Bool
    public let date: Date

    public init(
        surah: Int, verse: Int, surahName: String, verseCount: Int, reciter: String, isPlaying: Bool,
        date: Date = .now
    ) {
        self.surah = surah
        self.verse = verse
        self.surahName = surahName
        self.verseCount = verseCount
        self.reciter = reciter
        self.isPlaying = isPlaying
        self.date = date
    }

    public var link: URL? { URL(string: "kiblegah://kuran/\(surah):\(verse)") }

    public static let fileName = "dinle.json"
    public static let kind = "kuran-dinle"

    public static func file() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: PrayerTimesSnapshot.appGroup)?
            .appending(
                path: fileName)
    }

    public func save(_ url: URL? = ListenSnapshot.file()) {
        guard let url, let veri = try? JSONEncoder().encode(self) else { return }
        try? veri.write(to: url, options: .atomic)
    }

    public static func load(_ url: URL? = ListenSnapshot.file()) -> ListenSnapshot? {
        guard let url, let veri = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ListenSnapshot.self, from: veri)
    }
}

/// The path from the widget button into the app's player. The app sets it in `init`, before a
/// scene exists - so it also works when the system first starts the app in the background for the button
/// (StoryShelf finding of Sep 20: with a scene this was `nil` in the morning).
@MainActor public enum ListenHandoff {
    /// Plays `surah` from `verse`, or toggles pause/resume if exactly that is already loaded in the player.
    public static var toggle: ((_ surah: Int, _ verse: Int) async -> Bool)?
}

/// The play/pause button in the widget. As an `AudioPlaybackIntent`, `perform()` runs in the app's
/// process, even in the background, and does not bring it to the foreground - like with music and podcasts.
public struct KuranDinleNiyeti: AudioPlaybackIntent {
    public static let title: LocalizedStringResource = "Kur'an dinle"
    public static let openAppWhenRun = false
    public static let isDiscoverable = false

    @Parameter(title: "Sure") public var surah: Int
    @Parameter(title: "Ayet") public var verse: Int

    public init() {}

    public init(surah: Int, verse: Int) {
        self.surah = surah
        self.verse = verse
    }

    @MainActor public func perform() async throws -> some IntentResult {
        _ = await ListenHandoff.toggle?(surah, verse)
        return .result()
    }
}
