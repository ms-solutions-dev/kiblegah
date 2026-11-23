import Testing

@testable import Core

/// Tabs per app target: filtered and padded; the stored list itself stays unchanged.
@Suite struct TabEditionTests {
    @Test func filteredTabIsFilledUp() {
        let stored: [AppTab] = [.prayerTimes, .qibla, .quran, .talks]
        #expect(
            AppTab.normalized(stored, allowed: { $0 != .talks }) == [.prayerTimes, .qibla, .quran, .duas])
        #expect(AppTab.normalized(stored) == stored)
        #expect(!AppTab.normalized(AppTab.standard, allowed: { $0 != .talks }).contains(.talks))
    }
}
