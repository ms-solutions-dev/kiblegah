import Foundation
import Testing

@testable import Core

/// Relay address from the Info value: a host without a scheme means https, empty means off.
@Suite struct RelayTests {
    @Test func parse() {
        #expect(Relay.parse("vermittler.example.dev")?.absoluteString == "https://vermittler.example.dev")
        #expect(Relay.parse(" http://localhost:8787 ")?.absoluteString == "http://localhost:8787")
        #expect(Relay.parse(nil) == nil)
        #expect(Relay.parse("") == nil)
        #expect(Relay.parse("$(VERMITTLER_ADRESI)") == nil)
    }

    @Test func qfBase() {
        let old = Relay.address
        defer { Relay.address = old }
        Relay.address = nil
        #expect(Relay.qfBase.isEmpty)
        Relay.address = Relay.parse("vermittler.example.dev")
        #expect(Relay.qfBase == "https://vermittler.example.dev/qf")
    }
}
