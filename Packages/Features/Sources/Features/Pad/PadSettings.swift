import Core
import DesignSystem
import SwiftUI
import UserData

/// Ayarlar on the iPad (board G18): a large sheet with the sections on the left and their content on the right.
/// The content is the iPhone's, section by section; nothing is left out.
struct PadSettingsScreen: View {
    enum Section: String, CaseIterable, Identifiable {
        case appearance, reading, location, notifications, calculation, compass, storage, quiz, language, data
        var id: String { rawValue }

        var title: String.LocalizationValue {
            switch self {
            case .appearance: "ipad.ayar.aussehen"
            case .reading: "ipad.ayar.lesen"
            case .location: "konum.baslik"
            case .notifications: "bildirim.baslik"
            case .calculation: "ipad.ayar.berechnung"
            case .compass: "ipad.ayar.kompass"
            case .storage: "depolama.baslik"
            case .quiz: "sekme.quiz"
            case .language: "ayar.dil"
            case .data: "ayar.bolum.veriler"
            }
        }
    }

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var section: Section = .appearance

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(app: "ayarlar.baslik").typography(.display(size: 24))
                    .padding(.horizontal, 12).padding(.top, 22).padding(.bottom, 12)
                ForEach(Section.allCases) { s in
                    Button {
                        section = s
                    } label: {
                        Text(verbatim: localized(s.title))
                            .typography(.label(size: 17))
                            .foregroundStyle(section == s ? theme.colors.accent : theme.colors.text2)
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .background(
                                section == s ? theme.colors.accent.opacity(0.14) : .clear,
                                in: .rect(cornerRadius: 14)
                            )
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(section == s ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(width: 260)
            .background(theme.colors.surface2)
            NavigationStack {
                content
                    .navigationTitle(Text(verbatim: localized(section.title)))
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(localized("genel.bitti")) { dismiss() }
                        }
                    }
                    .navigationDestination(for: Goal.self) { GoalScreen(goal: $0) }
            }
            .id(section)
        }
        .presentationSizing(.page)
        .presentationBackground(theme.colors.background)
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .notifications: NotificationsScreen()
        case .storage: StorageScreen()
        case .quiz: QuizSettingsScreen()
        case .reading: ReadingSettings(embedded: true)
        default: SettingsScreen(section: section)
        }
    }
}
