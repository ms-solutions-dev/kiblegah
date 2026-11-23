import Core
import Foundation

public struct Reciter: Identifiable, Hashable, Sendable, Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case name = "ad"
        case style = "stil"
        case folder = "klasor"
        case storeEligible = "storeTauglich"
        case qcID = "qcId"
        case fullSurah = "tamSure"
        case qiraat = "kiraat"
    }

    public let id: String
    public let name: String
    public let style: String
    /// Path at Quran.com (`verses.quran.com/…`) or its mirror (`//mirrors.quranicaudio.com/…`),
    /// one `SSSAAA.mp3` per verse – this is what `/recitations/{id}/by_ayah` returns.
    let folder: String
    /// QF content: in the Store edition only via the QF relay.
    public var storeEligible = false
    /// Recitation ID at Quran.com; the word timings (`WordTimings`) belong to exactly these files.
    public var qcID: Int? = nil
    public var fullSurah: String? = nil
    /// Different reading, as a hint in the selection (e.g. „el-Bezzî an İbn Kesîr“).
    public var qiraat: String? = nil

    public static let source = "Quran.com (Quran Foundation)"
    static let base = URL(string: "https://verses.quran.com/")!

    /// All selectable reciters: the catalog, plus `extras` only with the switch `FeatureFlags.extraReciters`.
    public static var all: [Reciter] {
        catalog + (FeatureFlags.enabled.contains(.extraReciters) ? extras : [])
    }

    nonisolated(unsafe) public static var extras: [Reciter] = []

    /// A reciter with one file per surah (`<address>SSS.mp3`), e.g. from mp3quran.
    public static func hasFullSurah(
        id: String, name: String, style: String, address: String, qiraat: String? = nil
    ) -> Reciter {
        Reciter(id: id, name: name, style: style, folder: "", fullSurah: address, qiraat: qiraat)
    }

    /// Only the Quran.com catalog: verse by verse, with word timings for reading along.
    /// IDs and paths from `/resources/recitations` and `/recitations/{id}/by_ayah`.
    public static let catalog: [Reciter] = [
        Reciter(id: "alafasy", name: "Mishary Alafasy", style: "Murattal", folder: "Alafasy/mp3", qcID: 7),
        Reciter(
            id: "abdulbasit", name: "Abdul Basit Abdus Samad", style: "Murattal",
            folder: "AbdulBaset/Murattal/mp3",
            qcID: 2),
        Reciter(
            id: "abdulbasit-mucevved", name: "Abdul Basit Abdus Samad", style: "Mücevved",
            folder: "AbdulBaset/Mujawwad/mp3", qcID: 1),
        Reciter(
            id: "minshawi", name: "Mohamed Siddiq Al-Minshawi", style: "Murattal",
            folder: "Minshawi/Murattal/mp3",
            qcID: 9),
        Reciter(
            id: "minshawi-mucevved", name: "Mohamed Siddiq Al-Minshawi", style: "Mücevved",
            folder: "Minshawi/Mujawwad/mp3", qcID: 8),
        Reciter(
            id: "sudais", name: "Abdurrahman As-Sudais", style: "Murattal", folder: "Sudais/mp3", qcID: 3),
        Reciter(id: "shatri", name: "Abu Bakr Al-Shatri", style: "Murattal", folder: "Shatri/mp3", qcID: 4),
        Reciter(id: "rifai", name: "Hani Ar-Rifai", style: "Murattal", folder: "Rifai/mp3", qcID: 5),
        Reciter(id: "shuraym", name: "Saud Ash-Shuraim", style: "Murattal", folder: "Shuraym/mp3", qcID: 10),
        Reciter(
            id: "husary", name: "Mahmoud Khalil Al-Husary", style: "Murattal",
            folder: "//mirrors.quranicaudio.com/everyayah/Husary_64kbps", qcID: 6),
        Reciter(
            id: "husary-muallim", name: "Mahmoud Khalil Al-Husary", style: "Muallim (öğretici)",
            folder: "//mirrors.quranicaudio.com/everyayah/Husary_Muallim_128kbps", qcID: 12),
        Reciter(
            id: "tablawi", name: "Mohamed Al-Tablawi", style: "Murattal",
            folder: "//mirrors.quranicaudio.com/everyayah/Mohammad_al_Tablaway_128kbps", qcID: 11),
    ]

    public static let standard = catalog[0]

    public static func find(_ id: String) -> Reciter { all.first { $0.id == id } ?? standard }

    static func fileName(surah: Int, verse: Int) -> String { String(format: "%03d%03d.mp3", surah, verse) }

    /// The file of the whole surah for `fullSurah` reciters.
    public func surahFile(_ surah: Int) -> URL? {
        fullSurah.flatMap { URL(string: $0 + String(format: "%03d.mp3", surah)) }
    }

    public func remote(surah: Int, verse: Int) -> URL {
        if let u = surahFile(surah) { return u }
        let root =
            folder.hasPrefix("//") ? URL(string: "https:" + folder)! : Self.base.appending(path: folder)
        return root.appending(path: Self.fileName(surah: surah, verse: verse))
    }
}
