import ContentPacks
import Core
import DesignSystem
import PrayerTimes
import SwiftUI
import UserData

/// The question of the day (cockpit ): one question, three to four answers, then the source.
///
/// The question comes from `QuestionGenerator` and is the same for everyone on the same day. The first
/// answer is remembered (daily point „Soru“); wrong answers are not marked red but
/// quietly - it is about learning, not about losing.
struct QuestionOfTheDayCard: View {
    @Environment(\.contentProvider) private var contentProvider
    @Environment(UserStore.self) private var store
    @Environment(\.theme) private var theme
    let day: Day
    @State private var question: QuestionOfTheDay?

    var body: some View {
        let _ = store.version
        VStack(alignment: .leading, spacing: 10) {
            Text(app: "bugun.soru.baslik").typography(.footnote).textCase(.uppercase)
                .foregroundStyle(theme.colors.label)
            if let contentProvider, let question {
                let answer = store.questionAnswer(day: day.description)
                questionText(question, contentProvider)
                VStack(spacing: 8) {
                    ForEach(Array(question.options.enumerated()), id: \.offset) { i, s in
                        option(
                            i, s, question: question, selection: answer?.secim,
                            contentProvider: contentProvider)
                    }
                }
                if let answer {
                    result(
                        question, isCorrect: answer.secim == question.correct,
                        contentProvider: contentProvider)
                    continueButton
                }
            }
        }
        .task(id: day) { question = generate() }
    }

    private func generate() -> QuestionOfTheDay? {
        contentProvider.flatMap { Self.question(day: day, contentProvider: $0) }
    }

    /// The question of a day - the same calculation for the card and question 1 of the daily round.
    static func question(day: Day, contentProvider: any ContentProvider) -> QuestionOfTheDay? {
        let dayNumber = Int((day.start(.gmt).timeIntervalSince1970 / 86400).rounded(.down))
        return QuestionGenerator.generate(
            dayNumber: dayNumber, surahs: contentProvider.surahs(),
            divineNames: contentProvider.divineNames(),
            verses: VerseOfTheDay.list.filter { $0 != VerseOfTheDay.key(day) },
            language: translationLanguage())
    }

    @ViewBuilder
    private func questionText(_ s: QuestionOfTheDay, _ contentProvider: any ContentProvider) -> some View {
        switch (s.kind, s.topic) {
        case (.verseSurah, .verse(let a)):
            Text(app: "bugun.soru.ayet_suresi").typography(.emphasized).foregroundStyle(theme.colors.text)
            if let p = contentProvider.translations(language: translationLanguage()).first,
                let m = contentProvider.translation(a, pack: p.id)
            {
                Text(verbatim: "„\(m.text)“").typography(.body).italic().foregroundStyle(theme.colors.text2)
                    .lineLimit(5)
            }
        case (.verseCount, .surah(let number)):
            Text(app: "bugun.soru.ayet_sayisi \(surahName(number, contentProvider))").typography(.emphasized)
                .foregroundStyle(theme.colors.text)
        case (.divineNameMeaning, .divineName(let number)):
            let e = contentProvider.divineNames().first { $0.number == number }
            Text(app: "bugun.soru.esma \(divineNameLabel(e))").typography(.emphasized).foregroundStyle(
                theme.colors.text)
            if let e {
                Text(verbatim: e.arabic).typography(.arabic(size: 26)).foregroundStyle(theme.colors.text)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        case (.firstRevealed, _):
            Text(app: "bugun.soru.ilk_nazil").typography(.emphasized).foregroundStyle(theme.colors.text)
        default:
            Text(app: "bugun.soru.medeni").typography(.emphasized).foregroundStyle(theme.colors.text)
        }
    }

    private func option(
        _ i: Int, _ s: QuestionOfTheDay.Option, question: QuestionOfTheDay, selection: Int?,
        contentProvider: any ContentProvider
    ) -> some View {
        let answered = selection != nil
        let correct = i == question.correct
        let selected = i == selection
        return Button {
            withAnimation(.easeOut(duration: 0.2)) {
                let dayNumber = Int((day.start(.gmt).timeIntervalSince1970 / 86400).rounded(.down))
                store.answerQuestion(
                    day: day.description, selection: i, correct: correct,
                    question: QuizID.ofTheDay(dayNumber),
                    kind: store.dailyKind(day: day.description)?.kimlik ?? "",
                    area: QuizQuestion(ofTheDay: question, dayNumber: dayNumber).area.rawValue)
                if !correct {
                    store.addToReview(QuizQuestion(ofTheDay: question, dayNumber: dayNumber).reviewID)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(verbatim: text(s, contentProvider)).multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                if answered && correct {
                    Image(systemName: "checkmark.circle.fill").accessibilityHidden(true)
                } else if answered && selected {
                    Image(systemName: "xmark.circle").accessibilityHidden(true)
                }
            }
            .typography(answered && correct ? .emphasized : .body)
            .foregroundStyle(answered && correct ? theme.colors.successText : theme.colors.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(
                answered && correct ? theme.colors.successBackground : theme.colors.surface2,
                in: .rect(cornerRadius: 14)
            )
            .opacity(answered && !correct && !selected ? 0.6 : 1)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(answered)
        .accessibilityValue(
            answered
                ? [
                    correct ? localized("bugun.soru.dogru_cevap") : nil,
                    selected ? localized("bugun.soru.secimin") : nil,
                ]
                .compactMap { $0 }.joined(separator: ", ")
                : "")
    }

    @ViewBuilder
    private func result(
        _ s: QuestionOfTheDay, isCorrect: Bool, contentProvider: any ContentProvider
    ) -> some View {
        let correctText =
            s.options.indices.contains(s.correct) ? text(s.options[s.correct], contentProvider) : ""
        Text(
            verbatim: isCorrect
                ? localized("bugun.soru.dogru") : localized("bugun.soru.yanlis \(correctText)")
        )
        .typography(.emphasized).foregroundStyle(theme.colors.text)
        switch s.source {
        case .verse(let a):
            NavigationLink(value: Goal.verse(a)) {
                sourceRow(verseSource(a, kind: s.kind, contentProvider))
            }
            .buttonStyle(.plain)
        case .divineName(let number):
            NavigationLink(value: Goal.divineNameDetail(number)) {
                sourceRow(divineNameSource(number, contentProvider))
            }
            .buttonStyle(.plain)
        }
    }

    /// The daily question is question 1 of the daily round: continue with question 2.
    @ViewBuilder
    private var continueButton: some View {
        let kind = store.dailyKind(day: day.description)
        if kind?.isFinished == true {
            NavigationLink(value: Goal.quiz) {
                Label(localized("quiz.puan \(kind?.puan ?? 0)"), systemImage: "checkmark.seal")
            }
            .buttonStyle(SecondaryButton())
        } else {
            let remaining = (kind?.uzunluk ?? 10) - max(1, kind?.cevapSayisi ?? 1)
            NavigationLink(value: Goal.quizGame("gun")) {
                Text(verbatim: localized("quiz.devam_kalan \(remaining)"))
            }
            .buttonStyle(PrimaryButton())
        }
    }

    private func sourceRow(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(app: "bugun.soru.kaynak \(text)").multilineTextAlignment(.leading)
            Image(systemName: "chevron.right").font(.footnote.weight(.bold)).accessibilityHidden(true)
        }
        .typography(.secondary)
        .foregroundStyle(theme.colors.accent)
        .frame(minHeight: 44)
        .contentShape(.rect)
    }

    private func text(_ s: QuestionOfTheDay.Option, _ contentProvider: any ContentProvider) -> String {
        switch s {
        case .surah(let number): surahName(number, contentProvider)
        case .number(let n): n.formatted(.number.locale(AppLanguage.locale))
        case .divineName(let number):
            contentProvider.divineNames().first { $0.number == number }?.meaning(translationLanguage()) ?? ""
        }
    }

    private func surahName(_ number: Int, _ contentProvider: any ContentProvider) -> String {
        contentProvider.surah(number)?.name(language: translationLanguage()) ?? "\(number)"
    }

    /// In Turkish the reading according to Diyanet („Er-Rahmân“), otherwise the transliteration.
    private func divineNameLabel(_ e: DivineName?) -> String {
        guard let e else { return "" }
        return translationLanguage() == "tr" ? (e.transliterationTR ?? e.latin) : e.latin
    }

    /// „Bakara 2:286“; for place and order of revelation with a note on the Tanzil data.
    private func verseSource(
        _ a: ContentKey, kind: QuestionOfTheDay.Kind, _ contentProvider: any ContentProvider
    ) -> String {
        guard case .verse(let s, let n) = a else { return a.text }
        let place = "\(surahName(s, contentProvider)) \(s):\(n)"
        switch kind {
        case .medinanSurah, .firstRevealed: return "\(localized("bugun.soru.kaynak.tanzil")) · \(place)"
        default: return place
        }
    }

    private func divineNameSource(_ number: Int, _ contentProvider: any ContentProvider) -> String {
        let e = contentProvider.divineNames().first { $0.number == number }
        return [localized("sekme.esma"), divineNameLabel(e), e?.source].compactMap { $0 }.filter {
            !$0.isEmpty
        }
        .joined(separator: " · ")
    }
}
