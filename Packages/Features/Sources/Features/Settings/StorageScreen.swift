import ContentPacks
import Core
import DesignSystem
import Foundation
import Quran
import SwiftUI

/// Storage management: what the app occupies on the device,
/// split into downloaded recitations, caches and app data.
/// Recitations and caches can be deleted; content packs belong to the app itself.
struct StorageScreen: View {
    @Environment(AudioStore.self) private var audioStore
    @Environment(\.theme) private var theme
    @State private var refresh = 0
    @State private var approval: Confirmation?
    /// Bytes a plugin keeps in Application Support (shown in its own section, not under app data).
    @State private var extraSize: Int64 = 0

    enum Confirmation: Identifiable {
        case reciter(Reciter), cache
        var id: String {
            switch self {
            case .reciter(let k): k.id
            case .cache: "onbellek"
            }
        }
    }

    /// Caches that the app can reload at any time.
    static let caches = ["KelimeMeali", "KelimeZamanlari", "MushafDuzeni"]
    /// Individual files in the Caches folder that the app recomputes itself ().
    static let cacheFiles = ["esma-ayetler-"]

    var body: some View {
        let _ = refresh
        let downloadedItems = Dictionary(grouping: audioStore.downloaded(), by: { $0.reciter.id })
        let cache =
            Self.caches.map { Self.size(URL.cachesDirectory.appending(path: $0)) }.reduce(0, +)
            + Int64(URLCache.shared.currentDiskUsage) + Self.cacheFilesSize()
        let packs = Bundle.main.url(forResource: "Paketler", withExtension: nil).map(Self.size) ?? 0
        let bookSize = extraSize
        let items =
            Self.size(URL.applicationSupportDirectory)
            - (audioStore.rootInApp ? downloadedItems.values.joined().map(\.bytes).reduce(0, +) : 0)
            - bookSize
        let total =
            downloadedItems.values.joined().map(\.bytes).reduce(0, +) + cache + packs + max(0, items)
            + bookSize

        List {
            Section {
                row(localized("depolama.toplam"), total, icon: "internaldrive").fontWeight(.semibold)
            }
            Section {
                if downloadedItems.isEmpty {
                    Text(app: "kuran.indirilenler.bos").foregroundStyle(theme.colors.text2)
                }
                ForEach(Reciter.all.filter { downloadedItems[$0.id] != nil }, id: \.id) { k in
                    let l = downloadedItems[k.id] ?? []
                    row(
                        localized("depolama.kari \(k.name) \(l.count)"), l.map(\.bytes).reduce(0, +),
                        icon: "waveform"
                    )
                    .swipeActions {
                        Button(localized("kuran.indirilenler.sil"), role: .destructive) {
                            approval = .reciter(k)
                        }
                    }
                }
                NavigationLink(value: Goal.downloaded) { Text(app: "depolama.sure_sure") }
            } header: {
                Text(app: "depolama.tilavetler")
            }
            SlotView(.storageSection)
            Section {
                row(localized("depolama.onbellek"), cache, icon: "clock.arrow.circlepath")
                Button(localized("depolama.onbellek.temizle"), role: .destructive) { approval = .cache }
            } footer: {
                Text(app: "depolama.onbellek.alt")
            }
            Section {
                row(localized("depolama.paketler"), packs, icon: "books.vertical")
                row(localized("depolama.veriler"), max(0, items), icon: "person.crop.circle")
            } header: {
                Text(app: "depolama.uygulama")
            } footer: {
                Text(app: "depolama.uygulama.alt")
            }
        }
        .pageBackground()
        .navigationTitle(localized("depolama.baslik"))
        .task { extraSize = await StorageExtras.size() }
        .confirmationDialog(
            localized("depolama.emin"),
            isPresented: Binding(get: { approval != nil }, set: { if !$0 { approval = nil } }),
            titleVisibility: .visible
        ) {
            Button(localized("kuran.indirilenler.sil"), role: .destructive) {
                switch approval {
                case .reciter(let k): audioStore.deleteAll(k)
                case .cache: Self.clearCache()
                case nil: break
                }
                approval = nil
                refresh += 1
            }
        }
    }

    private func row(_ name: String, _ bytes: Int64, icon: String) -> some View {
        HStack {
            Label(name, systemImage: icon)
            Spacer()
            Text(verbatim: bytes.formatted(.byteCount(style: .file))).monospacedDigit()
                .foregroundStyle(theme.colors.text2)
        }
    }

    static func clearCache() {
        for name in caches {
            try? FileManager.default.removeItem(at: URL.cachesDirectory.appending(path: name))
        }
        URLCache.shared.removeAllCachedResponses()
        for u in cacheFileList() { try? FileManager.default.removeItem(at: u) }
    }

    private static func cacheFileList() -> [URL] {
        let all =
            (try? FileManager.default.contentsOfDirectory(
                at: URL.cachesDirectory, includingPropertiesForKeys: nil)) ?? []
        return all.filter { u in cacheFiles.contains { u.lastPathComponent.hasPrefix($0) } }
    }

    static func cacheFilesSize() -> Int64 {
        cacheFileList().reduce(0) {
            $0
                + Int64(
                    (try? $1.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize)
                        ?? 0)
        }
    }

    /// Occupied space of a folder including subfolders.
    static func size(_ url: URL) -> Int64 {
        guard
            let e = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey])
        else { return 0 }
        var t: Int64 = 0
        for case let f as URL in e {
            t += Int64(
                (try? f.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
        return t
    }
}

/// Storage a plugin occupies (its section comes via `Slot/storageSection`).
public enum StorageExtras {
    nonisolated(unsafe) public static var size: @Sendable () async -> Int64 = { 0 }
}
