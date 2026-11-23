import ContentPacks
import Core
import DesignSystem
import PrayerTimes
import SwiftUI
import UserData

extension EnvironmentValues {
    /// The content interface; the app sets it at launch.
    @Entry public var contentProvider: (any ContentProvider)? = nil
}

/// The content language follows the app language (Ayarlar → Dil, otherwise iPhone).
public func translationLanguage() -> String { AppLanguage.code }

/// For German there is neither transliteration nor tafsir. Without its own choice the app takes Turkish
/// if it is among the device languages (German Turks), otherwise English.
func fallbackLanguage(_ selection: String) -> String {
    if !selection.isEmpty { return selection }
    let language = translationLanguage()
    if language != "de" { return language == "tr" ? "tr" : "en" }
    return Locale.preferredLanguages.contains { $0.hasPrefix("tr") } ? "tr" : "en"
}

@MainActor func transliterationLanguage(_ a: AppSettings) -> String {
    fallbackLanguage(a.transliterationLanguage)
}

@MainActor func tafsirLanguage(_ a: AppSettings) -> String {
    translationLanguage() == "de" ? fallbackLanguage(a.tafsirLanguage) : translationLanguage()
}

/// Günün ayeti: a short, encouraging verse per day from a fixed list.
///
/// The list contains only keys; the text comes unchanged from the translation bundles.
/// Short verses were chosen that cannot be misunderstood without context.
struct VerseOfTheDay: View {
    @Environment(\.contentProvider) private var contentProvider
    @Environment(\.theme) private var theme
    let day: Day

    nonisolated static let list: [ContentKey] = [
        .verse(surah: 94, verse: 5), .verse(surah: 94, verse: 6), .verse(surah: 13, verse: 28),
        .verse(surah: 2, verse: 152),
        .verse(surah: 39, verse: 53), .verse(surah: 2, verse: 186), .verse(surah: 3, verse: 139),
        .verse(surah: 2, verse: 153),
        .verse(surah: 49, verse: 13), .verse(surah: 17, verse: 23), .verse(surah: 3, verse: 159),
        .verse(surah: 93, verse: 5),
        .verse(surah: 2, verse: 45), .verse(surah: 16, verse: 97), .verse(surah: 33, verse: 41),
        .verse(surah: 2, verse: 286),
    ]

    nonisolated static func key(_ g: Day) -> ContentKey {
        let dayNumber = Int(g.start(.gmt).timeIntervalSince1970 / 86400)
        return list[dayNumber % list.count]
    }

    var body: some View {
        let a = Self.key(day)
        if let contentProvider, case .verse(let s, let n) = a, let surah = contentProvider.surah(s),
            let pack = contentProvider.translations(language: translationLanguage()).first,
            let translation = contentProvider.translation(a, pack: pack.id)
        {
            NavigationLink(value: Goal.verse(a)) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app: "gunun_ayeti \(surah.name(language: translationLanguage())) \(n)")
                            .typography(.footnote).textCase(.uppercase).foregroundStyle(theme.colors.label)
                        Text(verbatim: translation.text).typography(.title2).lineLimit(4)
                            .multilineTextAlignment(
                                .leading
                            )
                            .foregroundStyle(theme.colors.text)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(theme.colors.text2)
                        .accessibilityHidden(true)
                }
                .padding(16)
                .background(theme.colors.surface2, in: .rect(cornerRadius: 22))
            }
            .buttonStyle(.plain)
        }
    }
}

extension Surah {
    /// Surah name in the language of the UI package: Turkish according to Diyanet, otherwise the transliteration;
    /// German without the English long vowels („Al-Faatiha“ → „Al-Fatiha“).
    public func name(language: String) -> String {
        switch language {
        case "tr": nameTurkish
        case "de":
            nameLatin.replacingOccurrences(of: "aa", with: "a").replacingOccurrences(of: "ee", with: "i")
                .replacingOccurrences(of: "oo", with: "u")
        default: nameLatin
        }
    }
}
