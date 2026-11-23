import ContentPacks
import Core
import DesignSystem
import PrayerTimes
import SwiftUI
import UserData

/// Alıştırma selection: area (or Karışık), length 10/15, level Otomatik/Kolay/Normal/Zor.
/// Exercises do not count, move the level by half and fill the review.
struct QuizPracticeScreen: View {
    @Environment(\.contentProvider) private var contentProvider
    @Environment(AppSettings.self) private var settings
    @State private var area: QuizArea?
    @State private var length = 10
    @State private var tier = 0
    @State private var areas: [QuizArea] = QuizArea.generated

    var body: some View {
        Form {
            Section {
                Picker(localized("quiz.alan"), selection: $area) {
                    Text(app: "quiz.karisik").tag(QuizArea?.none)
                    ForEach(areas) { a in Text(verbatim: a.name).tag(QuizArea?.some(a)) }
                }
                Picker(localized("quiz.uzunluk"), selection: $length) {
                    Text(app: "quiz.soru_sayisi \(10)").tag(10)
                    Text(app: "quiz.soru_sayisi \(15)").tag(15)
                }
                .pickerStyle(.segmented)
                Picker(localized("quiz.kademe"), selection: $tier) {
                    Text(app: "quiz.kademe.otomatik").tag(0)
                    Text(app: "quiz.kademe.kolay").tag(1)
                    Text(app: "quiz.kademe.normal").tag(2)
                    Text(app: "quiz.kademe.zor").tag(3)
                }
            } footer: {
                Text(app: "quiz.alistirma.aciklama")
            }
            Section {
                NavigationLink(
                    value: Goal.quizGame(
                        QuizSession.Request.practiceText(area, length: length, tier: tier))
                ) {
                    Text(app: "quiz.basla").typography(.emphasized)
                }
            }
        }
        .pageBackground()
        .navigationTitle(Text(app: "quiz.alistirma"))
        .task {
            guard let contentProvider else { return }
            areas = await QuizAreas.load(contentProvider: contentProvider).areas
        }
    }
}

/// Code duel (V1): create and share a code, enter someone else's code, „Düellolarım“ with the opponent's
/// result entered by hand. Duels do not count towards the score.
/// Düello overview (package 5, variant A "face to face"): at the top the own name, then challenge
/// with share link, per opponent the overall standing like a match score with their duels and rematch,
/// open invitations and „Kodla katıl“ as fallback. The opponent's results come from the
/// duel space (``DuelSync``); manual entry exists only without an iCloud account.
struct QuizDuelScreen: View {
    @Environment(\.theme) private var theme
    @Environment(UserStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @State private var area: QuizArea?
    @State private var newCode: String?
    @State private var entered = ""
    @State private var editing: Duello?
    private let syncer = DuelSync.shared

    /// A duel has 10 questions.
    static let length = 10

    var body: some View {
        @Bindable var a = settings
        let _ = store.version
        let list = store.duels()
        let groups = Dictionary(grouping: list.filter { !$0.karsiAd.isEmpty }, by: \.karsiAd)
            .sorted { ($0.value.first?.tarih ?? .distantPast) > ($1.value.first?.tarih ?? .distantPast) }
        let pending = list.filter { $0.karsiAd.isEmpty }
        ScrollViewReader { scroll in
            List {
                Section {
                    TextField(localized("quiz.duello.adin.yer"), text: $a.duelName)
                        .textContentType(.givenName)
                } header: {
                    Text(app: "quiz.duello.adin")
                } footer: {
                    Text(app: "quiz.duello.adin.aciklama")
                }
                Section {
                    Picker(localized("quiz.alan"), selection: $area) {
                        Text(app: "quiz.karisik").tag(QuizArea?.none)
                        ForEach(QuizArea.generated) { a in Text(verbatim: a.name).tag(QuizArea?.some(a)) }
                    }
                    Button(localized("quiz.duello.davet_et")) { invite(area) }
                        .foregroundStyle(theme.colors.accent)
                        .disabled(settings.duelName.isEmpty)
                    if let k = newCode { inviteCard(k) }
                } header: {
                    Text(app: "quiz.duello.yeni")
                } footer: {
                    Text(app: "quiz.duello.aciklama")
                }
                .id("yeni")
                ForEach(groups, id: \.key) { name, l in
                    Section {
                        scoreCard(name, l)
                        ForEach(l) { d in duelRow(d) }
                            .onDelete { i in i.map { l[$0] }.forEach(store.deleteDuel) }
                        Button(localized("quiz.duello.rovans")) {
                            invite(l.first.flatMap { QuizArea(rawValue: $0.alan) })
                            withAnimation { scroll.scrollTo("yeni", anchor: .top) }
                        }
                        .foregroundStyle(theme.colors.accent)
                        .disabled(settings.duelName.isEmpty)
                    }
                }
                if !pending.isEmpty {
                    Section {
                        ForEach(pending) { d in duelRow(d) }
                            .onDelete { i in i.map { pending[$0] }.forEach(store.deleteDuel) }
                    } header: {
                        Text(app: "quiz.duello.bekleyen")
                    } footer: {
                        if syncer.noAccount { Text(app: "quiz.duello.icloud_yok") }
                    }
                }
                Section {
                    TextField(localized("quiz.duello.kod_gir"), text: $entered)
                        #if os(iOS)
                            .textInputAutocapitalization(.characters)
                        #endif
                        .autocorrectionDisabled()
                        .monospaced()
                    NavigationLink(value: Goal.quizGame("duello:\(entered)")) {
                        Text(app: "quiz.duello.katil")
                    }
                    .disabled(DuelCode.parse(entered) == nil)
                } header: {
                    Text(app: "quiz.duello.kodla")
                }
            }
        }
        .pageBackground()
        .navigationTitle(Text(app: "quiz.duello"))
        .sheet(item: $editing) { d in OpponentResultSheet(duello: d) }
        .task { await syncer.update(store) }
        .refreshable { await syncer.update(store) }
    }

    private func invite(_ a: QuizArea?) {
        newCode = DuelCode.create(
            seed: UInt64.random(in: 0..<DuelCode.seedTop), area: a, length: Self.length)
    }

    private func inviteCard(_ k: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: DuelCode.formatted(k)).typography(.title1).monospaced()
                .foregroundStyle(theme.colors.accent)
                .textSelection(.enabled)
            ShareLink(
                item: localized("quiz.duello.davet \(DuelCode.formatted(k))")
                    + "\nkiblegah://quiz/duello/\(k)"
            ) {
                Label(localized("quiz.duello.davet_gonder"), systemImage: "square.and.arrow.up")
            }
            .frame(minHeight: 44)
            NavigationLink(value: Goal.quizGame("duello:\(k)")) { Text(app: "quiz.duello.oyna") }
                .buttonStyle(PrimaryButton())
        }
        .padding(.vertical, 6)
    }

    /// Overall standing against one person across all duels that both have finished.
    private func scoreCard(_ name: String, _ l: [Duello]) -> some View {
        var ben = 0
        var o = 0
        for d in l {
            guard let k = d.karsiDogru, let t = store.quizRound(d.tur), t.isFinished else { continue }
            if t.dogruSayisi > k { ben += 1 } else if t.dogruSayisi < k { o += 1 }
        }
        return HStack {
            DuelAvatar(name: settings.duelName, color: theme.colors.sage)
            Spacer()
            VStack(spacing: 2) {
                Text(verbatim: "\(ben) : \(o)").typography(.title1).monospacedDigit().foregroundStyle(
                    theme.colors.text)
                Text(app: "quiz.duello.sayisi \(l.count)").typography(.footnote).foregroundStyle(
                    theme.colors.text2)
            }
            Spacer()
            DuelAvatar(name: name, color: theme.colors.accent)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localized("quiz.duello.skor.sesli \(ben) \(name) \(o)"))
    }

    private func duelRow(_ d: Duello) -> some View {
        let t = store.quizRound(d.tur)
        let areaName = QuizArea(rawValue: d.alan)?.name ?? localized("quiz.karisik")
        let opponent = d.karsiAd.isEmpty ? localized("quiz.duello.karsi") : d.karsiAd
        let status: String
        var result: String?
        if t?.isFinished != true {
            status =
                d.karsiDogru != nil
                ? localized("quiz.duello.sira_sende.bitirdi \(opponent)")
                : localized("quiz.duello.sira_sende")
        } else if let k = d.karsiDogru, let t {
            status = localized("quiz.duello.sonuc \(t.dogruSayisi) \(opponent) \(k)")
            result = localized(
                t.dogruSayisi > k
                    ? "quiz.duello.kazandin"
                    : t.dogruSayisi < k ? "quiz.duello.kaybettin" : "quiz.duello.berabere")
        } else {
            status =
                d.karsiAd.isEmpty
                ? localized("quiz.duello.rakip_bekleniyor") : localized("quiz.duello.bekleniyor \(opponent)")
        }
        return NavigationLink(value: Goal.quizGame("duello:\(d.kod)")) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: "\(areaName) · \(d.uzunluk)").typography(.emphasized).foregroundStyle(
                        theme.colors.text)
                    Text(verbatim: status).typography(.footnote).foregroundStyle(theme.colors.text2)
                }
                Spacer()
                if t?.isFinished != true {
                    Text(app: "quiz.duello.oyna.kisa").typography(.footnote).bold().foregroundStyle(
                        theme.colors.accent
                    )
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(theme.colors.accent.opacity(0.12), in: .capsule)
                } else if let result {
                    Text(verbatim: result).typography(.footnote).foregroundStyle(theme.colors.text2)
                }
            }
        }
        .swipeActions(edge: .leading) {
            if syncer.noAccount {
                Button(localized("quiz.duello.karsi_gir")) { editing = d }
            }
        }
    }
}

/// Circle with initial letter and name below it.
struct DuelAvatar: View {
    @Environment(\.theme) private var theme
    let name: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(verbatim: String(name.prefix(1)).uppercased()).font(.headline).foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(color, in: .circle)
            Text(verbatim: name).typography(.footnote).foregroundStyle(theme.colors.text2).lineLimit(1)
        }
        .frame(width: 80)
    }
}

/// Enter the opponent's result by hand.
struct OpponentResultSheet: View {
    @Environment(UserStore.self) private var store
    @Environment(\.dismiss) private var close
    let duello: Duello
    @State private var name = ""
    @State private var correct = 0

    var body: some View {
        NavigationStack {
            Form {
                TextField(localized("quiz.duello.karsi_ad"), text: $name)
                Stepper(value: $correct, in: 0...duello.uzunluk) {
                    Text(app: "quiz.duello.karsi_dogru \(correct) \(duello.uzunluk)")
                }
            }
            .pageBackground()
            .navigationTitle(Text(verbatim: DuelCode.formatted(duello.kod)))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("quiz.kaydet")) {
                        store.updateDuel(duello, opponentName: name, opponentCorrect: correct)
                        close()
                    }
                }
                ToolbarItem(placement: .cancellationAction) { Button(localized("quiz.vazgec")) { close() } }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            name = duello.karsiAd
            correct = duello.karsiDogru ?? 0
        }
    }
}

/// Geçmiş: all answers of the last seven days, correct/wrong per area, four quiet
/// badges (never shareable) and „Verlauf löschen“.
struct QuizHistoryScreen: View {
    @Environment(\.theme) private var theme
    @Environment(UserStore.self) private var store
    @Environment(\.contentProvider) private var contentProvider
    @State private var confirmDelete = false

    var body: some View {
        let _ = store.version
        let today = QuizDay.today()
        let days = (0..<7).reversed().map { today.added(-$0) }
        let dayCounters = store.quizDayCounters(ab: days[0].description)
        let areaCounters = store.quizAreaCounters()
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    WeekBars(days: days, counters: dayCounters, height: 130)
                    WeekSummary(days: days, counters: dayCounters)
                }
                .padding(.vertical, 6)
            } header: {
                Text(app: "quiz.gecmis.hafta")
            }
            Section {
                // Fixed areas, plus every bank in which something has already been played.
                let banks = areaCounters.keys.compactMap(QuizArea.init(rawValue:)).filter {
                    !QuizArea.allCases.contains($0)
                }
                ForEach(QuizArea.allCases + banks.sorted { $0.rawValue < $1.rawValue }) { a in
                    let s = areaCounters[a.rawValue] ?? QuizCounter()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: a.name).foregroundStyle(theme.colors.text)
                            Text(
                                verbatim: s.total == 0
                                    ? localized("quiz.alan.bos")
                                    : localized("quiz.alan.dogru_yanlis \(s.correct) \(s.wrong)")
                            )
                            .typography(.footnote).foregroundStyle(theme.colors.text2)
                        }
                        Spacer()
                        if s.total > 0 {
                            Text(
                                verbatim: s.ratio.formatted(
                                    .percent.precision(.fractionLength(0)).locale(AppLanguage.locale))
                            )
                            .monospacedDigit().foregroundStyle(theme.colors.text2)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text(app: "quiz.gecmis.alanlar")
            }
            Section {
                ForEach(badges, id: \.0) { key, earned in
                    Label {
                        Text(verbatim: localized(key: key)).foregroundStyle(
                            earned ? theme.colors.text : theme.colors.text2)
                    } icon: {
                        Image(systemName: earned ? "seal.fill" : "seal")
                            .foregroundStyle(earned ? theme.colors.kaaba : theme.colors.text2)
                    }
                    .accessibilityValue(localized(earned ? "quiz.rozet.var" : "quiz.rozet.yok"))
                }
            } header: {
                Text(app: "quiz.gecmis.rozetler")
            } footer: {
                Text(app: "quiz.gecmis.rozetler.alt")
            }
            Section {
                Button(localized("quiz.gecmis.sil"), role: .destructive) { confirmDelete = true }
            }
        }
        .pageBackground()
        .navigationTitle(Text(app: "quiz.gecmis"))
        .confirmationDialog(
            localized("quiz.gecmis.sil.soru"), isPresented: $confirmDelete, titleVisibility: .visible
        ) {
            Button(localized("quiz.gecmis.sil"), role: .destructive) { store.deleteQuizHistory() }
        }
    }

    /// Four quiet badges, only for learning goals.
    private var badges: [(String, Bool)] {
        let correct = store.correctQuestions()
        var juz30 = Set<Int>()
        var divineName = Set<Int>()
        var basic = 0
        for k in correct {
            if let p = QuizID.parse(k) {
                switch (p.kind, ContentKey(text: p.key)) {
                case (.translationSurah, .verse(let s, _)?) where s >= 78: juz30.insert(s)
                case (.divineNameMeaning, .divineName(let n)?), (.meaningDivineName, .divineName(let n)?):
                    divineName.insert(n)
                default: break
                }
            } else if let (b, id, _) = QuizID.decodeBank(k), b == QuizArea.ilmihal.rawValue,
                id.hasPrefix("abdest") || id.hasPrefix("namaz")
            {
                basic += 1
            }
        }
        let daily = store.quizRounds(cesit: "gunluk").filter(\.isFinished).count
        return [
            ("quiz.rozet.cuz30", juz30.count >= 37),
            ("quiz.rozet.esma", divineName.count >= 98),
            ("quiz.rozet.temel", basic >= 20),
            ("quiz.rozet.otuz", daily >= 30),
        ]
    }
}

/// Ayarlar → Quiz: weekly goal, note on the school of law, review of the İlmihal drafts.
struct QuizSettingsScreen: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var a = settings
        Form {
            Section {
                Stepper(value: $a.quizGoal, in: 3...7) {
                    Text(app: "quiz.ayar.hedef \(settings.quizGoal)")
                }
            } footer: {
                Text(app: "quiz.ayar.hedef.alt")
            }
            Section {
                Text(app: "quiz.ayar.mezhep").typography(.secondary)
            }
            SlotView(.quizSettings)

        }
        .pageBackground()
        .navigationTitle(Text(app: "sekme.quiz"))
    }
}
