import ContentPacks
import DesignSystem
import Quran
import SwiftUI
import UserData

/// Okuma ayarları (Q-Aa): preview, three sliders, Okunuş, translations (several at once).
public struct ReadingSettings: View {
    @Environment(\.contentProvider) private var contentProvider
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var close
    @Environment(\.theme) private var theme

    /// German has no Okunuş of its own and no tafsir: choose Turkish or English.
    private func languagePicker(_ title: String.LocalizationValue, _ selection: Binding<String>) -> some View
    {
        Picker(localized(title), selection: selection) {
            Text(app: "ayar.dil.otomatik").tag("")
            Text(verbatim: "Türkçe").tag("tr")
            Text(verbatim: "English").tag("en")
        }
    }

    public init() {}

    public var body: some View {
        @Bindable var a = settings
        NavigationStack {
            Form {
                Section {
                    if let contentProvider, let verse = contentProvider.verse(.verse(surah: 1, verse: 4)) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(
                                settings.tajweedColors
                                    ? tajweedText(
                                        verse.text, spans: contentProvider.tajweed(verse.key),
                                        dark: theme.colors.dark)
                                    : AttributedString(verse.text)
                            )
                            .typography(.arabic(size: settings.arabicSize))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            if settings.showTransliteration,
                                let o = contentProvider.transliteration(
                                    verse.key, language: transliterationLanguage(settings))
                            {
                                Text(verbatim: o.text).font(
                                    .custom(
                                        "Plus Jakarta Sans", size: max(16, settings.transliterationSize),
                                        relativeTo: .body))
                            }
                            if let m = activeTranslations(contentProvider, settings).first,
                                let t = contentProvider.translation(verse.key, pack: m.id)
                            {
                                Text(verbatim: t.text).font(
                                    .custom(
                                        "Plus Jakarta Sans", size: settings.translationSize, relativeTo: .body
                                    )
                                )
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(localized("kuran.onizleme"))
                    }
                }
                Section {
                    sliderRow("kuran.boyut.arapca", $a.arabicSize, 20...56)
                    Toggle(localized("kuran.okunus.goster"), isOn: $a.showTransliteration)
                    if translationLanguage() == "de" {
                        languagePicker("kuran.okunus.dil", $a.transliterationLanguage)
                        languagePicker("kuran.tefsir.dil", $a.tafsirLanguage)
                    }
                    if settings.showTransliteration {
                        sliderRow("kuran.boyut.okunus", $a.transliterationSize, 16...30)
                    }
                    sliderRow("kuran.boyut.meal", $a.translationSize, 12...30)
                    Toggle(isOn: $a.tajweedColors) {
                        Text(app: "kuran.tecvid.goster")
                        Text(app: "kuran.tecvid.mushaf_ayri")
                    }
                    Toggle(localized("kuran.kelime.goster"), isOn: $a.wordByWord)
                    Button(localized("kuran.boyut.sifirla")) { settings.resetReadingSizes() }
                }
                Section {
                    Picker(localized("kuran.kari"), selection: $a.reciter) {
                        // Surah-file reciters only where a plugin delivers their verse timings.
                        ForEach(Reciter.all.filter { $0.fullSurah == nil || SurahTimings.isAvailable() }) {
                            k in
                            Text(verbatim: "\(k.name) · \(k.qiraat ?? k.style)").tag(k.id)
                        }
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(app: "kuran.ses.kaynak")
                        if Reciter.find(settings.reciter).qiraat != nil {
                            Text(app: "kuran.kiraat.farkli")
                        }
                    }
                }
                // Everything about the Quran in one place: Mushaf view and edition.
                Section {
                    Toggle(localized("ayar.mushafta_ac"), isOn: $a.openInMushaf)
                    NavigationLink {
                        MushafPicker()
                    } label: {
                        LabeledContent(localized("mushaf.fassung.baslik")) {
                            Text(app: MushafPicker.shortName(MushafEdition(setting: settings.mushafEdition)))
                        }
                    }
                } header: {
                    Text(app: "kuran.mushaf")
                }
                if settings.tajweedColors {
                    Section {
                        TajweedLegend(rules: TajweedColors.rules)
                    } header: {
                        Text(app: "kuran.tecvid.lejant")
                    }
                }
                if let contentProvider {
                    Section {
                        ForEach(contentProvider.translations()) { m in
                            let selected = activeTranslations(contentProvider, settings).contains(m)
                            Button {
                                var l = activeTranslations(contentProvider, settings).map(\.id)
                                if selected { l.removeAll { $0 == m.id } } else { l.append(m.id) }
                                settings.selectedTranslations = l.isEmpty ? [m.id] : l
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(verbatim: m.title).foregroundStyle(theme.colors.text)
                                        Text(verbatim: "\(m.language.uppercased()) · \(m.source)").typography(
                                            .footnote
                                        )
                                        .foregroundStyle(theme.colors.text2)
                                    }
                                    Spacer()
                                    if selected {
                                        Image(systemName: "checkmark").foregroundStyle(theme.colors.accent)
                                    }
                                }
                            }
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    } header: {
                        Text(app: "kuran.mealler")
                    } footer: {
                        Text(app: "kuran.mealler.alt")
                    }
                }
            }
            .pageBackground()
            .navigationTitle(localized("kuran.okuma_ayarlari"))
            .smallTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(localized("genel.bitti")) { close() } }
            }
        }
    }

    private func sliderRow(
        _ name: String.LocalizationValue, _ value: Binding<Double>, _ interval: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(verbatim: localized(name))
                Spacer()
                Text(verbatim: "\(Int(value.wrappedValue)) pt").monospacedDigit().foregroundStyle(
                    theme.colors.text2)
            }
            Slider(value: value, in: interval, step: 1).accessibilityLabel(localized(name))
        }
    }
}
