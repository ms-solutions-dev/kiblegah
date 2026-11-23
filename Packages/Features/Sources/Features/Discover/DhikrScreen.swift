import ContentPacks
import DesignSystem
import Duas
import SwiftUI
import UserData

/// Zikirmatik: large counting surface away from the tab bar, Tasbihat advances
/// automatically, −1, Sıfırla only with confirmation and 5 s „Geri al“.
struct DhikrScreen: View {
    @Environment(UserStore.self) private var store
    @Environment(\.contentProvider) private var contentProvider
    @Environment(\.theme) private var theme
    /// From the Esmâ page: the name as dhikr, round of 33.
    var divineName: Int?
    @State private var selection = "tesbihat"
    @State private var counter = DhikrCounter(index: Dhikr.tasbihat)
    @State private var resetAsk = false
    @State private var undoTarget: DhikrCounter?
    @State private var tick = 0
    @State private var roundEnd = 0

    var body: some View {
        let _ = store.version
        VStack(spacing: 16) {
            Text(app: "zikir.ozet \(store.dhikrTotal(days: 1)) \(store.dhikrTotal(days: 7))")
                .typography(.secondary).foregroundStyle(theme.colors.text2)
            if divineName == nil {
                Picker(localized("zikir.sec"), selection: $selection) {
                    Text(app: "zikir.tesbihat").tag("tesbihat")
                    ForEach(Dhikr.others) { z in
                        Text(verbatim: z.transliteration.text(translationLanguage())).tag(z.id)
                    }
                    Text(app: "zikir.serbest").tag("serbest")
                }
                .pickerStyle(.menu)
            }
            tally
            HStack(spacing: 12) {
                Button {
                    counter.undo()
                    store.addDhikr(dhikrID, -1)
                } label: {
                    Text(verbatim: "−1").frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButton())
                .accessibilityLabel(localized("zikir.geri_bir"))
                Button(localized("zikir.sifirla")) { resetAsk = true }
                    .buttonStyle(SecondaryButton())
            }
            if undoTarget != nil {
                Button(localized("zikir.geri_al")) {
                    if let g = undoTarget { counter = g }
                    undoTarget = nil
                }
                .buttonStyle(PrimaryButton())
                .task {
                    try? await Task.sleep(for: .seconds(5))
                    undoTarget = nil
                }
            }
        }
        .padding(20)
        .pageBackground()
        .navigationTitle(localized("sekme.zikir"))
        .smallTitle()
        .confirmationDialog(
            localized("zikir.sifirla.soru"), isPresented: $resetAsk, titleVisibility: .visible
        ) {
            Button(localized("zikir.sifirla"), role: .destructive) {
                undoTarget = counter
                counter.reset()
            }
        }
        .onChange(of: selection) { _, yeni in counter = DhikrCounter(index: index(yeni)) }
        .onAppear { if divineName != nil { counter = DhikrCounter(index: index("esma")) } }
        .sensoryFeedback(.impact(weight: .light), trigger: tick)
        .sensoryFeedback(.success, trigger: roundEnd)
    }

    private var dhikrID: String { divineName.map { "e:\($0)" } ?? (counter.dhikr?.id ?? "serbest") }

    private func index(_ id: String) -> [Dhikr] {
        if let divineName, let e = contentProvider?.divineNames().first(where: { $0.number == divineName }) {
            // ed-Dârr is never called on alone, only together with en-Nâfi‘ (DivineName.namedWithPartner).
            let all = [e] + (e.partner.map { [$0] } ?? [])
            func joined(_ part: (DivineName) -> String?) -> String {
                all.compactMap(part).filter { !$0.isEmpty }.joined(separator: " · ")
            }
            return [
                Dhikr(
                    id: "e:\(divineName)", arabic: all.map(\.arabic).joined(separator: " "),
                    transliteration: Multilingual(
                        tr: joined { $0.transliterationTR ?? $0.latin }, de: joined { $0.latin },
                        en: joined { $0.latin }),
                    meaning: Multilingual(
                        tr: joined(\.meaningTR), de: joined(\.meaningDE), en: joined(\.meaningEN)),
                    goal: 33)
            ]
        }
        switch id {
        case "tesbihat": return Dhikr.tasbihat
        case "serbest": return []
        default: return Dhikr.find(id).map { [$0] } ?? []
        }
    }

    /// The counting surface: whole field tappable, VoiceOver with Direct Touch and value.
    private var tally: some View {
        let z = counter.dhikr
        let value: String = {
            if let h = counter.goal { return localized("zikir.deger \(counter.number) \(h) \(counter.kind)") }
            return "\(counter.number)"
        }()
        return Button {
            let event = counter.count()
            store.addDhikr(dhikrID)
            tick += 1
            if event != .counted {
                roundEnd += 1
                let announcement =
                    event == .tasbihatFinished
                    ? localized("zikir.tesbihat_tamam") : localized("zikir.tur_bitti")
                AccessibilityNotification.Announcement(announcement).post()
            }
        } label: {
            VStack(spacing: 12) {
                if let z {
                    Text(verbatim: z.arabic).typography(.arabic(size: 34)).multilineTextAlignment(.center)
                    Text(verbatim: z.transliteration.text(translationLanguage())).typography(.emphasized)
                    Text(verbatim: z.meaning.text(translationLanguage())).typography(.secondary)
                        .foregroundStyle(
                            theme.colors.text2
                        )
                        .multilineTextAlignment(.center)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: "\(counter.number)").font(
                        .system(size: 88, weight: .semibold, design: .rounded)
                    )
                    .monospacedDigit()
                    if let h = counter.goal {
                        Text(verbatim: "/ \(h)").typography(.title2).foregroundStyle(theme.colors.text2)
                    }
                }
                if counter.goal != nil {
                    Text(app: "zikir.tur \(counter.kind)").typography(.footnote).foregroundStyle(
                        theme.colors.text2)
                }
                Text(app: "zikir.ipucu").typography(.footnote).foregroundStyle(theme.colors.text2)
            }
            .foregroundStyle(theme.colors.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
            .background(theme.colors.surface, in: .rect(cornerRadius: 28))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(z?.transliteration.text(translationLanguage()) ?? localized("zikir.serbest"))
        .accessibilityValue(value)
        .accessibilityAddTraits(.allowsDirectInteraction)
    }
}
