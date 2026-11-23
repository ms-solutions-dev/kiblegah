import Foundation

/// A place for prayer times and Qibla. Lives in Kern because both domain packages need it and
/// must not know each other.
public struct Location: Codable, Sendable, Hashable {
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var timeZoneIdentifier: String
    /// The Diyanet İlçe, if known; without it there are only calculated times.
    public var diyanetDistrict: Int?

    public init(
        name: String, latitude: Double, longitude: Double, timeZoneIdentifier: String,
        diyanetDistrict: Int? = nil
    ) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
        self.diyanetDistrict = diyanetDistrict
    }

    /// Persisted keys stay Turkish (App Group settings `ayar.konum`).
    enum CodingKeys: String, CodingKey {
        case name = "ad"
        case latitude = "enlem"
        case longitude = "boylam"
        case timeZoneIdentifier = "saatDilimi"
        case diyanetDistrict = "diyanetIlce"
    }

    public var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }

    /// A sample place for tests and previews.
    public static let sample = Location(
        name: "Hamburg", latitude: 53.5511, longitude: 9.9937, timeZoneIdentifier: "Europe/Berlin",
        diyanetDistrict: 10001)
}
