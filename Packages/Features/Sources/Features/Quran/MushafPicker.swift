import Core
import DesignSystem
import SwiftUI
import UserData

/// Choice of the Mushaf edition (): in onboarding, under Ayarlar and via the button in the Mushaf.
/// The chosen one is loaded, the previous one deleted afterwards; until then the old one stays in use.
struct MushafPicker: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme
    @State private var pack = MushafPack.shared
    /// In onboarding without a title bar and without a Done button.
    var embedded = false

    private var selected: MushafEdition? { MushafEdition(rawValue: settings.mushafEdition) }

    var body: some View {
        if embedded {
            VStack(spacing: 10) {
                ForEach(MushafEdition.allCases) { s in
                    row(s).padding(14)
                        .background(theme.colors.surface, in: .rect(cornerRadius: 14))
                }
            }
            .onAppear { pack.refresh() }
        } else {
            List {
                Section {
                    ForEach(MushafEdition.allCases) { s in row(s) }
                } footer: {
                    Text(app: "mushaf.fassung.aciklama")
                }
            }
            .navigationTitle(localized("mushaf.fassung.baslik"))
            .onAppear { pack.refresh() }
        }
    }

    private func row(_ s: MushafEdition) -> some View {
        Button {
            sec(s)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(app: title(s)).typography(.emphasized).foregroundStyle(theme.colors.text)
                    Text(app: explanation(s)).typography(.secondary).foregroundStyle(theme.colors.text2)
                    statusRow(s)
                }
                Spacer(minLength: 8)
                if selected == s {
                    Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(
                        theme.colors.accent
                    )
                    .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected == s ? .isSelected : [])
    }

    @ViewBuilder private func statusRow(_ s: MushafEdition) -> some View {
        switch pack.status(s) {
        case .ready:
            Label(localized("mushaf.fassung.hazir"), systemImage: "checkmark").typography(.footnote)
                .foregroundStyle(theme.colors.successText)
        case .downloading(let o):
            ProgressView(value: o) {
                Text(app: "mushaf.fassung.iniyor \(Int(o * 100))").typography(.footnote)
            }
            .tint(theme.colors.accent)
        case .failed:
            Label(localized("mushaf.fassung.hata"), systemImage: "exclamationmark.triangle").typography(
                .footnote
            )
            .foregroundStyle(theme.colors.text2)
        case .yok:
            Text(app: "mushaf.fassung.boyut \(s.sizeMB)").typography(.footnote).foregroundStyle(
                theme.colors.text2)
        }
    }

    /// Switch only after loading, so no half page appears on switching; if none is
    /// chosen yet, the choice applies immediately (until the bundle is there, the fallback runs).
    private func sec(_ s: MushafEdition) {
        // Already there: just switch, reload nothing.
        if MushafPack.isReady(s) {
            settings.mushafEdition = s.rawValue
            Task { await pack.download(s) }  // only clears away the others
            return
        }
        if case .downloading = pack.status(s) { return }
        if selected == nil { settings.mushafEdition = s.rawValue }
        Task {
            await pack.download(s)
            if pack.status(s) == .ready { settings.mushafEdition = s.rawValue }
        }
    }

    /// For the row under Ayarlar.
    static func shortName(_ s: MushafEdition) -> LocalizedStringKey {
        switch s {
        case .v1: "mushaf.fassung.kisa.v1"
        case .v2: "mushaf.fassung.kisa.v2"
        case .v4: "mushaf.fassung.kisa.v4"
        }
    }

    private func title(_ s: MushafEdition) -> LocalizedStringKey {
        switch s {
        case .v1: "mushaf.fassung.v1"
        case .v2: "mushaf.fassung.v2"
        case .v4: "mushaf.fassung.v4"
        }
    }

    private func explanation(_ s: MushafEdition) -> LocalizedStringKey {
        switch s {
        case .v1: "mushaf.fassung.v1.aciklama"
        case .v2: "mushaf.fassung.v2.aciklama"
        case .v4: "mushaf.fassung.v4.aciklama"
        }
    }
}
