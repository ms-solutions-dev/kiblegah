import Core
import Foundation

/// Provides a table for a location.
public protocol PrayerTimeSource: Sendable {
    func table(location: Location, start: Day, dayCount: Int) async throws -> PrayerTimeTable
}

public enum PrayerTimeError: Error, Equatable, Sendable {
    case noDistrict
    case server(Int)
    case invalidResponse
}

/// Calculates on the device - always available, labeled „hesaplanan“.
///
/// If the location's Diyanet İlçe is in the İlçe package, it calculates with Diyanet's own
/// coordinate, time zone and Yatsı angle instead of the GPS point: only this way
/// does the summer (İmsak/Yatsı via Takdir) match the official table to the minute.
public struct OnDeviceSource: PrayerTimeSource {
    let calculator = PrayerTimeCalculator()
    let districts: (any DistrictDirectory)?
    let time: @Sendable () -> Date

    /// - Parameter ilceler: Diyanet's location list; `nil` always calculates with the location
    ///   (setting „Konumuma göre“ or package missing).
    public init(districts: (any DistrictDirectory)? = nil, time: @escaping @Sendable () -> Date = Date.init) {
        self.districts = districts
        self.time = time
    }

    /// The point used for calculating, and the Yatsı angle (only from the package).
    func calculationPoint(_ location: Location) -> (Location, Double?) {
        guard let id = location.diyanetDistrict, let i = districts?.district(id) else {
            return (location, nil)
        }
        var k = location
        k.latitude = i.latitude
        k.longitude = i.longitude
        k.timeZoneIdentifier = i.timeZoneIdentifier
        return (k, i.ishaAngle)
    }

    public func table(location: Location, start: Day, dayCount: Int) async throws -> PrayerTimeTable {
        let (point, angle) = calculationPoint(location)
        let days = (0..<dayCount).map { i -> DailyPrayerTimes in
            let g = start.added(i)
            let v = calculator.day(g, location: point, ishaAngle: angle)
            return DailyPrayerTimes(
                day: g, times: v.times, hijri: HijriDate.calculate(g), source: .calculated)
        }
        return PrayerTimeTable(location: location, fetchedAt: time(), days: days)
    }
}

/// Diyanet via our own server. Credentials are only kept there.
public struct ServerSource: PrayerTimeSource {
    public let address: URL
    let session: URLSession
    let time: @Sendable () -> Date

    public init(address: URL, session: URLSession = .shared, time: @escaping @Sendable () -> Date = Date.init)
    {
        self.address = address
        self.session = session
        self.time = time
    }

    struct Response: Decodable {
        enum CodingKeys: String, CodingKey {
            case days = "gunler"
        }

        struct Row: Decodable {
            enum CodingKeys: String, CodingKey {
                case date = "tarih"
                case imsak
                case sunrise = "gunes"
                case dhuhr = "ogle"
                case asr = "ikindi"
                case maghrib = "aksam"
                case isha = "yatsi"
                case hijri = "hicri"
            }

            let date: String
            let imsak, sunrise, dhuhr, asr, maghrib, isha: String
            let hijri: String?
        }
        let days: [Row]
    }

    public func table(location: Location, start: Day, dayCount: Int) async throws -> PrayerTimeTable {
        guard let district = location.diyanetDistrict else { throw PrayerTimeError.noDistrict }
        var components = URLComponents(
            url: address.appending(path: "v1/vakit"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "ilce", value: String(district)),
            URLQueryItem(name: "bas", value: start.description),
            URLQueryItem(name: "gun", value: String(min(dayCount, 40))),
        ]
        var request = URLRequest(url: components.url!)
        // After that the device calculates; waiting longer only holds up the change of place.
        request.timeoutInterval = 8
        let (veri, answer) = try await session.data(for: request)
        if let h = answer as? HTTPURLResponse, h.statusCode != 200 {
            throw PrayerTimeError.server(h.statusCode)
        }
        return try Self.parse(veri, location: location, fetchedAt: time())
    }

    /// Converts the server response into a table; times are in the location's time zone.
    static func parse(_ veri: Data, location: Location, fetchedAt: Date) throws -> PrayerTimeTable {
        guard let response = try? JSONDecoder().decode(Response.self, from: veri) else {
            throw PrayerTimeError.invalidResponse
        }
        let tz = location.timeZone
        let days = try response.days.map { s -> DailyPrayerTimes in
            guard let g = Day(text: s.date) else { throw PrayerTimeError.invalidResponse }
            let night = g.start(tz)
            var times: [Prayer: Date] = [:]
            for (n, m) in [
                (Prayer.imsak, s.imsak), (.sunrise, s.sunrise), (.dhuhr, s.dhuhr), (.asr, s.asr),
                (.maghrib, s.maghrib), (.isha, s.isha),
            ] {
                guard let time = Self.time(m, night: night, tz: tz) else {
                    throw PrayerTimeError.invalidResponse
                }
                times[n] = time
            }
            return DailyPrayerTimes(
                day: g, times: times, hijri: s.hijri.flatMap(HijriDate.init(diyanet:)), source: .diyanet)
        }
        guard !days.isEmpty else { throw PrayerTimeError.invalidResponse }
        return PrayerTimeTable(location: location, fetchedAt: fetchedAt, days: days)
    }

    /// „05:54“ on day `gece` - via the calendar, so that daylight-saving-change days are correct.
    static func time(_ text: String, night: Date, tz: TimeZone) -> Date? {
        let p = text.split(separator: ":").compactMap { Int($0) }
        guard p.count >= 2 else { return nil }
        var t = Calendar(identifier: .gregorian)
        t.timeZone = tz
        return t.date(bySettingHour: p[0], minute: p[1], second: 0, of: night)
    }
}

/// Server first, the device on any error. The table says where it comes from.
public struct HybridSource: PrayerTimeSource {
    let server: (any PrayerTimeSource)?
    let device: any PrayerTimeSource

    public init(server: (any PrayerTimeSource)?, device: any PrayerTimeSource = OnDeviceSource()) {
        self.server = server
        self.device = device
    }

    public func table(location: Location, start: Day, dayCount: Int) async throws -> PrayerTimeTable {
        if let server, location.diyanetDistrict != nil,
            let t = try? await server.table(location: location, start: start, dayCount: dayCount)
        {
            return t
        }
        return try await device.table(location: location, start: start, dayCount: dayCount)
    }
}

extension ServerSource {
    struct LookupResponse: Decodable {
        enum CodingKeys: String, CodingKey {
            case district = "ilce"
        }

        struct Place: Decodable { let id: Int }
        let district: Place?
    }

    /// The Diyanet İlçe for a location (country in Turkish, state, city), or `nil`.
    public func findDistrict(country: String, region: String, city: String) async -> Int? {
        var b = URLComponents(url: address.appending(path: "v1/bul"), resolvingAgainstBaseURL: false)!
        b.queryItems = [
            URLQueryItem(name: "ulke", value: country), URLQueryItem(name: "eyalet", value: region),
            URLQueryItem(name: "sehir", value: city),
        ]
        // Keep it short: the service may sit on a local network that is unreachable on the road.
        var request = URLRequest(url: b.url!)
        request.timeoutInterval = 4
        guard let (veri, answer) = try? await session.data(for: request),
            (answer as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return (try? JSONDecoder().decode(LookupResponse.self, from: veri))?.district?.id
    }
}
