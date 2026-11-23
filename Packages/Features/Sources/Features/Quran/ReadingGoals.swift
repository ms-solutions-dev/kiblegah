import ContentPacks
import Core
import DesignSystem
import SwiftUI
import UserData

/// First Sıra per Mushaf page - for „Seiten am Tag“.
@MainActor func pageStarts(_ contentProvider: any ContentProvider) -> [Int] {
    (1...604).compactMap { contentProvider.page($0)?.firstIndex }
}

/// Today, week bar (four states) and streak of the active reading position; above it the
/// label „Bu hafta“ as on Bugün, otherwise the row of letters stays without context.
struct ReadingSummary: View {
    @Environment(\.contentProvider) private var contentProvider
    @Environment(UserStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme

    var body: some View {
        let _ = store.version
        let k = settings.activeKhatm
        let o = store.sessions(khatm: k)
        let starts = contentProvider.map(pageStarts) ?? []
        let goal = store.goal(k)
        let readCount = store.versesReadCount(khatm: k)
        let today = ReadingStats.summary(o, day: .now, pageStarts: starts)
        let streak = ReadingStats.streak(o)
        VStack(alignment: .leading, spacing: 8) {
            Text(app: "bugun.okuma.baslik").typography(.footnote).textCase(.uppercase)
                .foregroundStyle(theme.colors.label)
                .accessibilityAddTraits(.isHeader)
            if let goal {
                let target = ReadingStats.dailyGoal(goal, readCount: readCount, readToday: today.verse)
                let actual = ReadingStats.value(today, goal.kind)
                HStack {
                    Text(verbatim: todayText(actual, target, goal.kind)).typography(.secondary)
                    Spacer()
                    if actual >= target {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.colors.sage)
                    }
                }
                ProgressView(value: Double(min(actual, target)), total: Double(max(1, target))).tint(
                    theme.colors.accent)
            }
            HStack(spacing: 6) {
                ForEach(
                    ReadingStats.week(o, goal: goal, readCount: readCount, pageStarts: starts), id: \.day
                ) { g in
                    VStack(spacing: 3) {
                        Circle()
                            .fill(fillColor(g.status))
                            .strokeBorder(
                                theme.colors.text2.opacity(g.status == .upcoming ? 0.35 : 0), lineWidth: 1
                            )
                            .frame(width: 14, height: 14)
                        Text(
                            verbatim: g.day.formatted(.dateTime.weekday(.narrow).locale(AppLanguage.locale))
                        ).typography(.footnote)
                            .foregroundStyle(theme.colors.text2)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(g.day.formatted(.dateTime.weekday(.wide).locale(AppLanguage.locale)))
                    .accessibilityValue(keyText("okuma.gun." + statusName(g.status)))
                }
                if streak > 0 {
                    Label(localized("okuma.seri \(streak)"), systemImage: "flame").typography(.footnote)
                        .foregroundStyle(theme.colors.accent).fixedSize()
                }
            }
        }
    }

    private func fillColor(_ d: ReadingStats.Day) -> Color {
        switch d {
        case .done: theme.colors.sage
        case .partial: theme.colors.sage.opacity(0.4)
        case .empty: theme.colors.surface2
        case .upcoming: .clear
        }
    }

    private func statusName(_ d: ReadingStats.Day) -> String {
        switch d {
        case .done: "tamam"
        case .partial: "kismen"
        case .empty: "bos"
        case .upcoming: "gelecek"
        }
    }

    private func todayText(_ actual: Int, _ target: Int, _ kind: GoalKind) -> String {
        switch kind {
        case .verses, .finishDate: localized("okuma.bugun.ayet \(actual) \(target)")
        case .pages: localized("okuma.bugun.sayfa \(actual) \(target)")
        case .minutes: localized("okuma.bugun.dakika \(actual) \(target)")
        }
    }
}

/// Reading positions and goals: default khatm plus custom ones (e.g. „Ramazan“), each with a goal.
struct ReadingGoalsScreen: View {
    @Environment(\.contentProvider) private var contentProvider
    @Environment(UserStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme
    @State private var newOpen = false

    var body: some View {
        let _ = store.version
        List {
            Section {
                row(identifier: "", name: localized("okuma.standart"))
                ForEach(store.khatms(), id: \.kimlik) { h in
                    row(identifier: h.kimlik, name: h.ad)
                        .swipeActions {
                            Button(localized("kuran.indirilenler.sil"), role: .destructive) {
                                if settings.activeKhatm == h.kimlik { settings.activeKhatm = "" }
                                store.deleteKhatm(h)
                            }
                        }
                }
                Button(localized("okuma.yeni")) { newOpen = true }
            } header: {
                Text(app: "okuma.okumalar")
            } footer: {
                Text(app: "okuma.okumalar.not")
            }
            Section {
                EditGoal(identifier: settings.activeKhatm)
            } header: {
                Text(app: "okuma.hedef")
            }
            Section { ReadingSummary() }
        }
        .pageBackground()
        .navigationTitle(localized("okuma.hedefler.baslik"))
        .smallTitle()
        .sheet(isPresented: $newOpen) { NewReading() }
    }

    private func row(identifier: String, name: String) -> some View {
        let readCount = store.versesReadCount(khatm: identifier)
        return Button {
            settings.activeKhatm = identifier
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: name).typography(.emphasized)
                    ProgressView(value: Double(readCount), total: 6236).tint(theme.colors.sage)
                    Text(app: "okuma.ilerleme \(readCount) \(Int((Double(readCount) / 62.36).rounded()))")
                        .typography(
                            .footnote
                        )
                        .foregroundStyle(theme.colors.text2)
                }
                if settings.activeKhatm == identifier {
                    Image(systemName: "checkmark").foregroundStyle(theme.colors.accent)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(settings.activeKhatm == identifier ? .isSelected : [])
    }
}

/// Change the goal of the reading position `identifier`: none, verses/pages/minutes per day, or khatm by a date.
struct EditGoal: View {
    @Environment(UserStore.self) private var store
    let identifier: String

    var body: some View {
        let _ = store.version
        let h = store.goal(identifier)
        Picker(
            localized("okuma.hedef.tur"),
            selection: Binding(
                get: { h?.kind },
                set: { t in
                    save(
                        t.map {
                            ReadingGoal(
                                kind: $0, value: standard($0), end: $0 == .finishDate ? thirtyDays : nil)
                        })
                }
            )
        ) {
            Text(app: "okuma.hedef.yok").tag(GoalKind?.none)
            ForEach(GoalKind.allCases, id: \.self) { t in
                Text(verbatim: keyText("okuma.hedef." + t.rawValue)).tag(GoalKind?.some(t))
            }
        }
        if let h {
            if h.kind == .finishDate {
                DatePicker(
                    localized("okuma.hedef.tarih"),
                    selection: Binding(
                        get: { h.end ?? thirtyDays },
                        set: { save(ReadingGoal(kind: .finishDate, value: 0, end: $0)) }),
                    in: Date.now..., displayedComponents: .date)
            } else {
                Stepper(
                    value: Binding(get: { h.value }, set: { save(ReadingGoal(kind: h.kind, value: $0)) }),
                    in: 1...600, step: step(h.kind)
                ) {
                    Text(verbatim: valueText(h))
                }
            }
        }
    }

    private func valueText(_ h: ReadingGoal) -> String {
        switch h.kind {
        case .pages: localized("okuma.hedef.deger.sayfa \(h.value)")
        case .minutes: localized("okuma.hedef.deger.dakika \(h.value)")
        default: localized("okuma.hedef.deger.ayet \(h.value)")
        }
    }

    private var thirtyDays: Date { Calendar.current.date(byAdding: .day, value: 29, to: .now) ?? .now }

    private func standard(_ t: GoalKind) -> Int {
        switch t {
        case .verses: 20
        case .pages: 2
        case .minutes: 10
        case .finishDate: 0
        }
    }

    private func step(_ t: GoalKind) -> Int { t == .verses ? 5 : 1 }

    private func save(_ h: ReadingGoal?) {
        if let record = store.khatm(identifier) { store.saveGoal(record, h) }
    }
}

/// New reading position with a template.
private struct NewReading: View {
    @Environment(UserStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var close
    @State private var name = ""
    @State private var template = 0

    /// Templates: Ramazan khatm, one juz a day, two pages a day, ten minutes a day.
    private var templates: [(LocalizedStringKey, ReadingGoal?)] {
        [
            (
                "okuma.sablon.ramazan",
                ReadingGoal(
                    kind: .finishDate, value: 0,
                    end: Calendar.current.date(byAdding: .day, value: 29, to: .now))
            ),
            ("okuma.sablon.sayfa", ReadingGoal(kind: .pages, value: 2)),
            ("okuma.sablon.dakika", ReadingGoal(kind: .minutes, value: 10)),
            ("okuma.sablon.serbest", nil),
        ]
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(localized("okuma.yeni.ad"), text: $name)
                Picker(localized("okuma.hedef"), selection: $template) {
                    ForEach(templates.indices, id: \.self) { i in Text(app: templates[i].0).tag(i) }
                }
                .pickerStyle(.inline)
            }
            .pageBackground()
            .navigationTitle(localized("okuma.yeni"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(localized("genel.vazgec")) { close() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("koleksiyon.olustur")) {
                        let nameView = name.trimmingCharacters(in: .whitespaces)
                        let h = store.createKhatm(
                            nameView.isEmpty ? localized("okuma.yeni.varsayilan") : nameView,
                            goal: templates[template].1)
                        settings.activeKhatm = h.kimlik
                        close()
                    }
                }
            }
        }
    }
}

/// Translation of a composed key (LocalizationValue would turn it into „…%@“).
func keyText(_ k: String) -> String {
    AppLanguage.bundle.localizedString(forKey: k, value: nil, table: nil)
}
