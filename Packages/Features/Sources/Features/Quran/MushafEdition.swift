import ContentPacks
import Core

/// Which Medina edition the Mushaf shows.
///
/// `v1` (KFGQPC 1405 H) is the numbering of the whole app (`medine-604`: reading position, juz, jumps).
/// `v2` is the print of 1421 H, `v4` the same grid with tajweed page fonts (color is in
/// the font, one file for light and dark). The page boundaries of V2/V4 differ on 25 pages by individual verses. The differences are listed here
/// as a fixed table (page boundaries of a print, reconciled from `v1_page`/`v2_page` of the QF API).
enum MushafEdition: String, Sendable, CaseIterable, Identifiable {
    case v1, v2, v4

    var id: String { rawValue }

    /// From the setting; if unselected, V1 applies.
    init(setting: String) { self = MushafEdition(rawValue: setting) ?? .v1 }

    /// Glyph grid: V2 and V4 share the characters and page boundaries of the 1421 print.
    /// Also the key for the layout routes (`/v1/mushaf/<n>?surum=`).
    var raster: String { self == .v1 ? "v1" : "v2" }

    /// Name of the bundle at Apple and the folder in it.
    var packID: String { "mushaf-\(rawValue)" }

    /// Approximate size of the bundle on the device, measured when bundling.
    var sizeMB: Int {
        switch self {
        case .v1: 49
        case .v2: 98
        case .v4: 52
        }
    }

    /// Verses (consecutive number) that are on a different page in V2 than in V1.
    static let v2Page: [Int: Int] = [
        746: 120, 752: 121, 759: 122, 920: 145, 4918: 531, 4919: 531, 4942: 532, 4969: 533, 4970: 533,
        5287: 564, 5358: 567, 5415: 569, 5513: 575, 5728: 583, 5799: 586, 5800: 586, 5853: 588, 5854: 588,
        5882: 589, 5909: 590, 5959: 592, 5960: 592, 5961: 592, 5962: 592, 5963: 592, 5990: 593, 5991: 593,
        5992: 593, 5993: 593, 6016: 594, 6042: 595, 6043: 595, 6068: 596, 6069: 596, 6070: 596, 6071: 596,
        6072: 596, 6093: 597, 6094: 597, 6095: 597, 6096: 597, 6097: 597, 6098: 597, 6119: 598, 6120: 598,
        6121: 598, 6122: 598, 6123: 598, 6124: 598, 6125: 598, 6136: 599, 6137: 599, 6152: 600, 6153: 600,
        6154: 600, 6155: 600,
    ]

    /// First verse of the V2 pages whose beginning differs from V1.
    static let v2Start: [Int: Int] = [
        121: 747, 122: 753, 123: 760, 145: 920, 532: 4920, 533: 4943, 534: 4971, 565: 5288, 568: 5359,
        570: 5416, 576: 5514, 584: 5729, 586: 5799, 588: 5853, 589: 5882, 590: 5909, 592: 5959, 593: 5990,
        594: 6016, 595: 6042, 596: 6068, 597: 6093, 598: 6119, 599: 6136, 600: 6152,
    ]

    /// Page on which the verse `index` begins.
    func page(index: Int, _ contentProvider: any ContentProvider) -> Int? {
        if self != .v1, let n = Self.v2Page[index] { return n }
        return contentProvider.key(index: index).flatMap { contentProvider.verse($0) }?.page
    }

    /// Page of a verse.
    func page(surah: Int, verse: Int, _ contentProvider: any ContentProvider) -> Int? {
        guard let s = contentProvider.surah(surah) else { return nil }
        return page(index: s.firstIndex + min(max(verse, 1), s.verseCount) - 1, contentProvider)
    }

    /// First and last verse of page `n`.
    func interval(_ n: Int, _ contentProvider: any ContentProvider) -> (first: Int, end: Int)? {
        guard let b = contentProvider.page(n) else { return nil }
        guard self != .v1 else { return (b.firstIndex, b.lastIndex) }
        let first = Self.v2Start[n] ?? b.firstIndex
        let end =
            n >= 604
            ? b.lastIndex
            : (Self.v2Start[n + 1] ?? contentProvider.page(n + 1)?.firstIndex ?? b.lastIndex + 1) - 1
        return (first, end)
    }

    /// The same position in the other edition: via the first verse of the page.
    func convert(_ n: Int, nach: MushafEdition, _ contentProvider: any ContentProvider) -> Int {
        guard raster != nach.raster, let a = interval(n, contentProvider) else { return n }
        return nach.page(index: a.first, contentProvider) ?? n
    }
}
