import Core
import DesignSystem
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

/// Device checks for the iPad layouts. On the iPhone everything stays as it is.
public enum PadLayout {
    /// The iPad shell (sidebar, global player). Decided by the device, not the window: an iPad in a
    /// narrow window keeps its areas and lets the system fold the sidebar into a tab bar.
    @MainActor public static var isPad: Bool {
        #if os(iOS)
            UIDevice.current.userInterfaceIdiom == .pad
        #else
            false
        #endif
    }
}

extension EnvironmentValues {
    /// iPad: the size of the whole window. A page narrower than this has the sidebar next to it.
    @Entry var padWindow = CGSize.zero
}

/// The small entrance of the iPad boards: fade and rise, in a stagger through `delay`. Nothing moves with
/// „reduce motion“. Never for Quran text.
struct PadEnter: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var delay = 0.0
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .onAppear {
                guard !reduceMotion, !shown else { return }
                withAnimation(.timingCurve(0.3, 0.9, 0.3, 1, duration: 0.6).delay(delay)) { shown = true }
            }
    }
}

extension View {
    func padEnter(delay: Double = 0) -> some View { modifier(PadEnter(delay: delay)) }

    /// The card of the iPad boards: surface, thin line, soft shadow.
    func padCard(_ theme: Theme, radius: CGFloat = 26) -> some View {
        self
            .background(theme.colors.surface, in: .rect(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(theme.colors.line.opacity(0.9)))
            .padShadow(theme)
    }

    /// The soft warm shadow of the boards; two layers in light, a plain deep one in dark.
    func padShadow(_ theme: Theme) -> some View {
        let warm = PadColor.warmShadow
        return
            self
            .shadow(color: theme.colors.dark ? .black.opacity(0.4) : warm.opacity(0.08), radius: 1, y: 1)
            .shadow(color: theme.colors.dark ? .black.opacity(0.35) : warm.opacity(0.10), radius: 12, y: 8)
    }
}

/// What the sidebar can select: an area, or a destination a plugin brings along (Bibliothek, KI).
enum PadSelection: Hashable {
    case area(AppTab)
    case plugin(String)
}

/// A sidebar row provided by a plugin, in the group „Medien“.
public struct PluginSidebarEntry: Identifiable {
    public let id: String
    public let titleKey: String
    public let icon: String
    public let goal: Goal
    /// Second line on the tiles in Entdecken.
    public let subKey: String

    public init(id: String, titleKey: String, icon: String, goal: Goal, subKey: String = "") {
        self.id = id
        self.titleKey = titleKey
        self.icon = icon
        self.goal = goal
        self.subKey = subKey
    }
}

/// The iPad shell (board G01/G02): one system `TabView` that is a sidebar when opened and a bar at the
/// top when folded. Which form it starts in and when it switches is up to iPadOS.
struct PadShell: View {
    @Environment(Router.self) private var direction
    @Environment(\.plugins) private var plugins
    @Environment(\.theme) private var theme
    @State private var window = CGSize.zero
    /// iPad: the user may sort and hide rows in the sidebar.
    @AppStorage("ipad.seitenleiste") private var customization = TabViewCustomization()
    /// The area of the last visit; opening goes on where reading stopped (task T1 of the briefing).
    @SceneStorage("ipad.bereich") private var lastArea = ""

    private var selection: Binding<PadSelection> {
        Binding(
            get: { direction.padPlugin.map(PadSelection.plugin) ?? .area(direction.selected) },
            set: { value in
                switch value {
                case .area(let a):
                    direction.selected = a
                    direction.padPlugin = nil
                case .plugin(let id):
                    direction.padPlugin = id
                }
            })
    }

    var body: some View {
        @Bindable var direction = direction
        TabView(selection: selection) {
            areaTab(.prayerTimes)
            areaTab(.quran)
            areaTab(.qibla)
            TabSection {
                areaTab(.duas, inBar: false)
                areaTab(.hadith, inBar: false)
                areaTab(.dhikr, inBar: false)
                areaTab(.divineNames, inBar: false)
                areaTab(.quiz, inBar: false)
            } header: {
                Text(app: "ipad.grup.lernen")
            }
            .defaultVisibility(.hidden, for: .tabBar)
            .customizationID("ipad.lernen")
            let entries = plugins.sidebarEntries()
            if plugins.provides(.talks) || !entries.isEmpty {
                TabSection {
                    if plugins.provides(.talks) { areaTab(.talks) }
                    ForEach(entries) { entry in
                        Tab(value: PadSelection.plugin(entry.id)) {
                            PluginTabRoot(goal: entry.goal)
                        } label: {
                            Label {
                                Text(verbatim: localized(key: entry.titleKey))
                            } icon: {
                                Image(systemName: entry.icon)
                            }
                        }
                        .defaultVisibility(.hidden, for: .tabBar)
                        .customizationID("ipad.\(entry.id)")
                    }
                } header: {
                    Text(app: "ipad.grup.medien")
                }
                .customizationID("ipad.medien")
            }
            areaTab(.discover)
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewCustomization($customization)
        .environment(\.padWindow, window)
        .tabViewSidebarHeader {
            PadSidebarHeader()
        }
        .tabViewSidebarBottomBar {
            PadSidebarFooter()
        }
        .tint(theme.colors.accent)
        .onGeometryChange(for: CGSize.self, of: \.size) { window = $0 }
        .onAppear {
            if direction.selected == .prayerTimes, direction.path.isEmpty, let a = AppTab(rawValue: lastArea),
                a != .talks || plugins.provides(.talks)
            {
                direction.selected = a
            }
        }
        .onChange(of: direction.selected) { _, a in lastArea = a.rawValue }
        .sheet(isPresented: $direction.padSettingsOpen) {
            PadSettingsScreen()
        }
        #if os(iOS)
            .background(PadSidebarOpener())
        #endif
    }

    @TabContentBuilder<PadSelection>
    private func areaTab(_ tab: AppTab, inBar: Bool = true) -> some TabContent<PadSelection> {
        Tab(value: PadSelection.area(tab)) {
            TabRoot(tab: tab)
        } label: {
            Label {
                Text(app: tab.titleKey)
            } icon: {
                Image(systemName: tab.icon)
            }
        }
        .defaultVisibility(inBar ? .automatic : .hidden, for: .tabBar)
        .customizationID("ipad.\(tab.rawValue)")
    }
}

/// Logo and name on top of the sidebar.
private struct PadSidebarHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(AppIcon.heartCompass.previewName, bundle: .main)
                .resizable()
                .frame(width: 44, height: 44)
                .clipShape(.rect(cornerRadius: 11))
                .accessibilityHidden(true)
            Text(verbatim: "Kıblegâh").typography(.title1).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Foot of the sidebar: Ayarlar and the next prayer.
private struct PadSidebarFooter: View {
    @Environment(Router.self) private var direction
    @Environment(\.theme) private var theme

    var body: some View {
        // Band and gear share one row: the list above needs the height (usability review).
        HStack(spacing: 8) {
            PrayerBand(style: .card)
            Button {
                direction.padSettingsOpen = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 20))
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.colors.text)
            .accessibilityLabel(localized("ayarlar.baslik"))
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }
}

/// The root of a sidebar row that belongs to a plugin: its own stack.
private struct PluginTabRoot: View {
    let goal: Goal
    @State private var path: [Goal] = []

    var body: some View {
        NavigationStack(path: $path) {
            GoalScreen(goal: goal)
                .padPlayerInset(pageOwnsPlayer: false)
                .navigationDestination(for: Goal.self) {
                    GoalScreen(goal: $0).padPlayerInset(pageOwnsPlayer: $0.showsReader)
                }
        }
    }
}

#if os(iOS)
    /// Opens the sidebar once on the first start in landscape (board G01). After that the system remembers
    /// what the user chose.
    private struct PadSidebarOpener: UIViewControllerRepresentable {
        func makeUIViewController(context: Context) -> Finder { Finder() }
        func updateUIViewController(_ controller: Finder, context: Context) {}

        final class Finder: UIViewController {
            private static let key = "ipad.seitenleiste.geoeffnet"

            override func viewDidAppear(_ animated: Bool) {
                super.viewDidAppear(animated)
                var open = !UserDefaults.standard.bool(forKey: Self.key)
                #if DEBUG
                    // Screenshots: `-ipadLeiste auf|zu`.
                    let forced = UserDefaults.standard.string(forKey: "ipadLeiste")
                    if forced != nil { open = true }
                #endif
                guard open, let bar = tabBarController(from: view.window?.rootViewController) else { return }
                #if DEBUG
                    if let forced {
                        bar.sidebar.isHidden = forced != "auf"
                        return
                    }
                #endif
                if view.bounds.width > view.bounds.height { bar.sidebar.isHidden = false }
                UserDefaults.standard.set(true, forKey: Self.key)
            }

            private func tabBarController(from root: UIViewController?) -> UITabBarController? {
                guard let root else { return nil }
                if let bar = root as? UITabBarController { return bar }
                for child in root.children {
                    if let bar = tabBarController(from: child) { return bar }
                }
                return nil
            }
        }
    }
#endif
