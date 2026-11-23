import Foundation
import Testing

@testable import Core

/// Move of the screen settings into the App Group.
@Suite struct GroupDefaultsTests {
    private func suite(_ name: String) -> UserDefaults {
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func missingIsAdoptedExistingStays() {
        let old = suite("kiblegah.test.eski")
        let target = suite("kiblegah.test.yeni")
        old.set("ornek-kaynak", forKey: "tefsir.kaynak")
        old.set(true, forKey: "kuranNuzulSirasi")
        old.set(1.4, forKey: "mushafOlcek")
        old.set(3, forKey: "okuma.tekrar")
        target.set(false, forKey: "kuranNuzulSirasi")
        GroupDefaults.migrate(source: old, target: target)
        #expect(target.string(forKey: "tefsir.kaynak") == "ornek-kaynak")
        #expect(target.bool(forKey: "kuranNuzulSirasi") == false)
        #expect(target.double(forKey: "mushafOlcek") == 1.4)
        #expect(target.integer(forKey: "okuma.tekrar") == 3)
        #expect(target.object(forKey: "quizKontrolcu") == nil)
        #expect(old.string(forKey: "tefsir.kaynak") == "ornek-kaynak")
    }

    /// The keys are stored names: unchanged and without duplicates.
    @Test func keyIsStable() {
        #expect(GroupDefaults.migratedKeys.count == Set(GroupDefaults.migratedKeys).count)
        #expect(GroupDefaults.migratedKeys.contains("ezberDuzeni"))
        #expect(GroupDefaults.migratedKeys.contains("sohbetTanitimGoruldu"))
    }
}
