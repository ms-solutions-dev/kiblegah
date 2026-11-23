import DesignSystem
import SwiftUI

/// Round button „to the verse being read“ as in the map navigation: appears when the user scrolled away
/// by themselves during playback, and switches following back on.
struct FollowAlongButton: View {
    @Environment(\.theme) private var theme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "location.north.line.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.colors.accent)
                .frame(width: 52, height: 52)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(localized("kuran.takip.don"))
        .padding(.trailing, 16)
        .padding(.bottom, 12)
        .transition(.scale.combined(with: .opacity))
    }
}

#if DEBUG
    import ContentPacks
    import Quran

    /// Screenshots without a tap: `-testCal 93:9` plays from this verse to the end of the next surah
    /// (including the surah change); with `-testTakipKapali YES` following pauses after 6 s as after
    /// scrolling away by oneself, so that the center button becomes visible.
    @MainActor func followCheck(
        _ player: RecitationPlayer, _ contentProvider: (any ContentProvider)?, stopFollowing: () -> Void
    ) async {
        let d = UserDefaults.standard
        guard let m = d.string(forKey: "testCal"), let contentProvider else { return }
        let p = m.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2, let s = contentProvider.surah(p[0]) else { return }
        var k = RecitationPlayer.queue(surah: s.number, verseCount: s.verseCount, verse: p[1])
        if let s2 = contentProvider.surah(s.number + 1) {
            k += RecitationPlayer.queue(surah: s2.number, verseCount: s2.verseCount, verse: 1)
        }
        player.play(queue: k)
        guard d.bool(forKey: "testTakipKapali") else { return }
        try? await Task.sleep(for: .seconds(6))
        stopFollowing()
    }
#endif
