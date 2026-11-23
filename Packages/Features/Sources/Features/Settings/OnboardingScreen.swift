import Core
import DesignSystem
import SwiftUI
import UserData

#if os(iOS)
    import UIKit
#endif

/// First launch: welcome with language and „Büyük ve sade“,
/// then one explanatory screen each before the system prompt for location and notifications. Every step
/// can be skipped; without permission the city search remains.
struct OnboardingScreen: View {
    enum Step { case welcome, location, notification, mushaf }

    @Environment(AppSettings.self) private var settings
    @Environment(PrayerTimeModel.self) private var prayerTimes
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var open
    @State private var step: Step = .welcome
    @State private var pickCity = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch step {
                case .welcome: welcome
                case .location: location
                case .notification: notification
                case .mushaf: mushaf
                }
            }
            .padding(24)
            .padding(.top, 24)
        }
        .pageBackground()
        .sheet(isPresented: $pickCity, onDismiss: { if settings.location != nil { step = .notification } }) {
            LocationPickerScreen()
        }
        .interactiveDismissDisabled()
    }

    private var welcome: some View {
        @Bindable var a = settings
        return VStack(alignment: .leading, spacing: 20) {
            Text(verbatim: "Kıblegâh").typography(.accent)
            Text(app: "onboarding.slogan").typography(.title2).foregroundStyle(theme.colors.text2)
            // Choose the language right here, without the iPhone settings.
            Menu {
                Picker(localized("ayar.dil"), selection: $a.language) {
                    Text(app: "ayar.dil.sistem").tag("")
                    Text(verbatim: "Türkçe").tag("tr")
                    Text(verbatim: "Deutsch").tag("de")
                    Text(verbatim: "English").tag("en")
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "DİL · SPRACHE · LANGUAGE").typography(.footnote).foregroundStyle(
                            theme.colors.label)
                        Text(
                            verbatim: AppLanguage.locale.localizedString(
                                forLanguageCode: translationLanguage())?
                                .capitalized
                                ?? translationLanguage()
                        )
                        .typography(.emphasized)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").accessibilityHidden(true)
                }
                .padding(16)
                .frame(minHeight: 56)
                .background(theme.colors.surface, in: .rect(cornerRadius: 18))
            }
            .foregroundStyle(theme.colors.text)
            promise("onboarding.reklam", "onboarding.reklam.alt", "hand.raised")
            promise("onboarding.veri", "onboarding.veri.alt", "lock")
            promise("onboarding.diyanet", "onboarding.diyanet.alt", "clock")
            Toggle(isOn: $a.largeAndSimple) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(app: "ayar.buyuk_sade").typography(.emphasized)
                    Text(app: "onboarding.sade.alt").typography(.footnote).foregroundStyle(theme.colors.text2)
                }
            }
            .padding(16)
            .background(theme.colors.surface, in: .rect(cornerRadius: 18))
            Button(localized("onboarding.basla")) { step = .location }.buttonStyle(PrimaryButton())
            Text(app: "onboarding.basla.alt").typography(.footnote).foregroundStyle(theme.colors.text2)
        }
    }

    private func promise(
        _ title: LocalizedStringKey, _ bottom: LocalizedStringKey, _ icon: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(theme.colors.sage).frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(app: title).typography(.emphasized)
                Text(app: bottom).typography(.secondary).foregroundStyle(theme.colors.text2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var location: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "location.circle").font(.system(size: 56)).foregroundStyle(theme.colors.accent)
                .accessibilityHidden(true)
            Text(app: "onboarding.konum.baslik").typography(.title1)
            Text(app: "onboarding.konum.aciklama").typography(.body)
            Text(app: "gizlilik.konum").typography(.secondary).foregroundStyle(theme.colors.text2)
            Button(localized("konum.kullan")) {
                Task {
                    settings.automaticLocation = true
                    await prayerTimes.checkLocation(settings)
                    step = .notification
                }
            }
            .buttonStyle(PrimaryButton())
            Button(localized("onboarding.konum.elle")) { pickCity = true }.buttonStyle(SecondaryButton())
            Button(localized("onboarding.sonra")) { step = .notification }
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    private var notification: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "bell.badge").font(.system(size: 56)).foregroundStyle(theme.colors.accent)
                .accessibilityHidden(true)
            Text(app: "onboarding.bildirim.baslik").typography(.title1)
            Text(app: "onboarding.bildirim.aciklama").typography(.body)
            Text(app: "gizlilik.bildirim").typography(.secondary).foregroundStyle(theme.colors.text2)
            Button(localized("bildirim.izin_ver")) {
                Task {
                    await prayerTimes.notification.requestPermission()
                    await prayerTimes.notification.schedule(table: prayerTimes.table, settings: settings)
                    step = .mushaf
                }
            }
            .buttonStyle(PrimaryButton())
            Button(localized("onboarding.sonra")) { step = .mushaf }
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    /// Mushaf edition right during setup (): There is network during installation, afterwards the
    /// Mushaf reads offline. Loading continues even if the user moves on.
    private var mushaf: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "book.closed").font(.system(size: 56)).foregroundStyle(theme.colors.accent)
                .accessibilityHidden(true)
            Text(app: "onboarding.mushaf.baslik").typography(.title1)
            Text(app: "onboarding.mushaf.aciklama").typography(.body)
            MushafPicker(embedded: true)
            Button(localized("onboarding.devam")) {
                if settings.mushafEdition.isEmpty {
                    settings.mushafEdition = MushafEdition.v1.rawValue
                    Task { await MushafPack.shared.download(.v1) }
                }
                bitir()
            }
            .buttonStyle(PrimaryButton())
        }
    }

    private func bitir() {
        settings.onboardingDone = true
        Task { await prayerTimes.start(settings) }
    }
}
