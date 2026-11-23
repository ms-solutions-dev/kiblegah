import Core
import Foundation

/// A Hijri date. Diyanet delivers it with each day; without a server the app computes
/// astronomically (`Calendar.islamic`) with a correction from the last Diyanet stock.
/// Diyanet follows its own sighting criteria; measured over three months (Oct-Dec 2026)
/// the calculation hits 52 of 76 days and is otherwise one day off - therefore
/// the UI shows computed Hijri dates as „yaklaşık“ - except in the period for which
/// Diyanet's month starts are bundled:
/// there the date is exact, even offline.
public struct HijriDate: Codable, Sendable, Hashable {
    enum CodingKeys: String, CodingKey {
        case day = "gun"
        case month = "ay"
        case year = "yil"
    }

    public let day: Int
    /// 1 = Muharrem … 12 = Zilhicce.
    public let month: Int
    public let year: Int

    public init(day: Int, month: Int, year: Int) {
        self.day = day
        self.month = month
        self.year = year
    }

    /// Turkish month names in the spelling of the Diyanet API.
    public static let months = [
        "Muharrem", "Safer", "Rebiülevvel", "Rebiülahir", "Cemaziyelevvel", "Cemaziyelahir",
        "Recep", "Şaban", "Ramazan", "Şevval", "Zilkade", "Zilhicce",
    ]

    /// Reads „7 Cemaziyelevvel 1448“. Unknown spellings yield `nil`.
    public init?(diyanet text: String) {
        let p = text.split(separator: " ").map(String.init)
        guard p.count >= 3, let g = Int(p[0]), let y = Int(p[p.count - 1]) else { return nil }
        let name = p[1..<(p.count - 1)].joined()
        let fold = { (s: String) in
            s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr"))
                .replacingOccurrences(of: "ı", with: "i")
        }
        guard let i = HijriDate.months.firstIndex(where: { fold($0) == fold(name) }) else { return nil }
        self.init(day: g, month: i + 1, year: y)
    }

    public var monthName: String { HijriDate.months[month - 1] }

    struct DiyanetMonths: Decodable {
        enum CodingKeys: String, CodingKey {
            case end = "son"
            case months = "aylar"
        }

        struct Month: Decodable {
            enum CodingKeys: String, CodingKey {
                case year = "yil"
                case month = "ay"
                case start = "baslangic"
            }

            let year: Int
            let month: Int
            let start: String
        }
        let end: String
        let months: [Month]
    }

    /// Diyanet's month starts as (day, Hijri year, month), ascending; plus the last attested day.
    static let diyanetMonths: (months: [(Day, Int, Int)], end: Day?) = {
        guard let url = Bundle.module.url(forResource: "hicri-diyanet", withExtension: "json"),
            let veri = try? Data(contentsOf: url),
            let d = try? JSONDecoder().decode(DiyanetMonths.self, from: veri)
        else { return ([], nil) }
        let day = { (s: String) -> Day? in
            let p = s.split(separator: "-").compactMap { Int($0) }
            return p.count == 3 ? Day(year: p[0], month: p[1], day: p[2]) : nil
        }
        return (d.months.compactMap { a in day(a.start).map { ($0, a.year, a.month) } }, day(d.end))
    }()

    /// The date according to Diyanet's own table if `day` lies within it; otherwise `nil`.
    public static func fromDiyanet(_ day: Day) -> HijriDate? {
        let (months, end) = diyanetMonths
        guard let end, day <= end, let i = months.lastIndex(where: { $0.0 <= day }) else { return nil }
        let (start, year, month) = months[i]
        let difference = Int((day.start(.gmt).timeIntervalSince(start.start(.gmt)) / 86_400).rounded())
        return HijriDate(day: difference + 1, month: month, year: year)
    }

    /// Whether the Hijri date for `day` is exact (per Diyanet).
    public static func exact(_ day: Day) -> Bool { fromDiyanet(day) != nil }

    /// Diyanet's date where the table reaches; otherwise astronomical, shifted by `adjustment` days.
    public static func calculate(_ day: Day, adjustment: Int = 0) -> HijriDate {
        if let d = fromDiyanet(day) { return d }
        var calendar = Calendar(identifier: .islamic)
        calendar.timeZone = .gmt
        let time = day.added(adjustment).start(.gmt).addingTimeInterval(12 * 3600)
        let c = calendar.dateComponents([.year, .month, .day], from: time)
        return HijriDate(day: c.day!, month: c.month!, year: c.year!)
    }

    /// The correction with which the calculation hits the most Diyanet days of a stock.
    public static func adjustment(_ table: PrayerTimeTable) -> Int {
        let diyanet = table.days.filter { $0.source == .diyanet && $0.hijri != nil }
        guard !diyanet.isEmpty else { return 0 }
        return [0, -1, 1].max { a, b in
            diyanet.filter { calculate($0.day, adjustment: a) == $0.hijri }.count
                < diyanet.filter { calculate($0.day, adjustment: b) == $0.hijri }.count
        } ?? 0
    }

    /// Running day number (for „at most one day off“).
    var dayCount: Int { (year * 12 + month) * 30 + day }
}
