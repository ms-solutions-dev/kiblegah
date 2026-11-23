import ContentPacks
import Core
import DesignSystem
import Duas
import SwiftUI
import UserData

/// „Koleksiyona ekle“: toggle per collection and create a new one.
struct CollectionMenu: View {
    @Environment(UserStore.self) private var store
    let key: ContentKey
    @State private var newOpen = false
    @State private var newName = ""

    var body: some View {
        let _ = store.version
        Menu {
            ForEach(store.collections(), id: \.kimlik) { k in
                Button {
                    store.toggleCollection(key.text, k)
                } label: {
                    if store.contains(key.text, k) {
                        Label(k.ad, systemImage: "checkmark")
                    } else {
                        Text(verbatim: k.ad)
                    }
                }
            }
            Divider()
            Button(localized("koleksiyon.yeni")) { newOpen = true }
        } label: {
            Label(localized("koleksiyon.ekle"), systemImage: "folder.badge.plus")
        }
        .alert(localized("koleksiyon.yeni"), isPresented: $newOpen) {
            TextField(localized("koleksiyon.ad"), text: $newName)
            Button(localized("koleksiyon.olustur")) {
                let name = newName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                store.toggleCollection(key.text, store.createCollection(name))
                newName = ""
            }
            Button(localized("genel.vazgec"), role: .cancel) { newName = "" }
        }
    }
}

/// Notlarım ve koleksiyonlarım: notes overview (active/archive, search) and collections.
struct CollectionsScreen: View {
    @Environment(UserStore.self) private var store
    @Environment(\.theme) private var theme
    @State private var archived = false
    @State private var search = ""
    @State private var newOpen = false
    @State private var newName = ""

    var body: some View {
        let _ = store.version
        let notes = store.notes(archived: archived).filter {
            search.isEmpty || TurkishText.searchForm($0.metin).contains(TurkishText.searchForm(search))
        }
        List {
            Section {
                NavigationLink(value: Goal.collection("kaydedilen")) {
                    LabeledContent(
                        localized("kuran.kaydedilen"),
                        value: "\(store.saved().filter { ContentKey(text: $0.anahtar) != nil }.count)")
                }
                // Saved videos (Sohbet) and book highlights (), depending on the edition.
                SlotView(.collectionRows)
                ForEach(store.collections(), id: \.kimlik) { k in
                    NavigationLink(value: Goal.collection(k.kimlik)) {
                        LabeledContent(k.ad, value: "\(store.items(k).count)")
                    }
                    .swipeActions {
                        Button(localized("kuran.indirilenler.sil"), role: .destructive) {
                            store.deleteCollection(k)
                        }
                    }
                }
                Button(localized("koleksiyon.yeni")) { newOpen = true }
            } header: {
                Text(app: "koleksiyon.baslik")
            }
            Section {
                Picker(localized("not.durum"), selection: $archived) {
                    Text(app: "not.aktif").tag(false)
                    Text(app: "not.arsiv").tag(true)
                }
                .pickerStyle(.segmented)
                if notes.isEmpty { Text(app: "not.bos").foregroundStyle(theme.colors.text2) }
                ForEach(notes, id: \.anahtar) { n in
                    if let a = ContentKey(text: n.anahtar) {
                        NavigationLink(value: Goal.verse(firstVerse(a))) {
                            VStack(alignment: .leading, spacing: 4) {
                                ContentKeyHeader(key: a).typography(.footnote).foregroundStyle(
                                    theme.colors.label)
                                Text(verbatim: n.metin).typography(.secondary).lineLimit(3)
                                Text(
                                    verbatim: n.degisiklik.formatted(
                                        Date.FormatStyle(date: .abbreviated, time: .omitted).locale(
                                            AppLanguage.locale))
                                )
                                .typography(.footnote)
                                .foregroundStyle(theme.colors.text2)
                            }
                        }
                        .swipeActions {
                            Button(localized(archived ? "kuran.notum.geri_al" : "kuran.notum.arsivle")) {
                                store.archiveNote(n.anahtar, !archived)
                            }
                        }
                    }
                }
            } header: {
                Text(app: "not.baslik")
            }
            // Notes from the books are included here, like the verse notes ().
            SlotView(.collectionNotes(search: search, archived: archived))
        }
        .alwaysSearchable($search, prompt: localized("not.ara"))
        .pageBackground()
        .navigationTitle(localized("koleksiyon.ekran"))
        .alert(localized("koleksiyon.yeni"), isPresented: $newOpen) {
            TextField(localized("koleksiyon.ad"), text: $newName)
            Button(localized("koleksiyon.olustur")) {
                let name = newName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { store.createCollection(name) }
                newName = ""
            }
            Button(localized("genel.vazgec"), role: .cancel) { newName = "" }
        }
    }
}

/// Content of a collection (or of everything saved).
struct CollectionDetailScreen: View {
    @Environment(UserStore.self) private var store
    @Environment(\.theme) private var theme
    let identifier: String

    var body: some View {
        let _ = store.version
        let k = store.collections().first { $0.kimlik == identifier }
        let keys =
            identifier == "kaydedilen" ? store.saved().map(\.anahtar) : (k.map { store.items($0) } ?? [])
        List {
            if keys.isEmpty { Text(app: "koleksiyon.bos").foregroundStyle(theme.colors.text2) }
            ForEach(keys, id: \.self) { m in
                if let a = ContentKey(text: m) {
                    NavigationLink(value: goal(a)) { ContentKeyRow(key: a) }
                        .swipeActions {
                            Button(localized("kuran.indirilenler.sil"), role: .destructive) {
                                if let k { store.toggleCollection(m, k) } else { store.toggleSaved(m) }
                            }
                        }
                }
            }
        }
        .pageBackground()
        .navigationTitle(k?.ad ?? localized("kuran.kaydedilen"))
    }

    private func goal(_ a: ContentKey) -> Goal {
        switch a {
        case .dua(let s): .dua(s)
        case .divineName(let n): .divineNameDetail(n)
        case .hadith(_, let n): .hadithDetail(n)
        default: .verse(firstVerse(a))
        }
    }
}

/// Title of a key (verse, dua, hadith, esma) – for lists.
struct ContentKeyHeader: View {
    @Environment(\.contentProvider) private var contentProvider
    let key: ContentKey

    var body: some View {
        Text(verbatim: text)
    }

    private var text: String {
        guard let contentProvider else { return key.text }
        switch key {
        case .verse, .verseRange: return verseName(key, contentProvider)
        case .dua(let s):
            return contentProvider.duas().first { $0.slug == s }.map { duaSource($0, contentProvider) } ?? s
        case .hadith(_, let n):
            return contentProvider.hadith(n, language: translationLanguage())?.title ?? "\(n)"
        case .divineName(let n):
            // ed-Dârr only together with en-Nâfi‘ (DivineName.namedWithPartner).
            return contentProvider.divineNames().first { $0.number == n }
                .map { e in ([e] + (e.partner.map { [$0] } ?? [])).map(\.latin).joined(separator: " · ") }
                ?? "\(n)"
        default: return key.text
        }
    }
}

struct ContentKeyRow: View {
    @Environment(\.contentProvider) private var contentProvider
    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme
    let key: ContentKey

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ContentKeyHeader(key: key).typography(.emphasized)
            if let o = summary {
                Text(verbatim: o).typography(.secondary).foregroundStyle(theme.colors.text2).lineLimit(2)
            }
        }
    }

    private var summary: String? {
        guard let contentProvider else { return nil }
        switch key {
        case .verse:
            return activeTranslations(contentProvider, settings).first.flatMap {
                contentProvider.translation(key, pack: $0.id)?.text
            }
        case .verseRange(let s, let i, _):
            return activeTranslations(contentProvider, settings).first.flatMap {
                contentProvider.translation(.verse(surah: s, verse: i), pack: $0.id)?.text
            }
        case .dua(let sl):
            guard let d = contentProvider.duas().first(where: { $0.slug == sl }) else { return nil }
            return DuaContent.transliteration(d, contentProvider, language: transliterationLanguage(settings))
        case .divineName(let n):
            return contentProvider.divineNames().first { $0.number == n }?.displayMeaning
        default: return nil
        }
    }
}
