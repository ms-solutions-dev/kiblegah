import Foundation

extension Notification.Name {
    /// A video is about to take the audio session; the Quran player pauses and leaves the lock screen to it.
    public static let videoPlaybackWillStart = Notification.Name(
        "dev.ms-solutions.kiblegah.videoPlaybackWillStart")
}
