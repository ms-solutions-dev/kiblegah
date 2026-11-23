import DesignSystem
import PrayerTimes
import SwiftUI
import UserData

#if os(iOS)
    import Photos
#endif

#if os(iOS)
    import UIKit
#endif

/// Share sheet (variant 07, all three): preview of the card, style „Renk“ or „Gökyüzü“,
/// base color, meaning and place on/off; share as image, save, or as text only.
///
/// Open via ``ShareButton`` or `.paylasBlati($kart)`. The choice is kept in the
/// user defaults so the next card looks the same.
public struct ShareSheet: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PrayerTimeModel.self) private var prayerTimeModel
    @Environment(\.dismiss) private var close
    @Environment(\.theme) private var theme
    let card: ShareCard
    @State private var selection = ShareOptions(defaults: .standard)
    @State private var render: Image?
    @State private var didSave = false
    @State private var saveFailed = false

    public init(card: ShareCard) { self.card = card }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    previewName
                    options
                    buttons
                }
                .padding(16)
            }
            .pageBackground()
            .navigationTitle(localized("kuran.paylas"))
            .smallTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(localized("genel.kapat")) { close() } }
            }
        }
        .onChange(of: selection) { _, yeni in yeni.save(.standard) }
        .task(id: selection) { draw() }
    }

    private var prayerTimes: SkyPhase { skyPhase(prayerTimeModel.table) }

    private var previewName: some View {
        let s = ShareCardView.size
        return GeometryReader { g in
            let scale = min(g.size.width / s.width, 1)
            ShareCardView(
                card: card, selection: selection, prayerTimes: prayerTimes, placeName: settings.location?.name
            )
            .clipShape(.rect(cornerRadius: 16 / scale))
            .scaleEffect(scale, anchor: .top)
            .frame(width: g.size.width, alignment: .top)
            .shadow(color: .black.opacity(0.4), radius: 14, y: 8)
        }
        .aspectRatio(s.width / s.height, contentMode: .fit)
        .frame(maxWidth: 300)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localized("paylas.onizleme"))
        .accessibilityValue(card.text(showMeaning: selection.showMeaning, showPlace: selection.showPlace))
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker(localized("paylas.stil"), selection: $selection.style) {
                Text(app: "paylas.stil.renk").tag(ShareStyle.color)
                Text(app: "paylas.stil.gok").tag(ShareStyle.sky)
            }
            .pickerStyle(.segmented)
            if selection.style == .color {
                HStack(spacing: 16) {
                    ForEach(CardColor.allCases, id: \.self) { r in colorDot(r) }
                }
                .frame(maxWidth: .infinity)
            } else {
                Text(app: "paylas.gok.aciklama").typography(.footnote).foregroundStyle(theme.colors.text2)
            }
            if card.meaningHideable {
                Toggle(
                    localized(card.kind == .verse ? "paylas.meal" : "paylas.anlam"),
                    isOn: $selection.showMeaning)
            }
            if card.kind == .qibla || selection.style == .sky {
                Toggle(isOn: $selection.showPlace) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app: "paylas.yer")
                        Text(app: "paylas.yer.alt").typography(.footnote).foregroundStyle(theme.colors.text2)
                    }
                }
            }
        }
        .padding(14)
        .background(theme.colors.surface, in: .rect(cornerRadius: 16))
    }

    private func colorDot(_ r: CardColor) -> some View {
        let selected = selection.color == r
        return Button {
            selection.color = r
        } label: {
            Circle().fill(r.background).frame(width: 36, height: 36)
                .overlay(Circle().strokeBorder(r.text.opacity(0.35), lineWidth: 1))
                .padding(4)
                .overlay(Circle().strokeBorder(selected ? theme.colors.text : .clear, lineWidth: 2.5))
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localized(key: "paylas.renk.\(r.rawValue)"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var buttons: some View {
        let text = card.text(showMeaning: selection.showMeaning, showPlace: selection.showPlace)
        VStack(spacing: 10) {
            if let render {
                ShareLink(
                    item: render, message: Text(verbatim: text),
                    preview: SharePreview(card.parent, image: render)
                ) {
                    Label(localized("paylas.resim"), systemImage: "square.and.arrow.up").frame(
                        maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButton())
            }
            HStack(spacing: 10) {
                #if os(iOS)
                    Button {
                        save()
                    } label: {
                        Label(
                            localized(didSave ? "paylas.kaydedildi" : "paylas.kaydet"),
                            systemImage: didSave ? "checkmark" : "square.and.arrow.down"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButton())
                    .disabled(render == nil)
                #endif
                ShareLink(item: text) {
                    Label(localized("paylas.metin"), systemImage: "text.quote").frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButton())
            }
            if saveFailed {
                Text(app: "paylas.kaydet.hata").typography(.footnote).foregroundStyle(
                    theme.colors.warningText)
            }
        }
    }

    private func draw() {
        didSave = false
        saveFailed = false
        guard
            let cg = ShareCardView.render(
                card, selection: selection, prayerTimes: prayerTimes, placeName: settings.location?.name)
        else { return }
        render = Image(decorative: cg, scale: 1)
    }

    #if os(iOS)
        private func save() {
            guard
                let cg = ShareCardView.render(
                    card, selection: selection, prayerTimes: prayerTimes, placeName: settings.location?.name)
            else { return }
            // With feedback instead of UIImageWriteToSavedPhotosAlbum: without permission,
            // „saved“ must not appear.
            let render = UIImage(cgImage: cg)
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: render)
            } completionHandler: { done, _ in
                Task { @MainActor in
                    didSave = done
                    saveFailed = !done
                    AccessibilityNotification.Announcement(
                        localized(done ? "paylas.kaydedildi" : "paylas.kaydet.hata")
                    )
                    .post()
                }
            }
        }
    #endif
}

/// The sky at the time of day: the currently running prayer time, estimated from the hour when there is no table.
func skyPhase(_ table: PrayerTimeTable?, time: Date = .now) -> SkyPhase {
    if let table, let d = PrayerTimeStatus(table: table, time: time),
        let g = SkyPhase(rawValue: d.current.rawValue)
    {
        return g
    }
    return switch Calendar.current.component(.hour, from: time) {
    case 4..<6: .imsak
    case 6..<9: .sunrise
    case 9..<15: .dhuhr
    case 15..<18: .asr
    case 18..<20: .maghrib
    default: .isha
    }
}

/// Share button: opens the sheet for a card. `labeled` shows „Paylaş“ with text (for
/// button rows), otherwise only the symbol (toolbar).
public struct ShareButton: View {
    let card: ShareCard
    let labeled: Bool
    @State private var light: ShareCard?

    public init(_ card: ShareCard, labeled: Bool = false) {
        self.card = card
        self.labeled = labeled
    }

    public var body: some View {
        Button {
            light = card
        } label: {
            if labeled {
                Label(localized("kuran.paylas"), systemImage: "square.and.arrow.up").frame(
                    maxWidth: .infinity)
            } else {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .accessibilityLabel(localized("kuran.paylas"))
        .shareSheet($light)
    }
}

extension View {
    /// Shows the share sheet as soon as `card` is set; closing resets it.
    public func shareSheet(_ card: Binding<ShareCard?>) -> some View {
        sheet(item: card) { k in
            ShareSheet(card: k).presentationDetents([.large])
        }
    }
}
