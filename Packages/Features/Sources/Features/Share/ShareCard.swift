import Core
import DesignSystem
import Foundation
import Qibla

/// What a shareable 9:16 card shows (variant 07): verse, dua, hadith, divine name or the Qibla route.
///
/// Pure data, so that every place in the app passes only the content with its citation and the sheet
/// (``ShareSheet``) handles style, color and permissions itself. Content always comes from the
/// app data; the card adds nothing of its own.
public struct ShareCard: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable, Hashable {
        case verse = "ayet", dua, hadith = "hadis", divineName = "esma", qibla = "kible"
    }

    public let kind: Kind
    /// Header line in the „Renk“ style, e.g. „GÜNÜN AYETİ“; in the „Gökyüzü“ style it shows prayer time and place.
    public let parent: String
    public let arabic: String
    /// Name between Arabic and meaning, e.g. the reading of a divine name.
    public let title: String
    /// Translation or meaning; can be switched off in the sheet.
    public let meaning: String
    /// Citation like „İnşirâh 94:5 · Diyanet meali“; always appears on the card.
    public let source: String
    /// Link back into the app (`kiblegah://…`), only in the text, never in the image.
    public let link: String?
    public let qiblaDistanceKm: Double?
    public let qiblaAngle: Double?
    /// Place name; appears only if the user turns on „Ort zeigen“.
    public let place: String?

    public var id: String { "\(kind.rawValue)|\(link ?? source)|\(arabic.prefix(24))" }

    init(
        kind: Kind, parent: String, arabic: String = "", title: String = "", meaning: String = "",
        source: String, link: String? = nil, qiblaDistanceKm: Double? = nil, qiblaAngle: Double? = nil,
        place: String? = nil
    ) {
        self.kind = kind
        self.parent = parent
        self.arabic = arabic
        self.title = title
        self.meaning = meaning
        self.source = source
        self.link = link
        self.qiblaDistanceKm = qiblaDistanceKm
        self.qiblaAngle = qiblaAngle
        self.place = place
    }

    /// A verse or verse range.
    ///
    /// - Parameter kaynak: surah and verse including translation name, e.g. „İnşirâh 94:5 · Diyanet meali“.
    /// - Parameter sure: for the link back `kiblegah://quran/94:5`.
    /// - Parameter ust: own header line, e.g. „Günün ayeti“; otherwise „Ayet“.
    public static func verse(
        arabic: String, translation: String, source: String, surah: Int, verse: Int, parent: String? = nil
    ) -> ShareCard {
        ShareCard(
            kind: .verse, parent: parent ?? localized("paylas.ust.ayet"), arabic: arabic,
            meaning: translation, source: source,
            link: "kiblegah://kuran/\(surah):\(verse)")
    }

    public static func dua(arabic: String, meaning: String, source: String, slug: String) -> ShareCard {
        ShareCard(
            kind: .dua, parent: localized("paylas.ust.dua"), arabic: arabic, meaning: meaning, source: source,
            link: "kiblegah://dua/\(slug)")
    }

    public static func sunnahDua(
        arabic: String, transliteration: String, meaning: String, source: String, identifier: String
    ) -> ShareCard {
        ShareCard(
            kind: .dua, parent: localized("paylas.ust.dua"), arabic: arabic, title: transliteration,
            meaning: meaning,
            source: source,
            link: "kiblegah://sunnet/dua/\(identifier)")
    }

    /// A hadith from HadeethEnc; `arabic` may be missing, in which case the translation always stays on.
    public static func hadith(text: String, arabic: String, source: String, identifier: Int) -> ShareCard {
        ShareCard(
            kind: .hadith, parent: localized("paylas.ust.hadis"), arabic: arabic, meaning: text,
            source: source,
            link: "kiblegah://hadis/\(identifier)")
    }

    public static func divineName(
        arabic: String, name: String, meaning: String, source: String, number: Int
    ) -> ShareCard {
        ShareCard(
            kind: .divineName, parent: localized("paylas.ust.esma"), arabic: arabic, title: name,
            meaning: meaning,
            source: source, link: "kiblegah://esma/\(number)")
    }

    /// Route from the place to the Kaaba; distance and direction from ``QiblaCalculation``.
    public static func qibla(_ location: Location) -> ShareCard {
        ShareCard(
            kind: .qibla, parent: localized("paylas.ust.kible"), source: "", link: "kiblegah://kible",
            qiblaDistanceKm: QiblaCalculation.distance(location) / 1000,
            qiblaAngle: QiblaCalculation.angle(location),
            place: location.name)
    }

    /// Whether the meaning can be switched off: without Arabic only the source would remain.
    var meaningHideable: Bool { !arabic.isEmpty && !meaning.isEmpty }

    var kmText: String {
        Int((qiblaDistanceKm ?? 0).rounded()).formatted(.number.locale(AppLanguage.locale))
    }

    var angleText: String { "\(Int((qiblaAngle ?? 0).rounded()))°" }

    /// „Nur Text“: what is shared without an image, with the same permissions as the card.
    func text(showMeaning: Bool, showPlace: Bool) -> String {
        if kind == .qibla {
            let row =
                showPlace && place != nil
                ? localized("paylas.kible.yerli \(place ?? "") \(kmText) \(angleText)")
                : localized("paylas.kible.yersiz \(kmText) \(angleText)")
            return "\(row)\n— Kıblegâh"
        }
        let hasMeaning = showMeaning || !meaningHideable
        let parts = [arabic, title, hasMeaning ? meaning : ""].filter { !$0.isEmpty }
        let bottom = ["— \(source) · Kıblegâh", link ?? ""].filter { !$0.isEmpty }
        return (parts + bottom).joined(separator: "\n\n")
    }
}

/// The two styles of the sheet: fixed base color (07 A) or sky of the time of day (07 B).
enum ShareStyle: String, CaseIterable, Sendable { case color = "renk", sky = "gok" }

/// What the user chose in the sheet; kept for the next share.
///
/// The place is off by default (privacy, variant 07 B/C): whoever wants to show it turns it
/// on deliberately. The keys contain no dots, otherwise the catalog checker reads them as texts.
struct ShareOptions: Equatable, Sendable {
    var style: ShareStyle = .color
    var color: CardColor = .green
    var showMeaning = true
    var showPlace = false

    static let styleKey = "paylasStili"
    static let colorKey = "paylasRengi"
    static let meaningKey = "paylasAnlam"
    static let placeKey = "paylasYer"

    init() {}

    init(defaults: UserDefaults) {
        style = defaults.string(forKey: Self.styleKey).flatMap(ShareStyle.init(rawValue:)) ?? .color
        color = defaults.string(forKey: Self.colorKey).flatMap(CardColor.init(rawValue:)) ?? .green
        showMeaning = defaults.object(forKey: Self.meaningKey) as? Bool ?? true
        showPlace = defaults.object(forKey: Self.placeKey) as? Bool ?? false
    }

    func save(_ defaults: UserDefaults) {
        defaults.set(style.rawValue, forKey: Self.styleKey)
        defaults.set(color.rawValue, forKey: Self.colorKey)
        defaults.set(showMeaning, forKey: Self.meaningKey)
        defaults.set(showPlace, forKey: Self.placeKey)
    }
}
