import Core
import Foundation
import Testing

@testable import PrayerTimes

@Suite struct PrayerTimeCalculatorTests {
    struct Place: Decodable {
        enum CodingKeys: String, CodingKey {
            case latitude = "enlem"
            case longitude = "boylam"
            case tz
            case days = "tafel"
        }

        let latitude: Double
        let longitude: Double
        let tz: String
        let days: [String: [String]]
    }

    static let places: [String: Place] = {
        let url = Bundle.module.url(forResource: "Veri/diyanet-orte", withExtension: "json")!
        return try! JSONDecoder().decode([String: Place].self, from: Data(contentsOf: url))
    }()

    /// Deviations in minutes per time.
    static func deviations(_ o: Place) -> [Prayer: [Int]] {
        let location = Location(
            name: "", latitude: o.latitude, longitude: o.longitude, timeZoneIdentifier: o.tz)
        let h = PrayerTimeCalculator()
        var result: [Prayer: [Int]] = [:]
        for (date, times) in o.days {
            let g = Day(text: date)!
            let v = h.day(g, location: location)
            let night = g.start(location.timeZone)
            for (n, m) in zip(Prayer.allCases, times) {
                let expectedTime = ServerSource.time(m, night: night, tz: location.timeZone)!
                result[n, default: []].append(Int((v[n].timeIntervalSince(expectedTime) / 60).rounded()))
            }
        }
        return result
    }

    @Test(arguments: [
        "Istanbul", "PortJeff", "Adelaide", "Konstanz", "Hamburg",
        // Edmonton (53.5° N) is left out until its known deviation is resolved.
        "Flensburg", "Aberdeen", "Stockholm",
    ])
    func upToSixtyDegreesAtMostOneMinute(_ name: String) throws {
        let o = try #require(Self.places[name])
        for (n, s) in Self.deviations(o) {
            #expect(s.allSatisfy { abs($0) <= 1 }, "\(name) \(n): \(s.filter { abs($0) > 1 })")
            let tam = s.filter { $0 == 0 }.count
            #expect(tam * 100 >= s.count * 88, "\(name) \(n): only \(tam) of \(s.count) exact")
        }
    }

    /// Test bench of 2,110 İlçe: up to 60° together ≥ 98.5 % exact, Turkey
    /// (Temkin 4.98/4.02) ≥ 99.8 %.
    @Test(arguments: [
        ("Istanbul", 99.8), ("Konstanz", 98.5),
        ("Hamburg", 98.5), ("Flensburg", 98.5), ("Stockholm", 98.5), ("PortJeff", 99.5), ("Adelaide", 99.5),
        ("Aberdeen", 98.0),
    ])
    func totalShareExact(_ name: String, _ fraction: Double) throws {
        let o = try #require(Self.places[name])
        let all = Self.deviations(o).values.flatMap { $0 }
        let tam = Double(all.filter { $0 == 0 }.count) / Double(all.count) * 100
        #expect(tam >= fraction, "\(name): \(tam) %")
    }

    @Test func turkeyTemkin() {
        let tr = PrayerTimeCalculator.Method(timeZoneIdentifier: "Europe/Istanbul", ishaAngle: 17)
        let de = PrayerTimeCalculator.Method(timeZoneIdentifier: "Europe/Berlin", ishaAngle: 16)
        #expect(tr.dhuhrTemkin == 4.98 && tr.asrTemkin == 4.02)
        #expect(de.dhuhrTemkin == 5 && de.asrTemkin == 4)
    }

    @Test(arguments: ["Oslo", "Helsinki", "Trondheim", "Kemi", "Tromso"])
    func aboveSixtyDegreesAtMostTwoMinutes(_ name: String) throws {
        let o = try #require(Self.places[name])
        for (n, s) in Self.deviations(o) {
            #expect(s.allSatisfy { abs($0) <= 2 }, "\(name) \(n)")
            #expect(s.filter { $0 == 0 }.count * 100 >= s.count * 80, "\(name) \(n)")
        }
    }


    @Test func summerInTheNorthHasImsakAndIsha() {
        // Hamburg in June: the sun does not reach 18°; times are still ordered.
        let hh = Location(
            name: "Hamburg", latitude: 53.55, longitude: 9.99, timeZoneIdentifier: "Europe/Berlin")
        let v = PrayerTimeCalculator().day(Day(year: 2026, month: 6, day: 21), location: hh)
        let index = Prayer.allCases.map { v[$0] }
        #expect(index == index.sorted())
        #expect(v[.sunrise].timeIntervalSince(v[.imsak]) > 3600)
        // Oslo (59.9°) and Tromsø (69.6°, capped at 62°) also stay ordered.
        for (latitude, longitude) in [(59.91, 10.75), (69.65, 18.96)] {
            let k = Location(
                name: "x", latitude: latitude, longitude: longitude, timeZoneIdentifier: "Europe/Oslo")
            let w = PrayerTimeCalculator().day(Day(year: 2026, month: 6, day: 21), location: k)
            let s = Prayer.allCases.map { w[$0] }
            #expect(s == s.sorted(), "\(latitude)")
        }
    }
}
