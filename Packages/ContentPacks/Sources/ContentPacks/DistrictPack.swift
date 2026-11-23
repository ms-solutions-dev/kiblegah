import Core
import Foundation

public final class DistrictPack: DistrictDirectory {
    public let manifest: PackManifest
    private let db: Database

    public init(folder: URL) throws(ContentPackError) {
        let p = try ContentPack(folder: folder)
        guard p.manifest.kind == "ilce" else { throw .manifestCorrupt(folder.lastPathComponent) }
        manifest = p.manifest
        db = p.db
    }

    /// The package `district` in the first of the folders that contains it; `nil` if none has it.
    public static func find(folders: [URL]) -> DistrictPack? {
        for k in folders {
            if let p = try? DistrictPack(folder: k.appending(path: "ilce")) { return p }
        }
        return nil
    }

    private static let columns = """
        SELECT i.id, i.ad, e.ad, u.ad, u.kod, i.enlem, i.boylam, i.saat_dilimi, i.yatsi_acisi, i.sapma
        FROM ilce i JOIN ulke u ON u.id = i.ulke LEFT JOIN eyalet e ON e.id = i.eyalet
        """

    private static func load(_ r: Row) -> DiyanetDistrict {
        DiyanetDistrict(
            id: r.integer(0), name: r.text(1), region: r.optionalText(2), country: r.text(3),
            countryCode: r.text(4),
            latitude: r.double(5), longitude: r.double(6), timeZoneIdentifier: r.text(7),
            ishaAngle: r.double(8),
            deviation: r.integer(9))
    }

    public func district(_ id: Int) -> DiyanetDistrict? {
        db.first(Self.columns + " WHERE i.id = ?", [.integer(id)], row: Self.load)
    }

    /// Search form as in the build tool: `searchForm`, plus ß → ss and punctuation as separators.
    static func fold(_ text: String) -> [String] {
        let s = TurkishText.searchForm(text.replacingOccurrences(of: "ß", with: "ss"))
        return s.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    public func search(_ text: String, limit: Int = 20) -> [DiyanetDistrict] {
        let words = Self.fold(text)
        guard let first = words.first, words.joined().count >= 2 else { return [] }
        let condition = words.map { _ in "(' ' || i.katli) LIKE ?" }.joined(separator: " AND ")
        let values = words.map { Value.text("% \($0)%") }
        let candidates = db.query(Self.columns + " WHERE \(condition) LIMIT 400", values, row: Self.load)
        // Rank: name equals the query, name starts with it, word in the name, otherwise (state/country).
        let all = words.joined(separator: " ")
        func rank(_ i: DiyanetDistrict) -> Int {
            let name = Self.fold(i.name).joined(separator: " ")
            if name == all { return 0 }
            if name.hasPrefix(all) { return 1 }
            if (" " + name).contains(" " + first) { return 2 }
            return 3
        }
        return
            candidates
            .map { (rank($0), $0) }
            .sorted { a, b in
                if a.0 != b.0 { return a.0 < b.0 }
                if a.1.name.count != b.1.name.count { return a.1.name.count < b.1.name.count }
                return a.1.id < b.1.id
            }
            .prefix(limit).map(\.1)
    }

    public func nearest(
        latitude: Double, longitude: Double, atMostMeters maxMeters: Double
    ) -> DiyanetDistrict? {
        let dLatitude = maxMeters / 111_000
        let dLongitude = dLatitude / max(cos(latitude * .pi / 180), 0.01)
        let candidates = db.query(
            Self.columns + " WHERE i.enlem BETWEEN ? AND ? AND i.boylam BETWEEN ? AND ?",
            [
                .double(latitude - dLatitude), .double(latitude + dLatitude), .double(longitude - dLongitude),
                .double(longitude + dLongitude),
            ],
            row: Self.load)
        return
            candidates
            .map { (Self.distance(latitude, longitude, $0.latitude, $0.longitude), $0) }
            .filter { $0.0 <= maxMeters }
            .min { $0.0 < $1.0 }?.1
    }

    /// Großkreisabstand in Metern (Haversine).
    static func distance(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = Double.pi / 180
        let a =
            pow(sin((lat2 - lat1) * r / 2), 2) + cos(lat1 * r) * cos(lat2 * r)
            * pow(sin((lon2 - lon1) * r / 2), 2)
        return 2 * 6_371_000 * asin(min(1, sqrt(a)))
    }
}
