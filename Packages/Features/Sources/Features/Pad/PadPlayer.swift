import ContentPacks
import Core
import DesignSystem
import Quran
import SwiftUI
import UserData

/// The player over the whole app (board G12): nothing while nothing plays, a capsule while something does, and
/// from the capsule the expanded panel with everything of the iPhone bar. It stays when the area changes.
struct PadPlayerBar: View {
    @Environment(RecitationPlayer.self) private var player
    @Environment(\.contentProvider) private var contentProvider
    @Environment(\.theme) private var theme
    /// Capsule width; the reader column passes `nil` and fills its width.
    var width: CGFloat? = 500
    /// In the book's bottom row: no skipping in the capsule (the panel has it).
    var compact = false
    @State private var expanded = false

    private var failed: Bool { player.zamanYok || player.offlineError }

    var body: some View {
        if let current = player.current {
            HStack(spacing: 8) {
                if !compact {
                    button("backward.end.fill", size: 46, label: "kuran.oynatici.onceki") {
                        player.previous()
                    }
                }
                Button {
                    player.togglePause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(theme.colors.onAccent)
                        .frame(width: 54, height: 54)
                        .background(theme.colors.accent, in: .circle)
                        .shadow(color: theme.colors.accent.opacity(0.4), radius: 8, y: 6)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    localized(player.isPlaying ? "kuran.oynatici.duraklat" : "kuran.oynatici.oynat"))
                if !compact {
                    button("forward.end.fill", size: 46, label: "kuran.oynatici.sonraki") { player.next() }
                }
                Button {
                    expanded = true
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: title(current)).typography(.label(size: 15)).lineLimit(1)
                            .contentTransition(.numericText())
                        progress
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 6)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint(localized("ipad.player.erweitern"))
                Button {
                    expanded = true
                } label: {
                    Image(systemName: "chevron.up").font(.system(size: 15, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(theme.colors.surface2, in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(localized("ipad.player.erweitern"))
                .popover(isPresented: $expanded, arrowEdge: .bottom) {
                    PadPlayerPanel()
                }
            }
            .foregroundStyle(theme.colors.text)
            .padding(.leading, 10).padding(.trailing, 14).padding(.vertical, 10)
            .frame(maxWidth: width ?? .infinity)
            .glassEffect(.regular, in: .capsule)
            .overlay {
                if failed {
                    Capsule().strokeBorder(theme.colors.warningText, lineWidth: 1.5)
                }
            }
            .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
            .padding(.horizontal, compact ? 0 : 16)
            .padding(.bottom, compact ? 0 : 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func title(_ s: RecitationPlayer.QueueItem) -> String {
        let surah = contentProvider?.surah(s.surah)?.name(language: translationLanguage()) ?? "\(s.surah)"
        return s.basmala
            ? "\(surah) · \(localized("kuran.besmele"))"
            : "\(surah) · \(localized("kuran.oynatici.ayet \(s.verse)"))"
    }

    /// How far the queue is, as a thin line.
    private var progress: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.colors.surface2)
                Capsule().fill(theme.colors.accent)
                    .frame(width: max(6, g.size.width * ratio))
                    .animation(.linear(duration: 0.6), value: ratio)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }

    private var ratio: Double {
        player.queue.count > 1 ? Double(player.location + 1) / Double(player.queue.count) : 1
    }

    private func button(
        _ symbol: String, size: CGFloat, label: String.LocalizationValue, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 18))
                .frame(width: size, height: size)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localized(label))
    }
}

/// The idle capsule of the Quran columns: „Al-Baqara hören“ opens the reading options (boards G07, G21).
struct PadListenCapsule: View {
    @Environment(\.theme) private var theme
    let title: String
    var width: CGFloat? = nil
    /// `false`: without the margins of a column (book controls).
    var framed = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "play.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(theme.colors.onAccent)
                    .frame(width: 54, height: 54)
                    .background(theme.colors.accent, in: .circle)
                    .shadow(color: theme.colors.accent.opacity(0.4), radius: 8, y: 6)
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: title).typography(.label(size: 14)).foregroundStyle(theme.colors.text)
                    Capsule().fill(theme.colors.surface2).frame(height: 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.up").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.colors.text)
                    .frame(width: 44, height: 44)
                    .background(theme.colors.surface2, in: .circle)
            }
            .padding(.leading, 10).padding(.trailing, 14).padding(.vertical, 10)
            .frame(maxWidth: width ?? .infinity)
            .glassEffect(.regular, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        .padding(.horizontal, framed ? 16 : 0)
        .padding(.bottom, framed ? 8 : 0)
    }
}

/// Everything the iPhone bar offers, in one panel: reciter, repeat, range, pause, tempo, where it ends, the
/// download state, and stop. Errors stay visible, the player stays usable.
struct PadPlayerPanel: View {
    @Environment(RecitationPlayer.self) private var player
    @Environment(AudioStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.contentProvider) private var contentProvider
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(app: "ipad.player.hoeren").typography(.display(size: 20))
                Spacer()
                status
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down").frame(width: 44, height: 44)
                        .background(theme.colors.surface2, in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(localized("genel.kapat"))
            }
            if player.zamanYok || player.offlineError {
                Text(app: player.zamanYok ? "kuran.oynatici.zaman_yok" : "kuran.oynatici.ulasilamadi")
                    .typography(.secondary).foregroundStyle(theme.colors.warningText)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.colors.warningBackground, in: .rect(cornerRadius: 16))
            }
            eyebrow("kuran.kari")
            Menu {
                ForEach(Reciter.all.filter { $0.fullSurah == nil || SurahTimings.isAvailable() }) { k in
                    Button("\(k.name) · \(k.qiraat ?? k.style)") {
                        settings.reciter = k.id
                        player.reciter = k
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(verbatim: player.reciter.name).typography(.label(size: 14))
                    Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 16).frame(minHeight: 44)
                .foregroundStyle(theme.colors.onAccent)
                .background(theme.colors.accent, in: .capsule)
            }
            .accessibilityLabel(localized("kuran.kari"))
            if !theme.largeAndSimple {
                eyebrow("kuran.oynatici.tekrar")
                chips([1, 3, 5, 10], selection: player.repetition, text: repeatText) {
                    player.repetition = $0
                }
                eyebrow("kuran.oynatici.aralik")
                chips([1, 2, 3, 5, 10], selection: player.rangeRepeat, text: repeatText) {
                    player.rangeRepeat = $0
                }
                eyebrow("kuran.oynatici.bekleme")
                chips([0.0, 2, 5, 10], selection: player.delay, text: pauseText) { player.delay = $0 }
                eyebrow("kuran.oynatici.hiz")
                chips([Float(0.75), 1, 1.25, 1.5], selection: player.speed, text: { "\($0.formatted())×" }) {
                    player.speed = $0
                }
            }
            if let end = endText {
                Text(verbatim: end).typography(.secondary).foregroundStyle(theme.colors.text2)
            }
            HStack(spacing: 6) {
                panelButton("backward.end.fill", "kuran.oynatici.onceki") { player.previous() }
                panelButton("forward.end.fill", "kuran.oynatici.sonraki") { player.next() }
                Button {
                    player.stop()
                    dismiss()
                } label: {
                    Label(localized("ipad.player.stopp"), systemImage: "stop.fill")
                        .typography(.label(size: 14))
                        .padding(.horizontal, 16).frame(minHeight: 44)
                        .background(theme.colors.surface2, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .frame(width: 500)
        .foregroundStyle(theme.colors.text)
        .presentationCompactAdaptation(.popover)
    }

    private func panelButton(
        _ symbol: String, _ label: String.LocalizationValue, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 44, height: 44)
                .background(theme.colors.surface2, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localized(label))
    }

    private func repeatText(_ n: Int) -> String { n == 1 ? localized("kuran.oynatici.tekrar.yok") : "\(n)×" }
    private func pauseText(_ n: Double) -> String {
        n == 0 ? localized("kuran.oynatici.bekleme.yok") : localized("kuran.oynatici.saniye \(Int(n))")
    }

    private func eyebrow(_ key: String.LocalizationValue) -> some View {
        Text(verbatim: localized(key)).typography(.label(size: 13)).textCase(.uppercase).tracking(1.1)
            .foregroundStyle(theme.colors.label)
    }

    private func chips<T: Hashable>(
        _ values: [T], selection: T, text: @escaping (T) -> String, pick: @escaping (T) -> Void
    ) -> some View {
        HStack(spacing: 6) {
            ForEach(values, id: \.self) { v in
                Button {
                    pick(v)
                } label: {
                    Text(verbatim: text(v)).typography(.label(size: 14))
                        .padding(.horizontal, 16).frame(minHeight: 44)
                        .foregroundStyle(v == selection ? theme.colors.onAccent : theme.colors.text2)
                        .background(
                            v == selection ? theme.colors.accent : theme.colors.surface2, in: .capsule
                        )
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(v == selection ? .isSelected : [])
            }
        }
    }

    /// „bis 2:5 · Seitenende 48“, as on the iPhone.
    private var endText: String? {
        guard player.queue.count > 1, let last = player.queue.last else { return nil }
        var end = localized("kuran.oynatici.bitis \("\(last.surah):\(last.verse)")")
        if let contentProvider, let a = contentProvider.verse(.verse(surah: last.surah, verse: last.verse)),
            contentProvider.page(a.page)?.lastIndex == a.index
        {
            end += " · " + localized("kuran.oynatici.sayfa_sonu \(a.page)")
        }
        return end
    }

    @ViewBuilder private var status: some View {
        if let s = player.current, let su = contentProvider?.surah(s.surah) {
            switch store.status(player.reciter, surah: s.surah, verseCount: su.verseCount) {
            case .ready:
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(theme.colors.sage)
                    .accessibilityLabel(localized("kuran.ses.indirildi"))
            case .downloading(let p):
                ProgressView(value: p).frame(width: 40).accessibilityLabel(localized("kuran.ses.iniyor"))
            case .yok:
                Image(systemName: "icloud").foregroundStyle(theme.colors.text2)
                    .accessibilityLabel(localized("kuran.ses.cevrimici"))
            }
        }
    }
}
