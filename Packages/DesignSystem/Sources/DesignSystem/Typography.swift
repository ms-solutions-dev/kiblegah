import CoreText
import SwiftUI

/// Typography roles. Each role is tied to an iOS text style and grows with
/// Dynamic Type up to AX5. Fraunces only for headings and large numbers in the theme
/// Seher; Sakin sets everything in Plus Jakarta Sans.
public enum Typography {
    case accent
    case title1
    case title2
    case emphasized
    case body
    case secondary
    case footnote
    /// Arabic Quran and dua text.
    case arabic(size: CGFloat)

    func font(simple: Bool) -> Font {
        let serif = simple ? Typography.sans : Typography.serif
        switch self {
        case .accent: return .custom(serif, size: 46, relativeTo: .largeTitle).weight(.semibold)
        case .title1: return .custom(serif, size: 28, relativeTo: .title).weight(.semibold)
        case .title2: return .custom(Typography.sans, size: 20, relativeTo: .title3).weight(.bold)
        case .emphasized: return .custom(Typography.sans, size: 17, relativeTo: .headline).weight(.semibold)
        case .body: return .custom(Typography.sans, size: 17, relativeTo: .body)
        case .secondary: return .custom(Typography.sans, size: 15, relativeTo: .subheadline)
        case .footnote: return .custom(Typography.sans, size: 13, relativeTo: .footnote)
        case .arabic(let size): return .custom(Typography.arabicName, size: size, relativeTo: .title)
        }
    }

    static let serif = "Fraunces"
    static let sans = "Plus Jakarta Sans"
    static let arabicName = "Amiri"
    /// For views that determine the size themselves (Mushaf page).
    public static var arabicFontName: String { arabicName }

    /// Registers the bundled fonts with the system. Once at startup, idempotent.
    @MainActor public static func save() {
        guard !stored else { return }
        stored = true
        guard let folder = Bundle.module.url(forResource: "YaziTipleri", withExtension: nil),
            let files = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil)
        else { return }
        for url in files where url.pathExtension == "ttf" {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    @MainActor private static var stored = false
}

extension View {
    /// Applies a typography role matching the current theme.
    public func typography(_ role: Typography) -> some View {
        modifier(TextLayout(role: role))
    }
}

private struct TextLayout: ViewModifier {
    @Environment(\.theme) private var theme
    let role: Typography

    func body(content: Content) -> some View {
        content.font(role.font(simple: theme.largeAndSimple))
    }
}
