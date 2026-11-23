import Foundation

/// A place from Diyanet's place list with the coordinate that
/// Diyanet itself calculates with.
///
/// The coordinate is back-calculated from Diyanet's annual table.
/// With it the on-device calculator matches the official table; with the GPS coordinate the
/// summer values for Imsak/Isha deviate by several minutes. Lives in Kern because PrayerTimes (calculating)
/// and Inhalte (reading the pack) need it and must not know each other.
public struct DiyanetDistrict: Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    /// Federal state or İl; `nil` for countries without this level.
    public let region: String?
    /// Country in Diyanet's spelling ("Almanya").
    public let country: String
    /// ISO country code ("DE").
    public let countryCode: String
    public let latitude: Double
    public let longitude: Double
    public let timeZoneIdentifier: String
    public let ishaAngle: Double
    /// Largest deviation of the back-calculation against Diyanet's annual table, in minutes.
    public let deviation: Int

    public init(
        id: Int, name: String, region: String?, country: String, countryCode: String, latitude: Double,
        longitude: Double,
        timeZoneIdentifier: String, ishaAngle: Double, deviation: Int
    ) {
        self.id = id
        self.name = name
        self.region = region
        self.country = country
        self.countryCode = countryCode
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
        self.ishaAngle = ishaAngle
        self.deviation = deviation
    }

    /// The place for prayer times and Qibla, linked with the İlçe.
    public var location: Location {
        Location(
            name: name, latitude: latitude, longitude: longitude, timeZoneIdentifier: timeZoneIdentifier,
            diyanetDistrict: id)
    }

    /// "Bayern, Almanya" – for the line below the name.
    public var explanation: String {
        [region, country].compactMap { $0 }.filter { $0 != name }.joined(separator: ", ")
    }
}

/// Reads Diyanet's place list without network (pack `district`).
public protocol DistrictDirectory: Sendable {
    /// The İlçe with this Diyanet number, or `nil`.
    func district(_ id: Int) -> DiyanetDistrict?
    /// Places whose name (or federal state/country) begins with the words of the query; name matches first.
    func search(_ text: String, limit: Int) -> [DiyanetDistrict]
    /// The nearest İlçe at most `atMostMeters` away, or `nil`.
    func nearest(latitude: Double, longitude: Double, atMostMeters: Double) -> DiyanetDistrict?
}
