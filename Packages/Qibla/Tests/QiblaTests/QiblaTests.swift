import Core
import Foundation
import Testing

@testable import Qibla

@Suite struct QiblaCalculationTests {
    @Test func knownPlaces() {
        #expect(abs(QiblaCalculation.angle(.sample) - 133.0) < 1)
        #expect(abs(QiblaCalculation.angle(latitude: 41.0082, longitude: 28.9784) - 151.6) < 1)
        #expect(abs(QiblaCalculation.angle(latitude: 40.7128, longitude: -74.0060) - 58.5) < 1)
        #expect(abs(QiblaCalculation.angle(latitude: -6.2088, longitude: 106.8456) - 295.2) < 1)
        let km = QiblaCalculation.distance(.sample) / 1000
        #expect(km > 4300 && km < 4450)
    }

    @Test func differenceAndDirection() {
        #expect(QiblaCalculation.difference(350, 10) == 20)
        #expect(QiblaCalculation.difference(10, 350) == -20)
        #expect(QiblaCalculation.inEighths(131) == 3)  // Southeast
        #expect(QiblaCalculation.inEighths(359) == 0)
    }

    @Test func sunAtNoon() {
        let time = ISO8601DateFormatter().date(from: "2026-10-18T11:05:00Z")!
        let s = SunPosition.calculate(time: time, latitude: 53.5511, longitude: 9.9937)
        #expect(abs(s.azimuth - 180) < 3)
        #expect(s.altitude > 25 && s.altitude < 35)
        // At noon the sun is in the south; the Qibla (~133°) is to its left.
        let k = QiblaCalculation.angle(latitude: 53.5511, longitude: 9.9937)
        let f = SunPosition.qiblaOffset(time: time, latitude: 53.5511, longitude: 9.9937, qibla: k)
        #expect(f.difference < -45 && f.difference > -57)
    }
}

@Suite struct DeviceAttitudeTests {
    /// Axes of a device that is rotated by `heading` and tilted backwards by `tilt`.
    func device(heading: Double, tilt: Double) -> DeviceAttitude {
        let k = heading * .pi / 180
        let p = tilt * .pi / 180
        let advanced = SIMD3(cos(k), -sin(k), 0)  // North/West coordinates
        let sag = SIMD3(cos(k + .pi / 2), -sin(k + .pi / 2), 0)
        let up = SIMD3<Double>(0, 0, 1)
        // flat: y = ileri, z = yukari; tilted by p: y turns up, z turns back.
        let y = advanced * cos(p) + up * sin(p)
        let z = up * cos(p) - advanced * sin(p)
        return DeviceAttitude(x: sag, y: y, z: z)
    }

    @Test func flatAndUprightSameDirection() throws {
        for heading in stride(from: 0.0, to: 360, by: 37) {
            for tilt in [0.0, 30, 60, 89, 100] {
                let y = try #require(device(heading: heading, tilt: tilt).direction)
                #expect(abs(QiblaCalculation.difference(y, heading)) < 0.01, "kurs \(heading) kipp \(tilt)")
            }
        }
        #expect(device(heading: 0, tilt: 0).pose == .flat)
        #expect(device(heading: 0, tilt: 90).pose == .upright)
    }

    @Test func matrixReadingIsDetectedFromGravity() throws {
        let c = device(heading: 131, tilt: 80)
        let rows = [[c.x.x, c.x.y, c.x.z], [c.y.x, c.y.y, c.y.z], [c.z.x, c.z.y, c.z.z]]
        let columns = [[c.x.x, c.y.x, c.z.x], [c.x.y, c.y.y, c.z.y], [c.x.z, c.y.z, c.z.z]]
        // Gravity in the device frame = down · axes.
        let g = SIMD3(-c.x.z, -c.y.z, -c.z.z)
        #expect(
            abs(
                QiblaCalculation.difference(
                    try #require(DeviceAttitude(matrix: rows, gravity: g).direction), 131)) < 0.01)
        #expect(
            abs(
                QiblaCalculation.difference(
                    try #require(DeviceAttitude(matrix: columns, gravity: g).direction), 131)) < 0.01)
    }
}

@Suite struct QiblaStateTests {
    @Test func states() {
        #expect(QiblaState.parse(qibla: nil, direction: 0, accuracy: .good, area: 50) == .noLocation)
        #expect(QiblaState.parse(qibla: 131, direction: 0, accuracy: .good, area: 140) == .interference)
        #expect(QiblaState.parse(qibla: 131, direction: 0, accuracy: .unavailable, area: 50) == .calibrating)
        #expect(QiblaState.parse(qibla: 131, direction: nil, accuracy: .good, area: 50) == .searching)
        #expect(
            QiblaState.parse(qibla: 131, direction: 129, accuracy: .good, area: 50)
                == .done(approximate: false))
        #expect(
            QiblaState.parse(qibla: 131, direction: 107, accuracy: .good, area: 50)
                == .turn(difference: 24, approximate: false)
        )
        // With ±25° uncertainty, 20° off is still "hit, approximately".
        #expect(
            QiblaState.parse(qibla: 131, direction: 111, accuracy: .low, area: 50) == .done(approximate: true)
        )
        // Hysteresis: 6° off is not a hit at .iyi (5°), but after a hit it still is one.
        #expect(
            QiblaState.parse(qibla: 131, direction: 125, accuracy: .good, area: 50)
                != .done(approximate: false))
        #expect(
            QiblaState.parse(qibla: 131, direction: 125, accuracy: .good, area: 50, wasHit: true)
                == .done(approximate: false))
    }

    @Test func spokenTenSteps() {
        #expect(QiblaState.turn(difference: 24, approximate: false).spokenStep == 20)
        #expect(QiblaState.turn(difference: -36, approximate: false).spokenStep == -40)
        #expect(QiblaState.done(approximate: false).spokenStep == nil)
    }

    @Test func continuousTurnTakesShortWay() {
        #expect(QiblaCalculation.continuous(nil, 10) == 10)
        #expect(QiblaCalculation.continuous(359, 1) == 361)
        #expect(QiblaCalculation.continuous(361, 358) == 358)
        #expect(QiblaCalculation.continuous(-2, 5) == 5)
    }
}
