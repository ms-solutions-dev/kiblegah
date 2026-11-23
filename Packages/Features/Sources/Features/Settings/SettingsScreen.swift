import ContentPacks
import Core
import DesignSystem
import PrayerTimes
import Quran
import SwiftUI
import UserData

#if os(iOS)
    import UIKit
#endif

/// Ayarlar. Every change takes effect immediately and lives in the App Group;
/// no design names in the UI.
struct SettingsScreen: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.plugins) private var plugins
    @Environment(PrayerTimeModel.self) private var prayerTimes
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var open
    @State private var locationOpen = false
    @State private var readingOpen = false
    @State private var icloudInitial: Bool?

    var body: some View {
        @Bindable var a = settings
        Form {
            Section {
                PalettePicker(palette: $a.palette, locked: a.largeAndSimple)
                AppIconPicker()
                Picker(localized("ayar.gorunum"), selection: $a.appearance) {
                    Text(app: "ayar.gorunum.sistem").tag(Appearance.system)
                    Text(app: "ayar.gorunum.acik").tag(Appearance.light)
                    Text(app: "ayar.gorunum.koyu").tag(Appearance.dark)
                    Text(app: "ayar.gorunum.vakte_gore").tag(Appearance.byPrayerTime)
                }
                Toggle(isOn: $a.largeAndSimple) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app: "ayar.buyuk_sade")
                        Text(app: "ayar.buyuk_sade.alt").typography(.footnote).foregroundStyle(
                            theme.colors.text2)
                    }
                }
                NavigationLink {
                    EditTabsScreen()
                } label: {
                    LabeledContent(
                        localized("ayar.sekmeler"),
                        value: plugins.tabs(settings.tabs).map { localized($0.nameKey) }.joined(
                            separator: ", "))
                }
            } header: {
                Text(app: "ayar.bolum.gorunum")
            }

            Section {
                NavigationLink(value: Goal.notifications) { Text(app: "bildirim.baslik") }
                Button {
                    locationOpen = true
                } label: {
                    LabeledContent(
                        localized("konum.baslik"),
                        value: (settings.automaticLocation ? localized("ayar.konum.otomatik") + " · " : "")
                            + (settings.location?.name ?? "—"))
                }
                .foregroundStyle(theme.colors.text)
                Picker(localized("ayar.vakit_hesabi"), selection: $a.prayerTimeMethod) {
                    Text(app: "ayar.vakit_hesabi.diyanet").tag(PrayerTimeMethod.diyanet)
                    Text(app: "ayar.vakit_hesabi.konum").tag(PrayerTimeMethod.location)
                }
                .onChange(of: settings.prayerTimeMethod) {
                    Task { await prayerTimes.changeCalculation(settings) }
                }
                Picker(localized("ayar.kerahat"), selection: $a.karahatMinutes) {
                    ForEach([30, 40, 45, 50, 60], id: \.self) { d in Text(app: "bildirim.dk.sade \(d)").tag(d)
                    }
                }
            } header: {
                Text(app: "ayar.bolum.vakitler")
            } footer: {
                Text(app: "ayar.vakit_hesabi.alt")
            }
            Section {
                CompassStylePicker(style: $a.compassStyle, sade: a.largeAndSimple)
                Picker(localized("ayar.kible_baslangici"), selection: $a.qiblaStart) {
                    Text(app: "kible.pusula").tag(QiblaStart.compass)
                    Text(app: "kible.harita").tag(QiblaStart.map)
                    Text(app: "ayar.kible_baslangici.son").tag(QiblaStart.lastChoice)
                }
            } header: {
                Text(app: "ayar.bolum.kible")
            } footer: {
                Text(app: "ayar.kible_baslangici.alt")
            }
            SlotView(.settingsAdvanced)

            Section {
                Button {
                    readingOpen = true
                } label: {
                    Text(app: "kuran.okuma_ayarlari")
                }
                NavigationLink(value: Goal.storage) { Text(app: "depolama.baslik") }
                NavigationLink(value: Goal.quizSettings) { Text(app: "sekme.quiz") }
            } header: {
                Text(app: "ayar.bolum.okuma")
            }
            // Sohbet setting and AI conversations, depending on the edition.
            SlotView(.settingsSections)

            Section {
                LanguagePicker()
            } footer: {
                Text(app: "ayar.dil.alt")
            }

            Section {
                Toggle(isOn: $a.iCloud) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app: "ayar.icloud")
                        Text(app: "ayar.icloud.alt").typography(.footnote).foregroundStyle(theme.colors.text2)
                    }
                }
                if let b = icloudInitial, b != settings.iCloud {
                    Text(app: "ayar.icloud.yeniden").typography(.footnote).foregroundStyle(
                        theme.colors.warningText)
                }
                NavigationLink {
                    PrivacyScreen()
                } label: {
                    Text(app: "ayar.gizlilik")
                }
                NavigationLink {
                    SourcesScreen()
                } label: {
                    Text(app: "ayar.kaynaklar")
                }
            } header: {
                Text(app: "ayar.bolum.veriler")
            }

            Section {
                LabeledContent(
                    localized("ayar.surum"),
                    value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
            }
        }
        .pageBackground()
        .navigationTitle(localized("ayarlar.baslik"))
        .sheet(isPresented: $locationOpen) { LocationPickerScreen() }
        .sheet(isPresented: $readingOpen) { ReadingSettings() }
        .onAppear { if icloudInitial == nil { icloudInitial = settings.iCloud } }
        .onChange(of: settings.karahatMinutes) { _, _ in
            Task { await prayerTimes.notification.schedule(table: prayerTimes.table, settings: settings) }
        }
    }
}

extension AppTab {
    var nameKey: String.LocalizationValue {
        switch self {
        case .prayerTimes: "sekme.vakit"
        case .qibla: "sekme.kible"
        case .quran: "sekme.kuran"
        case .duas: "sekme.dualar"
        case .dhikr: "sekme.zikir"
        case .divineNames: "sekme.esma"
        case .hadith: "sekme.hadis"
        case .talks: "sekme.sohbet"
        case .quiz: "sekme.quiz"
        case .discover: "sekme.kesfet"
        }
    }
}

/// Customize tabs: four slots, order by dragging, content from the selection; Keşfet stays fixed.
struct EditTabsScreen: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme
    @Environment(\.plugins) private var plugins

    /// The tabs of this edition (saved order, filtered); Edit saves these.
    private var tabs: [AppTab] { plugins.tabs(settings.tabs) }

    var body: some View {
        List {
            Section {
                ForEach(Array(tabs.enumerated()), id: \.element) { i, s in
                    Menu {
                        ForEach(
                            AppTab.selectable.filter {
                                !tabs.contains($0) && plugins.provides($0)
                            }
                        ) {
                            yeni in
                            Button(localized(yeni.nameKey)) {
                                var l = tabs
                                l[i] = yeni
                                settings.tabs = l
                            }
                        }
                    } label: {
                        Label {
                            Text(app: s.titleKey)
                        } icon: {
                            Image(systemName: s.icon)
                        }
                    }
                }
                .onMove { source, goal in
                    var l = tabs
                    l.move(fromOffsets: source, toOffset: goal)
                    settings.tabs = l
                }
            } footer: {
                Text(app: "ayar.sekmeler.alt")
            }
            Section {
                Button(localized("ayar.sekmeler.sifirla")) { settings.tabs = AppTab.standard }
            }
        }
        #if os(iOS)
            .environment(\.editMode, .constant(.active))
        #endif
        .pageBackground()
        .navigationTitle(localized("ayar.sekmeler"))
    }
}

/// Gizlilik with precise sentences.
struct PrivacyScreen: View {
    @Environment(\.theme) private var theme

    var body: some View {
        List {
            ForEach(
                [
                    "gizlilik.reklam", "gizlilik.konum", "gizlilik.harita", "gizlilik.ses",
                    "gizlilik.icloud", "gizlilik.bildirim",
                ], id: \.self
            ) { k in
                Text(verbatim: AppLanguage.bundle.localizedString(forKey: k, value: nil, table: nil))
                    .typography(
                        .body)
            }
        }
        .pageBackground()
        .navigationTitle(localized("ayar.gizlilik"))
    }
}

/// Kaynaklar ve lisanslar: every package with source, license and version, plus fonts and sounds.
struct SourcesScreen: View {
    @Environment(\.contentProvider) private var contentProvider
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var open

    var body: some View {
        List {
            Section {
                ForEach(contentProvider?.packs ?? []) { p in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: p.title).typography(.emphasized)
                        Text(verbatim: p.source).typography(.secondary)
                        Text(verbatim: "\(p.license) · \(p.version)").typography(.footnote).foregroundStyle(
                            theme.colors.text2)
                        if p.unreviewed {
                            Text(app: "kaynak.ungeprueft").typography(.footnote).foregroundStyle(
                                theme.colors.warningText)
                        }
                        if let u = p.sourceURL {
                            Button(u.host() ?? u.absoluteString) { open(u) }.typography(.footnote)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text(app: "kaynak.paketler")
            }
            Section {
                Text(
                    verbatim:
                        "Kâri: \(Reciter.source) – \(Reciter.all.map(\.name).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.joined(separator: ", "))"
                )
                Text(app: "kuran.kelime.kaynak")
                Text(app: "kaynak.ezan")
                Text(app: "kaynak.yazi")
                Text(app: "kaynak.vakit")
            } header: {
                Text(app: "kaynak.diger")
            }
            .typography(.secondary)
        }
        .pageBackground()
        .navigationTitle(localized("ayar.kaynaklar"))
    }
}

/// Color scheme as color dots without names (variant 12 B, A17): background and accent per dot, like the
/// accent colors in iOS. No internal design name in the UI; VoiceOver reads a
/// description of the colors. Stays single-line, also in „Büyük ve sade“ – disabled there because
/// Sakin dictates the color scheme, and the hint below says so.
struct PalettePicker: View {
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Binding var palette: Palette
    let locked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(app: "ayar.palet")
            HStack(spacing: 0) {
                ForEach(Palette.allCases, id: \.self) { p in
                    point(p).frame(maxWidth: .infinity)
                }
            }
            .opacity(locked ? 0.45 : 1)
            .disabled(locked)
            if locked {
                Text(app: "ayar.palet.sade").typography(.footnote).foregroundStyle(theme.colors.text2)
            }
        }
        .padding(.vertical, 4)
    }

    private func point(_ p: Palette) -> some View {
        let selected = palette == p
        let r = PalettePicker.colors(p, dark: theme.colors.dark)
        let cap: CGFloat = typeSize.isAccessibilitySize ? 52 : 44
        return Button {
            palette = p
        } label: {
            Circle()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: r.background, location: 0.5), .init(color: r.accent, location: 0.5),
                        ], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(Circle().strokeBorder(r.line, lineWidth: 1))
                .frame(width: cap, height: cap)
                .padding(4)
                .overlay(Circle().strokeBorder(selected ? theme.colors.accent : .clear, lineWidth: 2.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localized(key: "ayar.palet.erisim.\(p.rawValue)"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Preview colors of a palette in the currently active scheme: in dark mode the Koyu variant,
    /// otherwise the dots show light color schemes that you cannot actually get.
    static func colors(_ p: Palette, dark: Bool) -> ColorTokens {
        switch p {
        case .dawn: dark ? .dawnDark : .dawnLight
        case .sky: dark ? .skyDark : .skyLight
        case .ornament: dark ? .ornamentDark : .ornamentLight
        case .emerald: dark ? .emeraldDark : .emeraldLight
        case .night: dark ? .nightDark : .nightLight
        case .rose: dark ? .roseDark : .roseLight
        }
    }
}

/// Language of the app, independent of the iPhone language; each language in its own spelling.
struct LanguagePicker: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var a = settings
        Picker(localized("ayar.dil"), selection: $a.language) {
            Text(app: "ayar.dil.sistem").tag("")
            Text(verbatim: "Türkçe").tag("tr")
            Text(verbatim: "Deutsch").tag("de")
            Text(verbatim: "English").tag("en")
        }
    }
}
