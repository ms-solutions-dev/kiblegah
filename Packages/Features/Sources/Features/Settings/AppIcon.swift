import DesignSystem
import SwiftUI

#if os(iOS)
    import UIKit
#endif

/// The app icons: Kalp Pusula is the default icon again,
/// the others are alternate icons in the asset catalog (`AppIcon…`); of the heart icons
/// from Oct 19, Ümmet remains. Preview images are separate image sets (`Ikon…`), because
/// icon sets cannot be loaded as an image.
enum AppIcon: String, CaseIterable, Identifiable {
    case heartCompass = "kalpPusula", kaf, kaaba = "kabe", mihrab = "mihrap", star = "yildiz", horizon =
        "ufuk", kef, ummah = "ummet"

    var id: String { rawValue }

    /// Name for `setAlternateIconName`; `nil` means the default icon.
    var systemName: String? {
        switch self {
        case .heartCompass: nil
        case .kaf: "AppIconKaf"
        case .kaaba: "AppIconKabe"
        case .mihrab: "AppIconMihrap"
        case .star: "AppIconYildiz"
        case .horizon: "AppIconUfuk"
        case .kef: "AppIconKef"
        case .ummah: "AppIconUmmet"
        }
    }

    var previewName: String {
        switch self {
        case .heartCompass: "IkonKalpPusula"
        case .kaf: "IkonKaf"
        case .kaaba: "IkonKabe"
        case .mihrab: "IkonMihrap"
        case .star: "IkonYildiz"
        case .horizon: "IkonUfuk"
        case .kef: "IkonKef"
        case .ummah: "IkonUmmet"
        }
    }

    var nameKey: LocalizedStringKey {
        switch self {
        case .heartCompass: "ayar.ikon.kalp_pusula"
        case .kaf: "ayar.ikon.kaf"
        case .kaaba: "ayar.ikon.kabe"
        case .mihrab: "ayar.ikon.mihrap"
        case .star: "ayar.ikon.yildiz"
        case .horizon: "ayar.ikon.ufuk"
        case .kef: "ayar.ikon.kef"
        case .ummah: "ayar.ikon.ummet"
        }
    }
}

/// App icon selection under Ayarlar → Görünüm. The system remembers the choice itself.
/// Names may take two lines instead of shrinking, so that all stay the same size.
struct AppIconPicker: View {
    @Environment(\.theme) private var theme
    @State private var selected: AppIcon = .heartCompass

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(app: "ayar.ikon")
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 4),
                spacing: 12
            ) {
                ForEach(AppIcon.allCases) { iconCase in
                    Button {
                        sec(iconCase)
                    } label: {
                        VStack(spacing: 6) {
                            Image(iconCase.previewName, bundle: .main)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 56, height: 56)
                                .clipShape(.rect(cornerRadius: 13, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                                        .stroke(
                                            selected == iconCase ? theme.colors.accent : .clear,
                                            lineWidth: 2.5
                                        )
                                        .padding(-3)
                                }
                            Text(app: iconCase.nameKey).typography(.footnote).lineLimit(
                                2, reservesSpace: true
                            )
                            .multilineTextAlignment(.center)
                            .foregroundStyle(selected == iconCase ? theme.colors.text : theme.colors.text2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(app: iconCase.nameKey))
                    .accessibilityAddTraits(selected == iconCase ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            #if os(iOS)
                let name = UIApplication.shared.alternateIconName
                selected = AppIcon.allCases.first { $0.systemName == name } ?? .heartCompass
            #endif
        }
    }

    private func sec(_ iconCase: AppIcon) {
        guard iconCase != selected else { return }
        #if os(iOS)
            guard UIApplication.shared.supportsAlternateIcons else { return }
            let previous = selected
            selected = iconCase
            UIApplication.shared.setAlternateIconName(iconCase.systemName) { failed in
                if failed != nil { Task { @MainActor in selected = previous } }
            }
        #endif
    }
}
