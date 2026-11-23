import Core
import Foundation
import Testing

@testable import UserData

@MainActor @Suite struct AppSettingsTests {
    func cleanDefaults() -> UserDefaults {
        let name = "test.\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @Test func defaultValues() {
        let a = AppSettings(defaults: cleanDefaults())
        #expect(a.appearance == .system)
        #expect(!a.largeAndSimple)
        #expect(a.tabs == AppTab.standard)
        #expect(a.karahatMinutes == 45)
        #expect(!a.iCloud)
        #expect(a.location == nil)
        #expect(a.automaticLocation)
        #expect(a.prayerTimeMethod == .diyanet)
    }

    @Test func prayerCalculationIsPersistent() {
        let d = cleanDefaults()
        AppSettings(defaults: d).prayerTimeMethod = .diyanet
        #expect(AppSettings(defaults: d).prayerTimeMethod == .diyanet)
    }

    @Test func locationIsPersistent() {
        let d = cleanDefaults()
        let a = AppSettings(defaults: d)
        a.location = .sample
        a.automaticLocation = false
        let b = AppSettings(defaults: d)
        #expect(b.location == .sample)
        #expect(!b.automaticLocation)
        b.location = nil
        #expect(AppSettings(defaults: d).location == nil)
    }

    @Test func isPersistent() {
        let d = cleanDefaults()
        let a = AppSettings(defaults: d)
        a.appearance = .byPrayerTime
        a.tabs = [.dhikr, .prayerTimes, .qibla, .quran]
        let b = AppSettings(defaults: d)
        #expect(b.appearance == .byPrayerTime)
        #expect(b.tabs == [.dhikr, .prayerTimes, .qibla, .quran])
    }

    @Test func invalidTabsAreFixed() {
        let a = AppSettings(defaults: cleanDefaults())
        a.tabs = [.discover, .dhikr]
        #expect(a.tabs.count == 4)
        #expect(!a.tabs.contains(.discover))
    }
}
