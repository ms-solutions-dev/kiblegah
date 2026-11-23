import Foundation

/// Compass quality from CoreMotion, converted to degrees.
public enum Accuracy: Sendable, Equatable {
    case unavailable
    case low
    case intermediate
    case good

    /// Estimated uncertainty in degrees.
    public var degrees: Double {
        switch self {
        case .unavailable: 45
        case .low: 25
        case .intermediate: 10
        case .good: 5
        }
    }
}

/// What the Qibla screen shows.
public enum QiblaState: Sendable, Equatable {
    case noLocation
    case searching
    case calibrating
    /// Magnetic interference: show no direction, so that nobody prays in the wrong direction.
    case interference
    /// Turn: `difference` positive = to the right.
    case turn(difference: Double, approximate: Bool)
    case done(approximate: Bool)

    /// Earth's magnetic field is between roughly 25 and 65 µT; far outside that is interference.
    public static let fieldRange = 15.0...85.0

    /// Hysteresis: once hit, it stays a hit until this many degrees outside the window.
    public static let backMargin = 2.0

    /// - Parameters:
    ///   - qibla: Target direction (degrees), `nil` without a location.
    ///   - direction: Actual direction of the device, `nil` as long as no attitude is available.
    ///   - area: Strength of the calibrated magnetic field in µT, `nil` if unknown.
    ///   - wasHit: Whether the last result was a hit. Then the window is wider by ``backMargin``,
    ///     so that title and haptics do not flicker at the edge.
    public static func parse(
        qibla: Double?, direction: Double?, accuracy: Accuracy, area: Double?, wasHit: Bool = false
    ) -> QiblaState {
        guard let qibla else { return .noLocation }
        if let area, !fieldRange.contains(area) { return .interference }
        if accuracy == .unavailable { return .calibrating }
        guard let direction else { return .searching }
        let f = QiblaCalculation.difference(direction, qibla)
        // Hit window at least 3°, otherwise as wide as the uncertainty.
        let window = max(3, accuracy.degrees) + (wasHit ? backMargin : 0)
        let approximate = accuracy.degrees > 10
        return abs(f) <= window
            ? .done(approximate: approximate) : .turn(difference: f, approximate: approximate)
    }

    /// Report to VoiceOver only in 10° steps.
    public var spokenStep: Int? {
        if case .turn(let f, _) = self { return Int((f / 10).rounded()) * 10 }
        return nil
    }
}
