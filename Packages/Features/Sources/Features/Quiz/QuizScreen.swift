import ContentPacks
import Core
import DesignSystem
import PrayerTimes
import SwiftUI
import UserData

/// The quiz section: at the top the weekly ring, below it the daily round as
/// main button, then the areas as tiles with answered questions, share correct and due
/// reviews (package 4, variant A; tap starts an exercise in the area), below that the last
/// seven days from all answers, Tekrar, Düello, Alıştırma and Geçmiş. In „Büyük ve sade“ the same content as a calm list (A).
struct QuizScreen: View {
    @Environment(\.contentProvider) private var contentProvider
    @Environment(\.theme) private var theme
    @Environment(UserStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @State private var areas = QuizAreas()

    var body: some View {
        let _ = store.version
        let d = QuizStatus(store: store)
        Group {
            if theme.largeAndSimple {
                list(d)
            } else {
                ring(d)
            }
        }
        .pageBackground()
        .navigationTitle(Text(app: "sekme.quiz"))
        .task { await loadAreas() }
    }

    private func loadAreas() async {
        guard let contentProvider else { return }
        areas = await QuizAreas.load(contentProvider: contentProvider)
    }

    /// Below the tiles: what an installed bank source shows (e.g. questions waiting for review).
    private var pendingRow: some View { SlotView(.quizBanks(pending: areas.pending)) }

    // MARK: B · Halka

    private func ring(_ d: QuizStatus) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !settings.quizIntentionSeen { IntentionCard() }
                HStack(spacing: 16) {
                    WeekRing(done: d.weekDone, goal: settings.quizGoal)
                        .frame(width: 84, height: 84)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app: "quiz.bu_hafta").typography(.title2).foregroundStyle(theme.colors.text)
                        Text(app: "quiz.hedef_seri \(settings.quizGoal) \(d.streak)").typography(.secondary)
                            .foregroundStyle(theme.colors.text2)
                        if d.weekDone >= settings.quizGoal {
                            Text(app: "quiz.hafta_tamam").typography(.emphasized).foregroundStyle(
                                theme.colors.successText)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                ReligiousDayCard(d: d)
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(areas.areas) { a in
                        areaBox(
                            a, counter: d.areaCounters[a.rawValue] ?? QuizCounter(),
                            repetition: d.repetitionByArea[a.rawValue] ?? 0)
                    }
                }
                pendingRow
                NavigationLink(value: Goal.quizHistory) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(app: "quiz.gecmis.hafta").typography(.footnote).textCase(.uppercase)
                                .foregroundStyle(theme.colors.label)
                            Spacer()
                            Image(systemName: "chevron.right").typography(.footnote).foregroundStyle(
                                theme.colors.text2)
                        }
                        WeekBars(days: d.sevenDays, counters: d.dayCounters, height: 64)
                        WeekSummary(days: d.sevenDays, counters: d.dayCounters)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.colors.surface, in: .rect(cornerRadius: 22))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                VStack(spacing: 0) {
                    row(
                        .quizGame("tekrar"), icon: "arrow.counterclockwise",
                        title: localized("quiz.tekrar"),
                        bottom: d.repeatCount > 0
                            ? localized("quiz.tekrar.bekliyor \(d.repeatCount)")
                            : localized("quiz.tekrar.yok"),
                        light: d.repeatCount > 0)
                    Divider().padding(.leading, 56)
                    row(
                        .quizDuello, icon: "arrow.left.arrow.right", title: localized("quiz.duello"),
                        bottom: d.duelloAlt)
                    Divider().padding(.leading, 56)
                    row(
                        .quizPractice, icon: "slider.horizontal.3", title: localized("quiz.alistirma"),
                        bottom: localized("quiz.alistirma.alt"))
                    Divider().padding(.leading, 56)
                    row(
                        .quizHistory, icon: "chart.bar", title: localized("quiz.gecmis"),
                        bottom: localized("quiz.gecmis.alt"))
                }
                .background(theme.colors.surface, in: .rect(cornerRadius: 22))
            }
            .padding(16)
        }
        #if DEBUG
            // Screenshots of the lower half (bank tiles, „onay bekliyor“): `-quizAsagi 1`.
            .defaultScrollAnchor(UserDefaults.standard.bool(forKey: "quizAsagi") ? .bottom : .top)
        #endif
    }

    private func areaBox(_ a: QuizArea, counter: QuizCounter, repetition: Int) -> some View {
        NavigationLink(
            value: Goal.quizGame(QuizSession.Request.practiceText(a, length: 10, tier: 0))
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    IconTile(a.icon, tone: a.ton)
                    Text(verbatim: a.name).typography(.emphasized).foregroundStyle(theme.colors.text)
                        .lineLimit(
                            1
                        )
                        .minimumScaleFactor(0.8)
                }
                AreaSummary(counter: counter)
                RatioBar(ratio: counter.ratio)
                if repetition > 0 {
                    Text(app: "quiz.alan.tekrar \(repetition)").typography(.footnote).foregroundStyle(
                        theme.colors.accent
                    )
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(theme.colors.accent.opacity(0.12), in: .capsule)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.colors.surface, in: .rect(cornerRadius: 18))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(localized("quiz.alan.ipucu"))
    }

    private func row(_ h: Goal, icon: String, title: String, bottom: String, light: Bool = true) -> some View
    {
        NavigationLink(value: h) {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 28).foregroundStyle(theme.colors.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title).typography(.emphasized).foregroundStyle(theme.colors.text)
                    Text(verbatim: bottom).typography(.footnote).foregroundStyle(theme.colors.text2)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.footnote.weight(.bold))
                    .foregroundStyle(theme.colors.text2).accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!light)
        .opacity(light ? 1 : 0.6)
    }

    // MARK: A · List (Büyük ve sade)

    /// Like Keşfet: one column of large rows, the daily round on top as the only card with a button.
    /// Deliberately without `List`, because it would turn the card's button into a list row.
    private func list(_ d: QuizStatus) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !settings.quizIntentionSeen { IntentionCard() }
                ReligiousDayCard(d: d)
                VStack(spacing: 0) {
                    row(
                        .quizHistory, icon: "circle.dashed", title: localized("quiz.bu_hafta"),
                        bottom: "\(d.weekDone) / \(settings.quizGoal) · "
                            + WeekSummary.text(d.sevenDays, d.dayCounters))
                    Divider().padding(.leading, 56)
                    row(
                        .quizGame("tekrar"), icon: "arrow.counterclockwise",
                        title: localized("quiz.tekrar"),
                        bottom: d.repeatCount > 0
                            ? localized("quiz.tekrar.bekliyor \(d.repeatCount)")
                            : localized("quiz.tekrar.yok"),
                        light: d.repeatCount > 0)
                }
                .background(theme.colors.surface, in: .rect(cornerRadius: 22))
                Text(app: "quiz.alistirma").typography(.footnote).textCase(.uppercase).foregroundStyle(
                    theme.colors.label)
                VStack(spacing: 0) {
                    ForEach(areas.areas) { a in
                        row(
                            .quizGame(QuizSession.Request.practiceText(a, length: 10, tier: 0)),
                            icon: a.icon,
                            title: a.name,
                            bottom: AreaSummary.text(d.areaCounters[a.rawValue] ?? QuizCounter()))
                        Divider().padding(.leading, 56)
                    }
                    row(
                        .quizPractice, icon: "slider.horizontal.3", title: localized("quiz.alistirma"),
                        bottom: localized("quiz.alistirma.alt"))
                }
                .background(theme.colors.surface, in: .rect(cornerRadius: 22))
                pendingRow
                VStack(spacing: 0) {
                    row(
                        .quizDuello, icon: "arrow.left.arrow.right", title: localized("quiz.meydan_oku"),
                        bottom: d.duelloAlt)
                    Divider().padding(.leading, 56)
                    row(
                        .quizHistory, icon: "chart.bar", title: localized("quiz.gecmis"),
                        bottom: localized("quiz.gecmis.alt"))
                }
                .background(theme.colors.surface, in: .rect(cornerRadius: 22))
            }
            .padding(16)
        }
    }
}

/// What the quiz section knows about the user, read once per presentation.
@MainActor struct QuizStatus {
    let today: Day
    let kind: QuizTuru?
    let todaysAnswer: SoruCevabi?
    let weekDone: Int
    let streak: Int
    let areaCounters: [String: QuizCounter]
    let repetitionByArea: [String: Int]
    /// Today and the six days before, oldest first.
    let sevenDays: [Day]
    let dayCounters: [String: QuizCounter]
    let repeatCount: Int
    let duelloAlt: String

    init(store: UserStore, now: Date = .now) {
        today = QuizDay.today(now)
        kind = store.dailyKind(day: today.description)
        todaysAnswer = store.questionAnswer(day: today.description)
        let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let ab = QuizDay.today(weekStart).description
        weekDone = Set(store.quizRounds(cesit: "gunluk", ab: ab).filter(\.isFinished).map(\.gun)).count
        streak = store.dailyPoints(now: now).streak
        areaCounters = store.quizAreaCounters()
        repetitionByArea = store.dueReviewCounts(now: now)
        let day = QuizDay.today(now)
        let lastSeven = (0..<7).reversed().map { day.added(-$0) }
        sevenDays = lastSeven
        dayCounters = store.quizDayCounters(ab: lastSeven[0].description)
        repeatCount = store.dueReviews(now: now).count
        if let d = store.duels().first {
            let code = DuelCode.formatted(d.kod)
            duelloAlt = d.karsiAd.isEmpty ? code : localized("quiz.duello.ile \(d.karsiAd) \(code)")
        } else {
            duelloAlt = localized("quiz.meydan_oku")
        }
    }

    /// Answered questions of the daily round (the daily question counts too, even without a round).
    var answeredCount: Int { max(kind?.cevapSayisi ?? 0, todaysAnswer == nil ? 0 : 1) }
    var length: Int { kind?.uzunluk ?? 10 }
    var finished: Bool { kind?.isFinished ?? false }
}

/// The daily round as the only card with a score.
struct ReligiousDayCard: View {
    @Environment(\.theme) private var theme
    let d: QuizStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(app: "quiz.gunun_turu").typography(.footnote).textCase(.uppercase).foregroundStyle(
                theme.colors.label)
            if d.finished {
                Text(app: "quiz.puan \(d.kind?.puan ?? 0)").typography(.title1).foregroundStyle(
                    theme.colors.text)
                Text(app: "quiz.gunun_turu.bitti \(d.kind?.dogruSayisi ?? 0) \(d.length)").typography(
                    .secondary
                )
                .foregroundStyle(theme.colors.text2)
            } else if d.answeredCount > 0 {
                Text(app: "quiz.gunun_turu.durum \(d.answeredCount) \(d.length)").typography(.title2)
                    .foregroundStyle(theme.colors.text)
            } else {
                Text(app: "quiz.gunun_turu.baslamadin").typography(.title2).foregroundStyle(theme.colors.text)
                Text(app: "quiz.gunun_turu.alt").typography(.secondary).foregroundStyle(theme.colors.text2)
            }
            NavigationLink(value: Goal.quizGame("gun")) {
                Text(
                    verbatim: d.finished
                        ? localized("quiz.sonucu_gor")
                        : d.answeredCount > 0
                            ? localized("quiz.devam_kalan \(d.length - d.answeredCount)")
                            : localized("quiz.basla"))
            }
            .buttonStyle(PrimaryButton())
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.surface, in: .rect(cornerRadius: 22))
    }
}

/// Weekly goal as a ring („5 von 7“), without fanfare.
struct WeekRing: View {
    @Environment(\.theme) private var theme
    let done: Int
    let goal: Int

    var body: some View {
        ZStack {
            Circle().stroke(theme.colors.line, lineWidth: 9)
            Circle()
                .trim(from: 0, to: min(1, CGFloat(done) / CGFloat(max(1, goal))))
                .stroke(theme.colors.sage, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(verbatim: "\(done)/\(goal)").typography(.emphasized).monospacedDigit().foregroundStyle(
                theme.colors.text)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localized("quiz.halka.sesli \(done) \(goal)"))
    }
}

/// Share correct as a bar; empty without answers.
struct RatioBar: View {
    @Environment(\.theme) private var theme
    let ratio: Double

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.colors.line)
                Capsule().fill(theme.colors.sage).frame(width: g.size.width * ratio)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// „42 soru · %78 doğru“ or „Henüz soru yok“.
struct AreaSummary: View {
    @Environment(\.theme) private var theme
    let counter: QuizCounter

    var body: some View {
        Text(verbatim: Self.text(counter)).typography(.footnote).foregroundStyle(theme.colors.text2)
    }

    static func text(_ s: QuizCounter) -> String {
        s.total == 0
            ? localized("quiz.alan.bos")
            : localized("quiz.alan.ozet \(s.total) \(Int((s.ratio * 100).rounded()))")
    }
}

/// Seven days as stacked columns: correct at the bottom (green), wrong on top (pale red).
///
/// Counts every answered question, not only the daily round; before, this mostly showed seven zeros
/// because exercises carry no points.
struct WeekBars: View {
    @Environment(\.theme) private var theme
    let days: [Day]
    let counters: [String: QuizCounter]
    let height: CGFloat

    var body: some View {
        let maxCount = max(1, days.map { counters[$0.description]?.total ?? 0 }.max() ?? 1)
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(days, id: \.description) { g in
                let s = counters[g.description] ?? QuizCounter()
                VStack(spacing: 4) {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        if s.total == 0 {
                            Capsule().fill(theme.colors.line).frame(height: 3)
                        } else {
                            Rectangle().fill(theme.colors.accent.opacity(0.35))
                                .frame(height: height * CGFloat(s.wrong) / CGFloat(maxCount))
                            Rectangle().fill(theme.colors.sage)
                                .frame(height: height * CGFloat(s.correct) / CGFloat(maxCount))
                        }
                    }
                    .frame(height: height)
                    .clipShape(.rect(topLeadingRadius: 4, topTrailingRadius: 4))
                    Text(
                        verbatim: g.start(.current).formatted(
                            .dateTime.weekday(.abbreviated).locale(AppLanguage.locale))
                    )
                    .typography(.footnote).foregroundStyle(theme.colors.text2).lineLimit(1)
                    .minimumScaleFactor(
                        0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localized("quiz.hafta.sesli \(total.correct) \(total.wrong)"))
    }

    private var total: QuizCounter {
        days.reduce(into: QuizCounter()) { t, g in
            let s = counters[g.description] ?? QuizCounter()
            t.correct += s.correct
            t.wrong += s.wrong
        }
    }
}

/// „46 soru · %82 doğru · 4 gün“ below the columns.
struct WeekSummary: View {
    @Environment(\.theme) private var theme
    let days: [Day]
    let counters: [String: QuizCounter]

    var body: some View {
        Text(verbatim: Self.text(days, counters)).typography(.secondary).foregroundStyle(theme.colors.text2)
    }

    static func text(_ days: [Day], _ counters: [String: QuizCounter]) -> String {
        let l = days.compactMap { counters[$0.description] }.filter { $0.total > 0 }
        let t = l.reduce(into: QuizCounter()) {
            $0.correct += $1.correct; $0.wrong += $1.wrong
        }
        guard t.total > 0 else { return localized("quiz.hafta.bos") }
        return localized("quiz.hafta.ozet \(t.total) \(Int((t.ratio * 100).rounded())) \(l.count)")
    }
}

/// Once on first open: one sentence about the intent, then never again.
struct IntentionCard: View {
    @Environment(\.theme) private var theme
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(app: "quiz.niyet").typography(.body).foregroundStyle(theme.colors.text)
                .fixedSize(horizontal: false, vertical: true)
            Button(localized("quiz.niyet.tamam")) { withAnimation { settings.quizIntentionSeen = true } }
                .buttonStyle(SecondaryButton())
        }
        .padding(16)
        .background(theme.colors.surface2, in: .rect(cornerRadius: 22))
    }
}
