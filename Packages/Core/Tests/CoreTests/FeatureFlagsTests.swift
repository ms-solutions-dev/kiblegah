import Testing

@testable import Core

/// Switches for sources requiring approval: from the Info value, default everything off.
@Suite struct FeatureFlagsTests {
    @Test func parse() {
        #expect(FeatureFlags.parse("diyanet,ekKariler") == .all)
        #expect(FeatureFlags.parse(" diyanet ") == .diyanet)
        #expect(FeatureFlags.parse(nil) == .free)
        #expect(FeatureFlags.parse("") == .free)
        #expect(FeatureFlags.parse("$(KIBLEGAH_OZELLIKLER)") == .free)
        #expect(FeatureFlags.parse("quranFoundation,bilinmez") == .free)
    }

    @Test func defaultIsAllOff() {
        #expect(FeatureFlags.free.isEmpty)
        #expect(Set(FeatureFlags.names.values.map(\.rawValue)).count == FeatureFlags.names.count)
    }
}
