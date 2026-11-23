import Foundation
import Testing

@testable import DesignSystem

/// Golden test: raw values are stored in UserDefaults (`paylasRengi`) or come from the package data,
/// fonts and resource folders are named so in the bundle.
@Suite struct PersistedFormatTests {
    @Test func rawValues() {
        #expect(
            Set(SkyPhase.allCases.map(\.rawValue)) == ["imsak", "gunes", "ogle", "ikindi", "aksam", "yatsi"])
        #expect(Set(CardColor.allCases.map(\.rawValue)) == ["yesil", "kiremit", "krem"])
        #expect(
            Set(CategoryTone.allCases.map(\.rawValue)) == [
                "kil", "safran", "adacayi", "turkuaz", "deniz", "mor", "gul", "zeytin", "notr",
            ])
    }

    @Test func resources() {
        expectLiterals(["Fraunces", "Amiri", "YaziTipleri"], in: goldenSourceText())
    }
}
