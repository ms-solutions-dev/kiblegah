import Core
import DesignSystem
import SwiftUI

/// Entry points for optional features that an app target may plug in.
///
/// The shared screens know only these places. What appears there is supplied by the packages
/// that the respective app target links. Without an installed plugin all places show nothing,
/// and the code of those features is not part of the app. Installation happens via
/// `.plugins(_:)` at the root.
public protocol Plugin: Sendable {
    /// Screen for a jump target for which this plugin is responsible; otherwise nil.
    @MainActor func screen(_ goal: Goal) -> AnyView?
    /// Content for a place in a shared screen; nil = nothing.
    @MainActor func slot(_ slot: Slot) -> AnyView?
    /// Wraps the stable root of a page (e.g. to present a full-screen reader).
    @MainActor func wrap(_ content: AnyView) -> AnyView
    /// Does this plugin provide the area (tab) `tab`?
    @MainActor func provides(_ tab: AppTab) -> Bool
    /// Additional tafsir sources in the verse sheet (source chips, `Slot/verseSources(verse:work:)`).
    @MainActor func extraTafsirSources() -> [TafsirSource]
    /// A `kiblegah://` link (path components) this plugin understands; otherwise nil.
    @MainActor func route(_ parts: [String]) -> Goal?
    /// Rows of this plugin in the iPad sidebar, group „Medien“.
    @MainActor func sidebarEntries() -> [PluginSidebarEntry]
    /// Tiles of this plugin in Entdecken on the iPad.
    @MainActor func discoverTiles() -> [PluginSidebarEntry]
}

extension Plugin {
    @MainActor public func screen(_ goal: Goal) -> AnyView? { nil }
    @MainActor public func slot(_ slot: Slot) -> AnyView? { nil }
    @MainActor public func wrap(_ content: AnyView) -> AnyView { content }
    @MainActor public func provides(_ tab: AppTab) -> Bool { false }
    @MainActor public func extraTafsirSources() -> [TafsirSource] { [] }
    @MainActor public func route(_ parts: [String]) -> Goal? { nil }
    @MainActor public func sidebarEntries() -> [PluginSidebarEntry] { [] }
    @MainActor public func discoverTiles() -> [PluginSidebarEntry] { [] }
}

/// A further tafsir source: identifier (stored under `tefsir.kaynak`) and catalog key of its name.
public struct TafsirSource: Hashable, Sendable {
    public let id: String
    public let nameKey: String

    public init(_ id: String, nameKey: String) {
        self.id = id
        self.nameKey = nameKey
    }
}

/// Place in a shared screen where a plugin may insert something.
public enum Slot: Hashable, Sendable {
    /// Button next to the search in Keşfet.
    case discoverAsk
    /// Rows in the lower Keşfet section.
    case discoverRows
    /// Sections in Ayarlar.
    case settingsSections
    /// Rows inside the collapsed advanced settings.
    case settingsAdvanced
    /// Rows at the top of Notlarım ve koleksiyonlarım.
    case collectionRows
    /// Section with further notes in the notes overview.
    case collectionNotes(search: String, archived: Bool)
    /// Section in Depolama.
    case storageSection
    /// Section below the dua categories.
    case duasSection
    /// Below a dua (`slug`).
    case duaCitations(String)
    /// Verse sheet, Hadith tab: further hadiths for the verse (`surah:verse`).
    case verseHadiths(String)
    /// Invisible in the verse sheet: reports via ``VerseHadithNotice`` whether there are further hadiths.
    case verseHadithProbe(String)
    /// Verse sheet, Tafsir tab: sections from another source (`work` ≠ „muhtasar“).
    case verseSources(verse: String, work: String)
    /// Verse sheet below the note: further highlights for this verse.
    case verseBookMarks(surah: Int, verse: Int)
    /// Extra tile in the action strip of the verse sheet (style ``ActionTile``).
    case verseAction(ContentKey)
    /// Extra entry for a verse in the reader and mushaf menus.
    case verseMenuAction(ContentKey)
    /// Below a name of Allah: a further explanation; ``DivineNameSourceAction`` opens the source sheet.
    case divineNameExplanation(Int)
    /// Section in the source sheet of a name of Allah.
    case divineNameSource(Int)
    /// Below the quiz tiles (`pending`: questions of additional banks that wait for review).
    case quizBanks(pending: Int)
    /// Section in the quiz settings.
    case quizSettings
}

/// Opens the source sheet of a name of Allah from inside ``Slot/divineNameExplanation(_:)``.
public struct DivineNameSourceAction {
    let open: () -> Void
    public func callAsFunction() { open() }
}

extension EnvironmentValues {
    @Entry public var divineNameSourceAction: DivineNameSourceAction? = nil
}

/// Reports upward from ``Slot/verseHadithProbe(_:)`` whether there are further hadiths for the verse. As a value
/// instead of a bare closure, like `BookOpening` (otherwise SwiftUI re-checks on every update).
public struct VerseHadithNotice {
    let notify: (Bool) -> Void
    public func callAsFunction(_ exists: Bool) { notify(exists) }
}

extension EnvironmentValues {
    @Entry public var verseHadithNotice: VerseHadithNotice? = nil
}

/// All installed plugins of an app target.
public struct Plugins: Sendable {
    public var list: [any Plugin]

    public init(_ list: [any Plugin] = []) { self.list = list }

    @MainActor func screen(_ goal: Goal) -> AnyView? { list.lazy.compactMap { $0.screen(goal) }.first }
    @MainActor func slot(_ slot: Slot) -> [AnyView] { list.compactMap { $0.slot(slot) } }
    @MainActor func wrap(_ content: AnyView) -> AnyView { list.reduce(content) { $1.wrap($0) } }
    @MainActor func extraTafsirSources() -> [TafsirSource] { list.flatMap { $0.extraTafsirSources() } }
    @MainActor public func route(_ parts: [String]) -> Goal? {
        list.lazy.compactMap { $0.route(parts) }.first
    }

    @MainActor func sidebarEntries() -> [PluginSidebarEntry] { list.flatMap { $0.sidebarEntries() } }
    @MainActor func discoverTiles() -> [PluginSidebarEntry] { list.flatMap { $0.discoverTiles() } }

    /// Areas without their own package always exist; Sohbet only with a plugin that provides it.
    @MainActor public func provides(_ tab: AppTab) -> Bool {
        tab != .talks || list.contains { $0.provides(tab) }
    }

    /// The tabs this edition shows: the saved order, filtered and filled up.
    @MainActor public func tabs(_ stored: [AppTab]) -> [AppTab] {
        AppTab.normalized(stored) { provides($0) }
    }
}

extension EnvironmentValues {
    @Entry public var plugins = Plugins()
}

extension View {
    /// Installs the plugins (at the root of the app).
    public func plugins(_ e: Plugins) -> some View { environment(\.plugins, e) }

    /// Wraps the stable root of a page in the plugins.
    public func pluginWrapper() -> some View { modifier(PluginWrapper()) }
}

private struct PluginWrapper: ViewModifier {
    @Environment(\.plugins) private var plugins

    func body(content: Content) -> some View {
        if plugins.list.isEmpty { content } else { plugins.wrap(AnyView(content)) }
    }
}

/// Screen of a plugin for a jump target; without the plugin an empty state.
struct PluginScreen: View {
    @Environment(\.plugins) private var plugins
    let goal: Goal

    var body: some View {
        if let v = plugins.screen(goal) {
            v
        } else {
            EmptyState(title: "eklenti.yok", explanation: "eklenti.yok.aciklama")
        }
    }
}

/// Shows what the plugins insert at this place; nothing without a plugin.
public struct SlotView: View {
    @Environment(\.plugins) private var plugins
    let slot: Slot

    public init(_ slot: Slot) { self.slot = slot }

    public var body: some View {
        ForEach(Array(plugins.slot(slot).enumerated()), id: \.offset) { $0.element }
    }
}
