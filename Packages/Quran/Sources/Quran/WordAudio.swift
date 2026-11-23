import AVFoundation
import Core
import Foundation

/// Speak a single word: the word recordings are publicly
/// available on the Quran.com CDN, one short MP3 per word. For the Store edition the
/// QF terms apply.
@MainActor public final class WordAudio {
    public static let shared = WordAudio()
    private let player = AVPlayer()

    /// `https://audio.qurancdn.com/wbw/002_255_001.mp3`
    public nonisolated static func address(surah: Int, verse: Int, word: Int) -> URL? {
        URL(string: String(format: "https://audio.qurancdn.com/wbw/%03d_%03d_%03d.mp3", surah, verse, word))
    }

    public func play(_ key: ContentKey) {
        guard case .word(let s, let a, let k) = key, let url = Self.address(surah: s, verse: a, word: k)
        else { return }
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.play()
    }
}
