import Core
import Testing

@testable import Features

@MainActor struct QiblaStartTests {
    @Test func selectionFromSettings() {
        #expect(QiblaScreen.startView(argument: nil, selection: .compass, end: "harita") == .compass)
        #expect(QiblaScreen.startView(argument: nil, selection: .map, end: "kamera") == .map)
    }

    /// "Last choice" also takes the camera; without a remembered view the compass starts.
    @Test func lastChoice() {
        #expect(QiblaScreen.startView(argument: nil, selection: .lastChoice, end: "kamera") == .camera)
        #expect(QiblaScreen.startView(argument: nil, selection: .lastChoice, end: "") == .compass)
        #expect(QiblaScreen.startView(argument: nil, selection: .lastChoice, end: "unbekannt") == .compass)
    }

    /// The launch argument for screenshots takes precedence over the setting.
    @Test func argument() {
        #expect(QiblaScreen.startView(argument: "harita", selection: .compass, end: "") == .map)
        #expect(QiblaScreen.startView(argument: "quatsch", selection: .map, end: "") == .map)
    }
}
