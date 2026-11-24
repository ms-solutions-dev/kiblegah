import Core
import Foundation

/// Kandil, Eid and further days of the year.
///
/// Preferably from the server's Diyanet list; without it from the Hijri calendar with the
/// correction that the last Diyanet stock delivered. Computed lists carry
/// `calculated`, so the UI can append „yaklaşık“.
public struct ReligiousDay: Hashable, Sendable, Codable {
    enum CodingKeys: String, CodingKey {
        case kind = "tur"
        case day = "gun"
        case source = "kaynak"
    }

    public enum Kind: String, Sendable, Codable, CaseIterable {
        case hijriNewYear = "hicriYilbasi", ashura = "asure", mawlidKandil = "mevlidKandili",
            threeHolyMonthsStart = "uclerAylarBaslangici", raghaibKandil = "regaibKandili", mirajKandil =
            "miracKandili"
        case baratKandil = "beratKandili", ramadanStart = "ramazanBaslangici", laylatAlQadr = "kadirGecesi",
            eidAlFitrEve = "ramazanArefesi", eidAlFitr = "ramazanBayrami"
        case dayOfArafah = "kurbanArefesi", eidAlAdha = "kurbanBayrami"
    }

    public let kind: Kind
    /// For Kandil nights, the day on whose evening the night begins.
    public let day: Day
    /// Kandil nights begin on the evening of this day.
    public var isNight: Bool {
        [.mawlidKandil, .raghaibKandil, .mirajKandil, .baratKandil, .laylatAlQadr].contains(kind)
    }
    public let source: PrayerTimeSourceKind

    public init(kind: Kind, day: Day, source: PrayerTimeSourceKind) {
        self.kind = kind
        self.day = day
        self.source = source
    }

    /// All days in the Gregorian year `year`, computed.
    public static func calculate(year: Int, adjustment: Int = 0) -> [ReligiousDay] {
        var result: [ReligiousDay] = []
        var g = Day(year: year, month: 1, day: 1)
        var hijriDates: [(Day, HijriDate)] = []
        while g.year == year {
            hijriDates.append((g, HijriDate.calculate(g, adjustment: adjustment)))
            g = g.added(1)
        }
        let next = { (day: Day) in HijriDate.calculate(day.added(1), adjustment: adjustment) }
        for (day, h) in hijriDates {
            let nextDay = next(day)
            // If the day lies in Diyanet's Hijri table, it is exact (as from the server).
            func add(_ t: Kind, _ x: Day = day) {
                let exact = HijriDate.exact(x) && HijriDate.exact(x.added(1))
                result.append(ReligiousDay(kind: t, day: x, source: exact ? .diyanet : .calculated))
            }
            switch (h.month, h.day) {
            case (1, 1): add(.hijriNewYear)
            case (1, 10): add(.ashura)
            case (7, 1): add(.threeHolyMonthsStart)
            case (9, 1): add(.ramadanStart)
            case (10, 1): add(.eidAlFitr)
            case (12, 9): add(.dayOfArafah)
            case (12, 10): add(.eidAlAdha)
            default: break
            }
            // Nights: the evening before the Hijri day.
            switch (nextDay.month, nextDay.day) {
            case (3, 12): add(.mawlidKandil)
            case (7, 27): add(.mirajKandil)
            case (8, 15): add(.baratKandil)
            case (9, 27): add(.laylatAlQadr)
            default: break
            }
            if h.month == 9 && nextDay.month == 10 { add(.eidAlFitrEve) }
            // Regaib: the night leading to the first Friday in Recep, i.e. a Friday on the 1st to 7th of Recep.
            // Measured on the Hijri day instead of with a marker, otherwise a Recep across the
            // year boundary counts a second time in the new year.
            if nextDay.month == 7 && nextDay.day <= 7 && day.added(1).weekday == 6 {
                add(.raghaibKandil)
            }
        }
        return result.sorted { $0.day < $1.day }
    }
}

extension ReligiousDay {
    /// Assigns a Diyanet name („Regaip Kandili“, „Ramazan Bayramı 1. Gün“ …) to a kind.
    /// Unknown names yield `nil` and are dropped instead of landing wrongly.
    static func kind(diyanet name: String) -> Kind? {
        let k = name.folding(
            options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr")
        )
        .replacingOccurrences(of: "ı", with: "i")
        let rules: [(String, Kind)] = [
            ("regaip", .raghaibKandil), ("regaib", .raghaibKandil), ("mirac", .mirajKandil),
            ("berat", .baratKandil), ("kadir", .laylatAlQadr), ("mevlid", .mawlidKandil),
            ("uc aylar", .threeHolyMonthsStart), ("asure", .ashura), ("yilbasi", .hijriNewYear),
            ("ramazan bayrami arefe", .eidAlFitrEve), ("kurban bayrami arefe", .dayOfArafah),
            ("ramazan bayrami", .eidAlFitr), ("kurban bayrami", .eidAlAdha),
            ("ramazan baslangic", .ramadanStart), ("arefe", .dayOfArafah),
        ]
        return rules.first { k.contains($0.0) }?.1
    }
}

extension ServerSource {
    struct ReligiousDayRow: Decodable {
        enum CodingKeys: String, CodingKey {
            case name = "ad"
            case date = "tarih"
        }

        let name: String
        let date: String
    }

    /// Kandil and Eid of a year from the Diyanet list; for multi-day Eids the first day counts.
    public func religiousDays(year: Int) async throws -> [ReligiousDay] {
        var b = URLComponents(url: address.appending(path: "v1/dini-gunler"), resolvingAgainstBaseURL: false)!
        b.queryItems = [URLQueryItem(name: "yil", value: String(year))]
        // Like the table (8 s): without a limit an unreachable home server held up the refresh for 60 s.
        var request = URLRequest(url: b.url!)
        request.timeoutInterval = 8
        let (veri, answer) = try await session.data(for: request)
        if let h = answer as? HTTPURLResponse, h.statusCode != 200 {
            throw PrayerTimeError.server(h.statusCode)
        }
        return try Self.decodeReligiousDays(veri)
    }

    static func decodeReligiousDays(_ veri: Data) throws -> [ReligiousDay] {
        guard let rows = try? JSONDecoder().decode([ReligiousDayRow].self, from: veri) else {
            throw PrayerTimeError.invalidResponse
        }
        var seenItems = Set<ReligiousDay.Kind>()
        return rows.compactMap { s -> ReligiousDay? in
            guard let t = ReligiousDay.kind(diyanet: s.name), let g = Day(text: s.date),
                seenItems.insert(t).inserted
            else {
                return nil
            }
            return ReligiousDay(kind: t, day: g, source: .diyanet)
        }.sorted { $0.day < $1.day }
    }
}
