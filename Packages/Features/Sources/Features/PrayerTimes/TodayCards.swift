import ContentPacks
import Core
import DesignSystem
import PrayerTimes
import SwiftUI
import UserData

/// The lower part of „Bugün“: daily points with streak, the reading week and the swipe stack.
///
/// `day` is the calendar day of the device - the same one by which reading, dhikr and the answer to
/// the question are counted; otherwise after a trip the question would stand on a different day than
/// its point.
struct TodayCards: View {
    @Environment(\.contentProvider) private var contentProvider
    @Environment(UserStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme
    let day: Day
    @State private var page: Int? = 0

    static let cardCount = 3

    var body: some View {
        let _ = store.version
        let n = store.dailyPoints()
        VStack(alignment: .leading, spacing: 16) {
            TodayCardsPoints(page: Binding(get: { page ?? 0 }, set: { page = $0 }), points: n)
            WeekReading(reading: store.weeklyReading())
            path
        }
    }

    /// The last reading position of the active reading state, otherwise of the default khatm.
    private var lastPosition: ContentKey? {
        (store.lastPosition(khatm: settings.activeKhatm) ?? store.lastPosition()).flatMap {
            ContentKey(text: $0)
        }
    }

    private var continueTarget: ContentKey { lastPosition ?? .verse(surah: 1, verse: 1) }

    // MARK: Swipe stack

    private var path: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(0..<Self.cardCount, id: \.self) { i in
                        Group {
                            switch i {
                            case 0: VerseOfTheDayCard(day: day)
                            case 1: QuestionOfTheDayCard(day: day)
                            default: ContinueCard(lastPosition: lastPosition)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(theme.colors.surface, in: .rect(cornerRadius: 22))
                        .containerRelativeFrame(.horizontal) { w, _ in max(200, w - 56) }
                        .accessibilityElement(children: .contain)
                        .id(i)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $page)
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollClipDisabled()
            .padding(.horizontal, -16)
            HStack(spacing: 8) {
                Text(app: "bugun.kaydir").typography(.footnote).foregroundStyle(theme.colors.text2)
                Spacer(minLength: 8)
                HStack(spacing: 5) {
                    ForEach(0..<Self.cardCount, id: \.self) { i in
                        Circle()
                            .fill(i == (page ?? 0) ? theme.colors.accent : theme.colors.text2.opacity(0.35))
                            .frame(width: 7, height: 7)
                    }
                }
                Text(verbatim: "\((page ?? 0) + 1) / \(Self.cardCount)").typography(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(theme.colors.text2)
            }
            .accessibilityHidden(true)
        }
    }
}

/// Daily points with the week and the streak: on the iPhone above the stack, on the iPad below the first screen.
struct TodayCardsPoints: View {
    @Environment(UserStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme
    @Binding var page: Int
    var points: DailyPoints? = nil

    private var lastPosition: ContentKey? {
        (store.lastPosition(khatm: settings.activeKhatm) ?? store.lastPosition()).flatMap {
            ContentKey(text: $0)
        }
    }

    private var continueTarget: ContentKey { lastPosition ?? .verse(surah: 1, verse: 1) }

    var body: some View {
        let _ = store.version
        points(points ?? store.dailyPoints())
    }

    private func points(_ n: DailyPoints) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    dotButtons(n)
                    Spacer(minLength: 4)
                    streak(n)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 14) { dotButtons(n) }
                    streak(n)
                }
            }
            HStack(spacing: 6) {
                ForEach(Array(n.week.enumerated()), id: \.offset) { i, full in
                    let today = i == n.week.count - 1
                    Circle()
                        .fill(full ? theme.colors.sage : .clear)
                        .strokeBorder(theme.colors.text2.opacity(full ? 0 : 0.35), lineWidth: 1.5)
                        .frame(width: 14, height: 14)
                        .padding(3)
                        .overlay {
                            if today { Circle().strokeBorder(theme.colors.text2, lineWidth: 1) }
                        }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(localized("bugun.hafta.sesli \(n.week.filter { $0 }.count)"))
        }
    }

    @ViewBuilder
    private func dotButtons(_ n: DailyPoints) -> some View {
        NavigationLink(value: Goal.verse(continueTarget)) {
            point("bugun.nokta.ayet", n.verse)
        }
        .buttonStyle(.plain)
        NavigationLink(value: Goal.dhikr) {
            point("bugun.nokta.zikir", n.dhikr)
        }
        .buttonStyle(.plain)
        // If the daily question is answered, „Soru“ opens the quiz section instead of just swiping to the card.
        if n.question {
            NavigationLink(value: Goal.quiz) {
                point("bugun.nokta.soru", n.question)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                withAnimation { page = 1 }
            } label: {
                point("bugun.nokta.soru", n.question)
            }
            .buttonStyle(.plain)
        }
    }

    private func point(_ key: String.LocalizationValue, _ done: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? theme.colors.sage : theme.colors.text2)
                .accessibilityHidden(true)
            Text(verbatim: localized(key)).typography(.secondary).foregroundStyle(theme.colors.text)
        }
        .frame(minHeight: 44)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityValue(localized(done ? "bugun.nokta.tamam" : "bugun.nokta.acik"))
    }

    @ViewBuilder
    private func streak(_ n: DailyPoints) -> some View {
        HStack(spacing: 4) {
            Image(systemName: n.streak > 0 ? "flame.fill" : "flame")
                .foregroundStyle(n.streak > 0 ? theme.colors.accent : theme.colors.text2)
                .accessibilityHidden(true)
            if n.streak > 0 {
                Text(app: "bugun.seri \(n.streak)").typography(.emphasized).foregroundStyle(
                    theme.colors.accent)
            } else {
                Text(app: "bugun.seri.basla").typography(.secondary).foregroundStyle(theme.colors.text2)
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            n.streak > 0 ? localized("bugun.seri.sesli \(n.streak)") : localized("bugun.seri.basla"))
    }
}

/// The reading week, counted positively (cockpit /): verses, minutes and reading days of this
/// week instead of „0 / 6.236“. Without reading there is an invitation, not a zero.
struct WeekReading: View {
    @Environment(\.theme) private var theme
    let reading: WeeklyReading

    var body: some View {
        NavigationLink(value: Goal.readingGoals) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(app: "bugun.okuma.baslik").typography(.footnote).textCase(.uppercase)
                        .foregroundStyle(theme.colors.label)
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.bold))
                        .foregroundStyle(theme.colors.text2).accessibilityHidden(true)
                }
                if reading.verse == 0 && reading.minutes == 0 {
                    Text(app: "bugun.okuma.bos").typography(.body).foregroundStyle(theme.colors.text)
                        .multilineTextAlignment(.leading)
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 12) { boxes }
                        VStack(alignment: .leading, spacing: 8) { boxes }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.colors.surface, in: .rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var boxes: some View {
        box(reading.verse, "bugun.okuma.ayet")
        box(reading.minutes, "bugun.okuma.dakika")
        box(reading.day, "bugun.okuma.gun")
    }

    private func box(_ number: Int, _ label: String.LocalizationValue) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: number.formatted(.number.locale(AppLanguage.locale))).typography(.title1)
                .foregroundStyle(theme.colors.text).monospacedDigit()
            Text(verbatim: localized(label)).typography(.footnote).foregroundStyle(theme.colors.text2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The verse of the day as first card of the stack: Arabic, translation, share.
struct VerseOfTheDayCard: View {
    @Environment(\.contentProvider) private var contentProvider
    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme
    let day: Day

    var body: some View {
        let a = VerseOfTheDay.key(day)
        if let contentProvider, case .verse(let s, let n) = a, let surah = contentProvider.surah(s),
            let verse = contentProvider.verse(a)
        {
            let pack = contentProvider.translations(language: translationLanguage()).first
            let translation = pack.flatMap { contentProvider.translation(a, pack: $0.id) }?.text ?? ""
            let surahName = surah.name(language: translationLanguage())
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    Text(app: "gunun_ayeti \(surahName) \(n)")
                        .typography(.footnote).textCase(.uppercase).foregroundStyle(theme.colors.label)
                    Spacer(minLength: 4)
                    ShareButton(
                        .verse(
                            arabic: verse.text, translation: translation,
                            source: "\(surahName) \(s):\(n) · \(pack?.title ?? "")",
                            surah: s, verse: n, parent: localized("gunun_ayeti \(surahName) \(n)"))
                    )
                    .frame(minWidth: 44, minHeight: 44)
                }
                NavigationLink(value: Goal.verse(a)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(verbatim: verse.text)
                            .typography(.arabic(size: min(settings.arabicSize, 28)))
                            .foregroundStyle(theme.colors.text)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text(verbatim: translation).typography(.emphasized).foregroundStyle(theme.colors.text)
                            .multilineTextAlignment(.leading)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint(localized("bugun.ayet.ac"))
            }
        }
    }
}

/// Continue reading: the last reading position of the active reading state, otherwise the beginning.
struct ContinueCard: View {
    @Environment(\.contentProvider) private var contentProvider
    @Environment(\.theme) private var theme
    let lastPosition: ContentKey?
    var showsTitle = true

    var body: some View {
        let goal = lastPosition ?? .verse(surah: 1, verse: 1)
        VStack(alignment: .leading, spacing: 10) {
            if showsTitle {
                Text(app: "kuran.kaldigin_yer").typography(.footnote).textCase(.uppercase)
                    .foregroundStyle(theme.colors.label)
            }
            if lastPosition != nil, let contentProvider, case .verse(let s, let n) = goal,
                let surah = contentProvider.surah(s)
            {
                Text(app: "kuran.kaldigin.ayet \(surah.name(language: translationLanguage())) \(n)")
                    .typography(.title2)
                    .foregroundStyle(theme.colors.text)
                if let p = contentProvider.translations(language: translationLanguage()).first,
                    let m = contentProvider.translation(goal, pack: p.id)
                {
                    Text(verbatim: m.text).typography(.body).foregroundStyle(theme.colors.text2).lineLimit(4)
                }
            } else {
                Text(app: "kuran.basla").typography(.title2).foregroundStyle(theme.colors.text)
                Text(app: "kuran.basla.alt").typography(.body).foregroundStyle(theme.colors.text2)
            }
            Spacer(minLength: 0)
            NavigationLink(value: Goal.verse(goal)) {
                Label(localized("bugun.devam.dugme"), systemImage: "book")
            }
            .buttonStyle(PrimaryButton())
        }
    }
}
