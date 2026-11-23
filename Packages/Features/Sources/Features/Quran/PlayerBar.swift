import ContentPacks
import DesignSystem
import Quran
import SwiftUI
import UserData

/// Player bar below the reader (Q-Okuyucu): ‹ ⏯ ›, repeat, tempo, reciter.
/// Sits as a safety margin at the bottom so it does not cover a verse.
struct PlayerBar: View {
    @Environment(RecitationPlayer.self) private var player
    @Environment(AudioStore.self) private var store
    @Environment(\.contentProvider) private var contentProvider
    @Environment(\.theme) private var theme
    @Environment(AppSettings.self) private var settings

    /// Reader and, with more than one verse, where playback stops; if it ends at a page end,
    /// the page is shown with it.
    private var bottomRow: String {
        guard player.queue.count > 1, let last = player.queue.last else { return player.reciter.name }
        var end = localized("kuran.oynatici.bitis \("\(last.surah):\(last.verse)")")
        if let contentProvider, let a = contentProvider.verse(.verse(surah: last.surah, verse: last.verse)),
            contentProvider.page(a.page)?.lastIndex == a.index
        {
            end += " · " + localized("kuran.oynatici.sayfa_sonu \(a.page)")
        }
        return player.reciter.name + " · " + end
    }

    var body: some View {
        if let s = player.current {
            VStack(spacing: 6) {
                if player.zamanYok || player.offlineError {
                    Text(app: player.zamanYok ? "kuran.oynatici.zaman_yok" : "kuran.oynatici.ulasilamadi")
                        .typography(.footnote).foregroundStyle(theme.colors.warningText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            verbatim: s.basmala
                                ? localized("kuran.besmele") : localized("kuran.oynatici.ayet \(s.verse)")
                        )
                        .typography(.emphasized)
                        Text(verbatim: bottomRow).typography(.footnote).foregroundStyle(theme.colors.text2)
                    }
                    Spacer()
                    status(s)
                    Button {
                        player.stop()
                    } label: {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(localized("genel.kapat"))
                }
                HStack(spacing: 4) {
                    Menu {
                        Picker(
                            localized("kuran.oynatici.tekrar"),
                            selection: Binding(
                                get: { player.repetition }, set: { player.repetition = $0 })
                        ) {
                            ForEach([1, 3, 5, 10], id: \.self) { n in
                                Text(verbatim: n == 1 ? localized("kuran.oynatici.tekrar.yok") : "\(n)×").tag(
                                    n)
                            }
                        }
                        Picker(
                            localized("kuran.oynatici.aralik"),
                            selection: Binding(
                                get: { player.rangeRepeat }, set: { player.rangeRepeat = $0 })
                        ) {
                            ForEach([1, 2, 3, 5, 10], id: \.self) { n in
                                Text(verbatim: n == 1 ? localized("kuran.oynatici.tekrar.yok") : "\(n)×").tag(
                                    n)
                            }
                        }
                        Picker(
                            localized("kuran.oynatici.bekleme"),
                            selection: Binding(get: { player.delay }, set: { player.delay = $0 })
                        ) {
                            ForEach([0.0, 2, 5, 10], id: \.self) { n in
                                Text(
                                    verbatim: n == 0
                                        ? localized("kuran.oynatici.bekleme.yok")
                                        : localized("kuran.oynatici.saniye \(Int(n))")
                                )
                                .tag(n)
                            }
                        }
                    } label: {
                        Image(
                            systemName: player.repetition > 1 || player.rangeRepeat > 1
                                || player.delay > 0 ? "repeat.1" : "repeat"
                        ).frame(
                            width: 44, height: 44)
                    }
                    .accessibilityLabel(localized("kuran.oynatici.tekrar"))
                    .accessibilityValue(
                        player.repetition > 1
                            ? "\(player.repetition)" : localized("kuran.oynatici.tekrar.yok")
                    )
                    .hiddenWhenSimple(theme.largeAndSimple)
                    Spacer()
                    Button {
                        player.previous()
                    } label: {
                        Image(systemName: "backward.end.fill").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(localized("kuran.oynatici.onceki"))
                    Button {
                        player.togglePause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(
                            .system(size: 44))
                    }
                    .accessibilityLabel(
                        localized(player.isPlaying ? "kuran.oynatici.duraklat" : "kuran.oynatici.oynat"))
                    Button {
                        player.next()
                    } label: {
                        Image(systemName: "forward.end.fill").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(localized("kuran.oynatici.sonraki"))
                    Spacer()
                    Menu {
                        Picker(
                            localized("kuran.oynatici.hiz"),
                            selection: Binding(get: { player.speed }, set: { player.speed = $0 })
                        ) {
                            ForEach([Float(0.75), 1, 1.25, 1.5], id: \.self) { h in
                                Text(verbatim: "\(h.formatted())×").tag(h)
                            }
                        }
                    } label: {
                        Text(verbatim: "\(player.speed.formatted())×").typography(.emphasized).frame(
                            minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel(localized("kuran.oynatici.hiz"))
                    .hiddenWhenSimple(theme.largeAndSimple)
                }
            }
            .foregroundStyle(theme.colors.text)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.regularMaterial)
        }
    }

    @ViewBuilder private func status(_ s: RecitationPlayer.QueueItem) -> some View {
        if let su = contentProvider?.surah(s.surah) {
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

/// İndirilenler: downloaded recitations with size; swiping deletes.
struct DownloadsScreen: View {
    @Environment(AudioStore.self) private var store
    @Environment(\.contentProvider) private var contentProvider
    @Environment(\.theme) private var theme
    @State private var refresh = 0

    var body: some View {
        let _ = refresh
        let l = store.downloaded()
        List {
            if l.isEmpty {
                Text(app: "kuran.indirilenler.bos").foregroundStyle(theme.colors.text2)
            }
            ForEach(Array(l.enumerated()), id: \.offset) { _, e in
                HStack {
                    VStack(alignment: .leading) {
                        Text(
                            verbatim: contentProvider?.surah(e.surah)?.name(language: translationLanguage())
                                ?? "\(e.surah)")
                        Text(verbatim: e.reciter.name).typography(.footnote).foregroundStyle(
                            theme.colors.text2)
                    }
                    Spacer()
                    Text(verbatim: e.bytes.formatted(.byteCount(style: .file))).foregroundStyle(
                        theme.colors.text2)
                }
                .swipeActions {
                    Button(localized("kuran.indirilenler.sil"), role: .destructive) {
                        if let n = contentProvider?.surah(e.surah)?.verseCount {
                            store.delete(e.reciter, surah: e.surah, verseCount: n)
                        }
                        refresh += 1
                    }
                }
            }
            Section {
                Text(app: "kuran.ses.kaynak").typography(.footnote).foregroundStyle(theme.colors.text2)
            }
        }
        .pageBackground()
        .navigationTitle(localized("kuran.indirilenler"))
    }
}

extension View {
    /// „Büyük ve sade“ hides repeat and tempo; the space remains,
    /// so the playback buttons stay in the middle.
    func hiddenWhenSimple(_ sade: Bool) -> some View {
        opacity(sade ? 0 : 1).disabled(sade).accessibilityHidden(sade)
    }
}
