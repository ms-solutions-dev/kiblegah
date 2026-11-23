import Core
import CoreLocation
import MapKit
import PrayerTimes

/// Place via GPS and place search. The place stays on the device; only the
/// İlçe request goes to the own prayer-time service, if one is entered.
///
/// With the İlçe bundle both also work without a network: the search finds Diyanet's places first,
/// and a GPS location gets the nearest İlçe within at most `districtMeters` distance.
@MainActor final class LocationService {
    enum LoadStatus: Equatable {
        case unknown
        case noPermission
        case ready
    }

    /// A search hit with the line below it (state and country, otherwise the time zone).
    struct PlaceResult: Hashable {
        let location: Location
        let explanation: String
    }

    let districts: (any DistrictDirectory)?
    /// How far the nearest İlçe may be from the location for its times to apply.
    static let districtMeters = 15_000.0

    init(districts: (any DistrictDirectory)? = nil) {
        self.districts = districts
    }

    var status: LoadStatus {
        switch CLLocationManager().authorizationStatus {
        case .denied, .restricted: .noPermission
        case .notDetermined: .unknown
        default: .ready
        }
    }

    /// The longest a fix may take; after that the best fix seen so far counts.
    nonisolated static let fixTimeout: Duration = .seconds(15)
    /// From this accuracy (meters) on there is no further waiting.
    nonisolated static let goodAccuracy = 1_000.0

    /// Asks for permission if needed and returns a usable location.
    ///
    /// Never waits without limit: indoors a fix under one kilometer often does not come, so after
    /// `fixTimeout` the best one so far (up to 5 km) counts. The session belongs to the call itself,
    /// so a second call (launch and button at the same time) does not take the permission away
    /// from the first.
    func currentLocation() async -> CLLocation? {
        #if os(iOS)
            let session = CLServiceSession(authorization: .whenInUse)
            defer { withExtendedLifetime(session) {} }
        #endif
        let best = BestLocation()
        return await withTaskGroup(of: CLLocation?.self) { group in
            group.addTask {
                do {
                    for try await updated in CLLocationUpdate.liveUpdates() {
                        if updated.authorizationDenied || updated.authorizationDeniedGlobally {
                            return nil
                        }
                        guard let k = updated.location, k.horizontalAccuracy >= 0,
                            k.horizontalAccuracy < 5000
                        else { continue }
                        await best.take(k)
                        if k.horizontalAccuracy <= LocationService.goodAccuracy { return k }
                    }
                } catch {}
                return await best.location
            }
            group.addTask {
                try? await Task.sleep(for: LocationService.fixTimeout)
                return await best.location
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// Place name, time zone and (via the service) Diyanet İlçe for a location.
    func location(_ place: CLLocation, server: ServerSource?) async -> Location {
        let item = try? await MKReverseGeocodingRequest(location: place)?.mapItems.first
        return await location(item, place: place, server: server)
    }

    /// Diyanet's places for the query, without network.
    func localSearch(_ text: String) -> [PlaceResult] {
        let cleaned = text.trimmingCharacters(in: .whitespaces)
        guard cleaned.count >= 2, let districts else { return [] }
        return districts.search(cleaned, limit: 12).map {
            PlaceResult(location: $0.location, explanation: $0.explanation)
        }
    }

    /// City search via Apple Maps. Empty on no hit or without network.
    func search(_ text: String, server: ServerSource?) async -> [PlaceResult] {
        let cleaned = text.trimmingCharacters(in: .whitespaces)
        guard cleaned.count >= 2, let request = MKGeocodingRequest(addressString: cleaned),
            let items = try? await request.mapItems
        else { return [] }
        // Resolve all hits at once; one after another the waiting times added up.
        let locations = await withTaskGroup(of: (Int, Location).self) { group in
            for (i, item) in items.prefix(8).enumerated() {
                // MKMapItem is not Sendable, but is only read here and runs on the MainActor.
                nonisolated(unsafe) let o = item
                group.addTask { @MainActor in (i, await self.location(o, place: o.location, server: server)) }
            }
            var all: [(Int, Location)] = []
            for await t in group { all.append(t) }
            return all.sorted { $0.0 < $1.0 }.map(\.1)
        }
        var result: [PlaceResult] = []
        for k in locations {
            if !result.contains(where: {
                $0.location.name == k.name && abs($0.location.latitude - k.latitude) < 0.05
            }) {
                result.append(PlaceResult(location: k, explanation: k.timeZoneIdentifier))
            }
        }
        return result
    }

    /// First the Diyanet places, then Apple Maps hits that are not already listed as İlçe.
    static func merge(local: [PlaceResult], online: [PlaceResult]) -> [PlaceResult] {
        local
            + online.filter { c in
                !local.contains { y in
                    (c.location.diyanetDistrict != nil
                        && c.location.diyanetDistrict == y.location.diyanetDistrict)
                        || (TurkishText.searchForm(c.location.name) == TurkishText.searchForm(y.location.name)
                            && c.location.distance(y.location) < 10_000)
                }
            }
    }

    private func location(_ item: MKMapItem?, place: CLLocation, server: ServerSource?) async -> Location {
        let representations = item?.addressRepresentations
        let name =
            representations?.cityName ?? item?.name
            ?? String(format: "%.2f, %.2f", place.coordinate.latitude, place.coordinate.longitude)
        var k = Location(
            name: name, latitude: place.coordinate.latitude, longitude: place.coordinate.longitude,
            timeZoneIdentifier: (item?.timeZone ?? .current).identifier)
        // The bundle on the device first: instant and without network. The server (possibly on a
        // local network) may be unreachable on the road and must not hold up the choice.
        k.diyanetDistrict =
            districts?.nearest(
                latitude: k.latitude, longitude: k.longitude, atMostMeters: Self.districtMeters)?
            .id
        if k.diyanetDistrict == nil, let server, let code = representations?.region?.identifier {
            // Diyanet lists countries under their Turkish name („ALMANYA“).
            let country = Locale(identifier: "tr").localizedString(forRegionCode: code) ?? code
            k.diyanetDistrict = await server.findDistrict(
                country: country, region: representations?.regionName ?? "", city: name)
        }
        return k
    }
}

extension Location {
    /// Distance in meters, for the location-change notice.
    func distance(_ other: Location) -> Double {
        CLLocation(latitude: latitude, longitude: longitude).distance(
            from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}

/// The most accurate fix of one location request, shared between the request and the timeout.
private actor BestLocation {
    private(set) var location: CLLocation?

    func take(_ k: CLLocation) {
        if location.map({ k.horizontalAccuracy < $0.horizontalAccuracy }) ?? true { location = k }
    }
}
