import Foundation
import Observation

/// The position in the Quran, shared by the surah view and the Mushaf: whoever pages on in one
/// view - even into another surah - finds the position again in the other.
/// Each view only adopts what the other wrote after it was itself opened;
/// so a freshly opened reader does not jump to an old Mushaf position.
@MainActor @Observable final class QuranPosition {
    static let shared = QuranPosition()

    enum Source { case scrollProxy, mushaf }

    /// Consecutive verse number (1…6236).
    private(set) var index: Int?
    private(set) var source: Source?
    private(set) var timeZone: Date = .distantPast

    func save(_ index: Int, _ source: Source) {
        guard index != self.index || source != self.source else { return }
        self.index = index
        self.source = source
        timeZone = .now
    }

    /// The position, if it comes from the other view and is newer than `launch`.
    func fromOther(_ ben: Source, after launch: Date) -> Int? {
        guard let index, source != ben, timeZone > launch else { return nil }
        return index
    }
}
