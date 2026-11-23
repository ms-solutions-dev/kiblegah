import Core
import Foundation
import Synchronization

/// Prayer times on the device according to the Diyanet method.
///
/// Rebuilt from the official annual tables of 17 places (38°-70° N, Adelaide, Port
/// Jefferson) and the published decisions (DİYK 2009, Congress 2021, Temkin table).
/// Checked against the 2027 annual tables of all 2,110 İlçe in Germany and Turkey: with
/// Diyanet's location coordinate every time is within ±1 minute, exactly 99.1 % (DE) or 99.9 % (TR); above 60°
/// on a few days ±2.
///
/// - Solar position (Meeus, in terrestrial time) once per day at 0 h UT, not at the event time.
/// - Temkin: Güneş −7, Öğle +5, İkindi (Shafi'i shadow) +4, Akşam +7 minutes; İmsak/Yatsı 0
///   (Turkey: Öğle 4.98, İkindi 4.02 - see `Method`).
/// - İmsak 18°. Yatsı 17° in Turkey, 16° in Europe and North America.
/// - Güneş/Akşam at most 9:30 h, at least 2:30 h from Öğle; above 60° not beyond
///   June 21.
/// - Takdir (high latitudes in summer): Yatsı = Akşam + r·night with the ratio r of the
///   şer'î night on the last day with 18° Fecr, İmsak = Güneş − (18/Yatsı angle)·(Yatsı − Akşam);
///   transitions as a 20-minute line to the fractional anchor day (the moment at which the
///   18° twilight disappears or returns).
public struct PrayerTimeCalculator: Sendable {
    public static let imsakAngle = 18.0

    public init() {}

    /// Yatsı angle per region: 17° Turkey and large parts of Asia/Africa/Australia, otherwise 16°.
    public static func ishaAngle(_ k: Location) -> Double {
        let tz = k.timeZoneIdentifier
        if tz == "Europe/Istanbul" || tz.hasPrefix("Asia/") || tz.hasPrefix("Africa/")
            || tz.hasPrefix("Australia/")
        {
            return 17
        }
        return 16
    }

    /// The location-dependent values of the method.
    ///
    /// The Turkey tables are 1.2 s earlier for Öğle and 1.2 s later for İkindi than with
    /// Temkin 5/4 - at all 869 İlçe alike, independent of longitude and latitude, in the 2026
    /// and 2027 tables. The cause is unknown; Germany does not show the offset.
    /// With 4.98/4.02 min Turkey hits 99.97 % instead of 99.3 %.
    struct Method: Hashable, Sendable {
        let ishaAngle: Double
        let dhuhrTemkin: Double
        let asrTemkin: Double

        init(timeZoneIdentifier: String, ishaAngle: Double) {
            self.ishaAngle = ishaAngle
            let turkey = timeZoneIdentifier == "Europe/Istanbul"
            dhuhrTemkin = turkey ? 4.98 : 5
            asrTemkin = turkey ? 4.02 : 4
        }
    }

    /// The times of a day, rounded to whole minutes.
    /// - Parameter yatsiAcisi: from the İlçe pack; without it the rule by time zone applies.
    public func day(_ g: Day, location: Location, ishaAngle: Double? = nil) -> DailyPrayerTimes {
        let year = DiyanetYear.al(
            latitude: location.latitude, longitude: location.longitude, year: g.year,
            method: Method(
                timeZoneIdentifier: location.timeZoneIdentifier,
                ishaAngle: ishaAngle ?? Self.ishaAngle(location)))
        let night = g.start(.gmt)
        var times: [Prayer: Date] = [:]
        for (n, dk) in year.day(g) {
            times[n] = night.addingTimeInterval(floor(dk + 0.5) * 60)
        }
        return DailyPrayerTimes(day: g, times: times, hijri: nil, source: .calculated)
    }

    static func julianDay(_ g: Day) -> Double {
        var y = g.year
        var m = g.month
        if m <= 2 {
            y -= 1
            m += 12
        }
        let a = y / 100
        let b = 2 - a + a / 4
        let years: Double = floor(365.25 * Double(y + 4716))
        let months: Double = floor(30.6001 * Double(m + 1))
        return years + months + Double(g.day + b) - 1524.5
    }

    /// ΔT = TT − UT for 2026/27 (IERS: 69.2 s), in days.
    static let deltaT = 69.2 / 86_400

    /// Declination (radians) and equation of time (hours) after Meeus (Astronomical Algorithms,
    /// ch. 25/28: apparent longitude with nutation and aberration), computed in terrestrial time.
    ///
    /// Against 2,110 Diyanet annual tables more accurate than the USNO short formula: Güneş, Öğle, İkindi
    /// and Akşam then land on the minute 99.8–99.9 % of the time (USNO 98.8–99.7 %).
    static func sunrise(_ jd: Double) -> (Double, Double) {
        let t = (jd + deltaT - 2_451_545.0) / 36_525
        let r = Double.pi / 180
        let l0 = 280.46646 + 36_000.76983 * t + 0.000_303_2 * t * t
        let m = (357.52911 + 35_999.05029 * t - 0.000_153_7 * t * t) * r
        let c =
            (1.914_602 - 0.004_817 * t - 0.000_014 * t * t) * sin(m) + (0.019_993 - 0.000_101 * t)
            * sin(2 * m)
            + 0.000_289 * sin(3 * m)
        let om = (125.04 - 1_934.136 * t) * r
        let lam = (l0 + c - 0.005_69 - 0.004_78 * sin(om)) * r
        let eps = (23 + (26 + (21.448 - 46.8150 * t) / 60) / 60 + 0.002_56 * cos(om)) * r
        let ra = atan2(cos(eps) * sin(lam), cos(lam)) / r
        let declination = asin(sin(eps) * sin(lam))
        let dpsi = -17.20 / 3600 * sin(om)
        var e = l0 - 0.005_718_3 - ra + dpsi * cos(eps)
        e = (e + 180).truncatingRemainder(dividingBy: 360)
        if e < 0 { e += 360 }
        return (declination, (e - 180) / 15)
    }

    /// Hour angle in minutes at which the sun has the altitude `altitude` (degrees).
    static func hourAngle(latitude: Double, altitude: Double, declination: Double) -> Double? {
        let f = latitude * .pi / 180
        let v = (sin(altitude * .pi / 180) - sin(f) * sin(declination)) / (cos(f) * cos(declination))
        guard v >= -1, v <= 1 else { return nil }
        return acos(v) * 180 / .pi / 15 * 60
    }
}

/// One year of Diyanet times for a place, in minutes UTC from 0 h UT of the respective day.
/// The Takdir rule needs the year's anchor days, so the year is computed in one piece
/// and cached.
struct DiyanetYear: Sendable {
    private let days: [Day: [Prayer: Double]]

    func day(_ g: Day) -> [Prayer: Double] { days[g] ?? [:] }

    private struct Key: Hashable {
        let latitude: Double
        let longitude: Double
        let year: Int
        let method: PrayerTimeCalculator.Method
    }

    private static let cache = Mutex<[Key: DiyanetYear]>([:])

    static func al(
        latitude: Double, longitude: Double, year: Int, method: PrayerTimeCalculator.Method
    ) -> DiyanetYear {
        let k = Key(latitude: latitude, longitude: longitude, year: year, method: method)
        if let v = cache.withLock({ $0[k] }) { return v }
        let v = DiyanetYear(latitude: latitude, longitude: longitude, year: year, method: method)
        cache.withLock { d in
            if d.count > 16 { d.removeAll() }
            d[k] = v
        }
        return v
    }

    private struct Raw {
        var sunrise: Double
        var maghrib: Double
        let dhuhr: Double
        let asr: Double
        let isha: Double?  // 18° İmsak
        let fajr18: Double?  // 18°-İmsak
        let polar: Bool
        let declination: Double
        var night: Double { 1440 - (maghrib - sunrise) }
        var r3: Double? { fajr18.map { (1440 - (maghrib - $0)) / 3 / night } }
    }

    init(latitude la: Double, longitude lo: Double, year: Int, method: PrayerTimeCalculator.Method) {
        let k = PrayerTimeCalculator.imsakAngle / method.ishaAngle
        var days: [Day] = []
        var g = Day(year: year, month: 1, day: 1)
        while g.year == year {
            days.append(g)
            g = g.added(1)
        }
        var q = days.map { Self.ham($0, la: la, lo: lo, method: method) }
        let sol = days.firstIndex(of: Day(year: year, month: 6, day: 21))!
        // Above 60° (and with midnight sun): not beyond June 21.
        let qs = q[sol]
        for i in q.indices where q[i].polar || abs(la) > 60 {
            q[i].sunrise = max(q[i].sunrise, qs.sunrise)
            q[i].maghrib = min(q[i].maghrib, qs.maghrib)
        }
        let angle = { (i: Int) in q[i].isha ?? 1e9 }
        let fa = { (i: Int) in q[i].fajr18 ?? -1e9 }
        var isha = q.indices.map(angle)
        var imsak = q.indices.map(fa)

        // Takdir: anchor days L (last with Fajr up to 21.06.) and L2 (first from 21.06.).
        if let l = (0...sol).last(where: { q[$0].r3 != nil }),
            let l2 = (sol..<q.count).first(where: { q[$0].r3 != nil }), let rL = q[l].r3
        {
            let fz = { (i: Int) in q[i].maghrib + rL * q[i].night }
            if angle(l) > fz(l) {
                let fr = { (i: Int) in q[i].sunrise - k * (fz(i) - q[i].maghrib) }
                let g20 = 20.0
                /// Fractional day on which `gap` drops from ≥ 20 below 20 (sequence towards the anchor).
                func crossing(_ array: [Int], _ gap: (Int) -> Double) -> Double? {
                    for (a, b) in zip(array, array.dropFirst()) {
                        let ga = gap(a)
                        let gb = gap(b)
                        if ga >= g20 && g20 > gb { return Double(a) + Double(b - a) * (ga - g20) / (ga - gb) }
                    }
                    return nil
                }
                // Anchor as a fractional day: the moment the 18° twilight disappears
                // (spring) or returns (autumn), linear between two days. With whole
                // anchor days 13–26 % of the transition days were off by one minute (2,110 İlçe).
                let f = la * .pi / 180
                let fv = { (i: Int) in
                    (sin(-PrayerTimeCalculator.imsakAngle * .pi / 180) - sin(f) * sin(q[i].declination))
                        / (cos(f) * cos(q[i].declination)) + 1
                }
                let la0 = l < sol && fv(l + 1) < 0 ? Double(l) + fv(l) / (fv(l) - fv(l + 1)) : Double(l)
                let lb0 =
                    l2 > sol && fv(l2 - 1) < 0 ? Double(l2) - fv(l2) / (fv(l2) - fv(l2 - 1)) : Double(l2)
                func search(_ fn: (Int) -> Double, _ xf: Double) -> Double {
                    let i0 = Int(xf.rounded(.down))
                    return fn(i0) + (fn(min(i0 + 1, q.count - 1)) - fn(i0)) * (xf - Double(i0))
                }
                let fza = search(fz, la0)
                let fzb = search(fz, lb0)
                let fra = search(fr, la0)
                let frb = search(fr, lb0)
                let spring = Array(0...l)
                let autumn = Array((l2..<q.count).reversed())
                let sx = crossing(spring) { fza - angle($0) }
                let ex = crossing(autumn) { fzb - angle($0) }
                let sfx = crossing(spring) { fa($0) - fra }
                let efx = crossing(autumn) { fa($0) - frb }
                for i in q.indices {
                    let x = Double(i)
                    if x < la0 {
                        if let sx, sx < x { isha[i] = min(angle(i), fza - g20 * (la0 - x) / (la0 - sx)) }
                        if let sfx, sfx < x { imsak[i] = max(fa(i), fra + g20 * (la0 - x) / (la0 - sfx)) }
                    } else if x <= lb0 {
                        isha[i] = min(angle(i), fz(i))
                        imsak[i] = max(fa(i), q[i].sunrise - k * (isha[i] - q[i].maghrib))
                    } else {
                        if let ex, x < ex { isha[i] = min(angle(i), fzb - g20 * (x - lb0) / (ex - lb0)) }
                        if let efx, x < efx { imsak[i] = max(fa(i), frb + g20 * (x - lb0) / (efx - lb0)) }
                    }
                }
            }
        }
        let imsakSol = imsak[sol]
        var result: [Day: [Prayer: Double]] = [:]
        for (i, g) in days.enumerated() {
            let im = (q[i].polar || abs(la) > 60) ? max(imsak[i], imsakSol) : imsak[i]
            result[g] = [
                .imsak: im, .sunrise: q[i].sunrise, .dhuhr: q[i].dhuhr, .asr: q[i].asr,
                .maghrib: q[i].maghrib,
                .isha: isha[i],
            ]
        }
        self.days = result
    }

    private static func ham(_ g: Day, la: Double, lo: Double, method: PrayerTimeCalculator.Method) -> Raw {
        let ai = method.ishaAngle
        let (declination, equationOfTime) = PrayerTimeCalculator.sunrise(PrayerTimeCalculator.julianDay(g))
        let dhuhrMoment = (12 - lo / 15 - equationOfTime) * 60
        let h = { (y: Double) in
            PrayerTimeCalculator.hourAngle(latitude: la, altitude: y, declination: declination)
        }
        let h0 = h(-0.833)
        let dhuhr = dhuhrMoment + method.dhuhrTemkin
        var sunrise: Double
        var maghrib: Double
        if let h0 {
            sunrise = dhuhrMoment - h0 - 7
            maghrib = dhuhrMoment + h0 + 7
        } else if declination * la > 0 {
            sunrise = dhuhr - 570
            maghrib = dhuhr + 570
        } else {
            sunrise = dhuhr - 150
            maghrib = dhuhr + 150
        }
        sunrise = min(max(sunrise, dhuhr - 570), dhuhr - 150)
        maghrib = max(min(maghrib, dhuhr + 570), dhuhr + 150)
        let shadow = atan(1 / (1 + tan(abs(la * .pi / 180 - declination)))) * 180 / .pi
        var asr = dhuhr
        if let ha = h(shadow), abs(la - declination * 180 / .pi) < 90 {
            asr = dhuhrMoment + ha + method.asrTemkin
        }
        return Raw(
            sunrise: sunrise, maghrib: maghrib, dhuhr: dhuhr, asr: min(asr, maghrib),
            isha: h(-ai).map { dhuhrMoment + $0 },
            fajr18: h(-PrayerTimeCalculator.imsakAngle).map { dhuhrMoment - $0 },
            polar: h0 == nil, declination: declination)
    }
}
