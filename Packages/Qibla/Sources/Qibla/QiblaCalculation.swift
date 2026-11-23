import Core
import Foundation

/// Direction and distance to the Kaaba along the great circle.
public enum QiblaCalculation {
    /// The Kaaba (center), WGS84.
    public static let kaabaLatitude = 21.422_487
    public static let kaabaLongitude = 39.826_206
    static let earthRadius = 6_371_008.8

    /// Initial bearing of the great circle from the location to the Kaaba, degrees clockwise from geographic north.
    public static func angle(latitude: Double, longitude: Double) -> Double {
        let f1 = latitude * .pi / 180
        let f2 = kaabaLatitude * .pi / 180
        let dl = (kaabaLongitude - longitude) * .pi / 180
        let y = sin(dl) * cos(f2)
        let x = cos(f1) * sin(f2) - sin(f1) * cos(f2) * cos(dl)
        return normalize(atan2(y, x) * 180 / .pi)
    }

    /// Distance in meters (haversine).
    public static func distance(latitude: Double, longitude: Double) -> Double {
        let f1 = latitude * .pi / 180
        let f2 = kaabaLatitude * .pi / 180
        let df = f2 - f1
        let dl = (kaabaLongitude - longitude) * .pi / 180
        let a = sin(df / 2) * sin(df / 2) + cos(f1) * cos(f2) * sin(dl / 2) * sin(dl / 2)
        return 2 * earthRadius * atan2(sqrt(a), sqrt(1 - a))
    }

    public static func angle(_ k: Location) -> Double { angle(latitude: k.latitude, longitude: k.longitude) }
    public static func distance(_ k: Location) -> Double {
        distance(latitude: k.latitude, longitude: k.longitude)
    }

    /// 0…360.
    public static func normalize(_ d: Double) -> Double {
        let r = d.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }

    /// Shortest difference from `a` to `b`, −180…180 (positive = turn to the right).
    public static func difference(_ a: Double, _ b: Double) -> Double {
        var d = normalize(b - a)
        if d > 180 { d -= 360 }
        return d
    }

    /// `yeni` shifted by full turns so that it lies closest to `previous`.
    ///
    /// For rotation animations: 359° → 1° becomes 359° → 361° instead of a whole turn backwards
    ///.
    public static func continuous(_ previous: Double?, _ yeni: Double) -> Double {
        guard let previous else { return yeni }
        return previous + difference(previous, yeni)
    }

    /// Compass direction in eighths: 0 = north, 1 = northeast … 7 = northwest.
    public static func inEighths(_ angle: Double) -> Int { Int((normalize(angle) + 22.5) / 45) % 8 }
}

/// Sun position for „güneşe göre“ – the cross-check without a compass.
public enum SunPosition {
    /// From this altitude (degrees) the sun is usable as a direction aid; below it, buildings
    /// and haze usually obscure it. Applies equally to app, watch and widget.
    public static let visibleHeight = 2.0

    /// Azimuth (degrees from north, clockwise) and altitude (degrees) of the sun.
    public static func calculate(
        time: Date, latitude: Double, longitude: Double
    ) -> (azimuth: Double, altitude: Double) {
        let jd = time.timeIntervalSince1970 / 86400 + 2_440_587.5
        let d = jd - 2_451_545.0
        let g = (357.529 + 0.985_600_28 * d) * .pi / 180
        let q = 280.459 + 0.985_647_36 * d
        let l = (q + 1.915 * sin(g) + 0.020 * sin(2 * g)) * .pi / 180
        let e = (23.439 - 0.000_000_36 * d) * .pi / 180
        let ra = atan2(cos(e) * sin(l), cos(l))
        let declination = asin(sin(e) * sin(l))
        // Sidereal time at Greenwich, then hour angle at the location.
        let gmst = (280.460_618_37 + 360.985_647_366_29 * d).truncatingRemainder(dividingBy: 360) * .pi / 180
        let h = gmst + longitude * .pi / 180 - ra
        let f = latitude * .pi / 180
        let altitude = asin(sin(f) * sin(declination) + cos(f) * cos(declination) * cos(h))
        let azimuth = atan2(-sin(h), tan(declination) * cos(f) - sin(f) * cos(h))
        return (QiblaCalculation.normalize(azimuth * 180 / .pi), altitude * 180 / .pi)
    }

    /// Qibla relative to the sun (−180…180, positive = to the right of it) and sun altitude – for
    /// „Güneşe göre Kıble“: face the sun, then turn by this angle.
    public static func qiblaOffset(
        time: Date, latitude: Double, longitude: Double, qibla: Double
    ) -> (difference: Double, altitude: Double) {
        let g = calculate(time: time, latitude: latitude, longitude: longitude)
        return (QiblaCalculation.difference(g.azimuth, qibla), g.altitude)
    }
}
