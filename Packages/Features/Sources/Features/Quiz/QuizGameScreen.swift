import ContentPacks
import Core
import DesignSystem
import SwiftUI
import UserData

/// A round: loads it, shows question by question (variant A „Kart“) and the result at the end.
struct QuizGameScreen: View {
    @Environment(\.contentProvider) private var contentProvider
    @Environment(\.theme) private var theme
    @Environment(UserStore.self) private var store
    @Environment(AppSettings.self) private var settings
    let request: String
    @State private var session: QuizSession?
    @State private var text: QuizText?
    @State private var empty = false
    @State private var showResult = false

    var body: some View {
        Group {
            if let session, let text {
                if session.finished && showResult {
                    QuizResultScreen(session: session, text: text)
                } else if session.kind.cesit == "duello" && settings.duelName.isEmpty {
                    DuelNamePrompt()
                } else {
                    QuizQuestionScreen(session: session, text: text) { showResult = true }
                }
            } else if empty {
                EmptyState(title: "quiz.bos.baslik", explanation: "quiz.bos.aciklama")
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .pageBackground()
        .navigationTitle(Text(app: title))
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: request) { await prepare() }
    }

    private var title: LocalizedStringKey {
        switch QuizSession.Request(request) {
        case .day: "quiz.gunun_turu"
        case .repetition: "quiz.tekrar"
        case .duello: "quiz.duello"
        default: "quiz.alistirma"
        }
    }

    private func prepare() async {
        guard session == nil, let contentProvider, let i = QuizSession.Request(request) else {
            empty = session == nil
            return
        }
        let o = await QuizSession.prepare(
            i, contentProvider: contentProvider, store: store)
        text = QuizText(
            contentProvider: contentProvider,
            bank: await QuizBanks.questions())
        #if DEBUG
            // Screenshots without tapping: `-quizOtoCevap 3` answers three questions (option 0 each).
            if let o, UserDefaults.standard.object(forKey: "quizOtoCevap") != nil {
                let n = UserDefaults.standard.integer(forKey: "quizOtoCevap")
                for i in 0..<n where !o.finished {
                    if o.currentAnswer != nil { o.next() }
                    o.selection = i % 2
                    o.submitAnswer(store: store)
                }
                if UserDefaults.standard.bool(forKey: "quizOtoSec") { o.selection = 1 }
            }
        #endif
        session = o
        showResult = o?.finished ?? false
        // Claim the slot in the duel space immediately: the opponent sees „spielt gerade“.
        if let o, !settings.duelName.isEmpty {
            DuelSync.shared.gonder(o.kind, store: store, name: settings.duelName)
        }
        empty = o == nil
    }
}

/// Question screen variant A „Kart“: progress bars, area, question in the card, answers
/// stacked. First tap, then „Cevapla“ - so mistaken taps at the edge cost nothing. Then green/red and
/// the citation strip.
struct QuizQuestionScreen: View {
    @Environment(\.theme) private var theme
    @Environment(UserStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Bindable var session: QuizSession
    let text: QuizText
    let bitir: () -> Void
    @State private var transliterationOpen = false

    var body: some View {
        if let (_, question) = session.current {
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        progress
                        Text(verbatim: label(question)).typography(.footnote).textCase(.uppercase)
                            .foregroundStyle(theme.colors.label)
                        card(question)
                        options(question)
                        if let c = session.currentAnswer {
                            CitationStrip(question: question, text: text, isCorrect: c.correct).id("beleg")
                        }
                        mapButton
                    }
                    .padding(16)
                }
                .onChange(of: session.currentAnswer) { _, c in
                    if c != nil { withAnimation { scroll.scrollTo("beleg", anchor: .bottom) } }
                }
            }
            .sensoryFeedback(trigger: session.currentAnswer) { _, c in
                c.map { $0.correct ? .success : .error }
            }
            .onChange(of: session.index) { transliterationOpen = false }
        }
    }

    /// Area, for bank questions with topic (only the İlmihal topics are in the catalog; the other
    /// topics are names like „halid“ and would stay misspelled without transliteration, hence only there).
    private func label(_ s: QuizQuestion) -> String {
        guard s.area == .ilmihal, let topic = text.bankQuestion(s)?.topic else { return s.area.name }
        return [s.area.name, localized(key: "quiz.konu.\(topic)", fallback: topic.capitalized)].joined(
            separator: " · ")
    }

    /// One bar per question: filled when answered, the current one emphasized.
    private var progress: some View {
        HStack(spacing: 4) {
            ForEach(Array(session.questions.enumerated()), id: \.offset) { i, s in
                let c = session.answers[s.index]
                Capsule()
                    .fill(
                        c == nil
                            ? (i == session.index ? theme.colors.text2 : theme.colors.line)
                            : (c!.correct ? theme.colors.sage : theme.colors.accent)
                    )
                    .frame(height: 5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localized("quiz.ilerleme \(session.index + 1) \(session.questions.count)"))
    }

    @ViewBuilder
    private func card(_ s: QuizQuestion) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: text.title(s)).typography(.title2).foregroundStyle(theme.colors.text)
                    .accessibilityAddTraits(.isHeader)
                    .fixedSize(horizontal: false, vertical: true)
                content(s)
            }
        }
    }

    @ViewBuilder
    private func content(_ s: QuizQuestion) -> some View {
        switch s.topic {
        case .verse(let a):
            if let m = text.translationText(a) {
                Text(verbatim: quoted(m.text)).typography(.body).italic().foregroundStyle(theme.colors.text2)
                Text(verbatim: m.pack).typography(.footnote).foregroundStyle(theme.colors.text2)
            }
        case .divineName(let n) where s.kind == .meaningDivineName:
            Text(verbatim: quoted(text.divineName(n)?.meaning(text.language) ?? "")).typography(.body)
                .italic()
                .foregroundStyle(theme.colors.text2)
        case .divineName(let n):
            Text(verbatim: text.divineName(n)?.arabic ?? "").typography(.arabic(size: 30))
                .frame(maxWidth: .infinity, alignment: .trailing).accessibilityHidden(true)
        case .hadith(let n):
            if let h = text.contentProvider.hadith(n, language: text.language) {
                Text(verbatim: quoted(h.title)).typography(.body).italic().foregroundStyle(theme.colors.text2)
            }
        case .dua(let slug):
            if let d = text.dua(slug) {
                Text(verbatim: d.arabic).typography(.arabic(size: 24)).multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing).accessibilityHidden(true)
                if s.kind == .duaCategory || s.kind == .duaSurah {
                    Text(verbatim: d.translation).typography(.secondary).foregroundStyle(theme.colors.text2)
                }
            }
        case .word(let k):
            wordVerse(k, s)
        default:
            EmptyView()
        }
    }

    /// The verse with a gap; the chosen tile fills it. „Okunuş“ as an aid.
    @ViewBuilder
    private func wordVerse(_ k: ContentKey, _ s: QuizQuestion) -> some View {
        if case .word(let su, let n, let index) = k,
            let verse = text.contentProvider.verse(.verse(surah: su, verse: n))
        {
            let selected: String? = (session.currentAnswer?.selection ?? session.selection).flatMap { i in
                s.options.indices.contains(i) ? text.option(s.options[i], question: s) : nil
            }
            let parts = verse.words.map { w -> String in
                guard case .word(_, _, let i) = w.key, i == index else { return w.text }
                return selected.map { "[\($0)]" } ?? "[ … ]"
            }
            Text(verbatim: parts.joined(separator: " ")).typography(.arabic(size: 28))
                .environment(\.layoutDirection, .rightToLeft)
                .multilineTextAlignment(.trailing).frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel(localized("quiz.kelime.sesli"))
            Text(verbatim: "\(text.surahName(su)) \(su):\(n)").typography(.footnote).foregroundStyle(
                theme.colors.text2)
            if let o = text.contentProvider.transliteration(
                .verse(surah: su, verse: n), language: transliterationLanguage(settings))
            {
                if transliterationOpen {
                    Text(verbatim: o.text).typography(.secondary).italic().foregroundStyle(theme.colors.text2)
                } else {
                    Button(localized("quiz.okunus_goster")) { transliterationOpen = true }
                        .typography(.secondary).frame(minHeight: 44)
                }
            }
        }
    }

    @ViewBuilder
    private func options(_ s: QuizQuestion) -> some View {
        let answer = session.currentAnswer
        if s.format == .wordTiles {
            // Tiles: Arabic large, at least 44 pt each.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                ForEach(Array(s.options.enumerated()), id: \.offset) { i, o in
                    optionButton(i, text.option(o, question: s), question: s, answer: answer, arabic: true)
                }
            }
            .environment(\.layoutDirection, .rightToLeft)
        } else {
            VStack(spacing: 10) {
                ForEach(Array(s.options.enumerated()), id: \.offset) { i, o in
                    optionButton(i, text.option(o, question: s), question: s, answer: answer, arabic: false)
                }
            }
        }
    }

    private func optionButton(
        _ i: Int, _ typography: String, question s: QuizQuestion, answer: QuizSession.Answer?, arabic: Bool
    ) -> some View {
        let correct = i == s.correct
        let selected = answer?.selection == i || (answer == nil && session.selection == i)
        let background: Color =
            answer == nil
            ? (selected ? theme.colors.surface : theme.colors.surface2)
            : (correct
                ? theme.colors.successBackground
                : (selected ? theme.colors.errorBackground : theme.colors.surface2))
        let color: Color =
            answer == nil
            ? theme.colors.text
            : (correct ? theme.colors.successText : (selected ? theme.colors.errorText : theme.colors.text))
        return Button {
            session.selection = i
        } label: {
            HStack(spacing: 8) {
                if arabic {
                    Text(verbatim: typography).typography(.arabic(size: 26)).frame(maxWidth: .infinity)
                } else {
                    Text(verbatim: typography).multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if answer != nil && correct {
                    Image(systemName: "checkmark.circle.fill").accessibilityHidden(true)
                } else if answer != nil && selected {
                    Image(systemName: "xmark.circle.fill").accessibilityHidden(true)
                }
            }
            .typography(selected || (answer != nil && correct) ? .emphasized : .body)
            .foregroundStyle(color)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: arabic ? 56 : 52)
            .background(background, in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(selected && answer == nil ? theme.colors.accent : .clear, lineWidth: 2)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // Not `.disabled`: that also fades the correct answer marked green.
        .allowsHitTesting(answer == nil)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(
            answer == nil
                ? ""
                : [
                    correct ? localized("bugun.soru.dogru_cevap") : nil,
                    selected ? localized("bugun.soru.secimin") : nil,
                ]
                .compactMap { $0 }.joined(separator: ", "))
    }

    @ViewBuilder
    private var mapButton: some View {
        if session.currentAnswer == nil {
            Button(localized("quiz.cevapla")) {
                withAnimation(.easeOut(duration: 0.2)) { session.submitAnswer(store: store) }
                DuelSync.shared.gonder(session.kind, store: store, name: settings.duelName)
            }
            .buttonStyle(PrimaryButton())
            .disabled(session.selection == nil)
            .opacity(session.selection == nil ? 0.5 : 1)
        } else if session.finished {
            Button(localized("quiz.sonucu_gor")) { bitir() }.buttonStyle(PrimaryButton())
        } else {
            Button(localized("quiz.sonraki")) { withAnimation { session.next() } }.buttonStyle(
                PrimaryButton())
        }
    }
}

/// Adds quotation marks unless the text already brings its own (hadith texts, some translations).
public func quoted(_ s: String) -> String {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    let annotations: Set<Character> = ["\"", "«", "»", "„", "“", "”", "'"]
    if let first = t.first, annotations.contains(first) { return t }
    return "„\(t)“"
}

struct CitationStrip: View {
    @Environment(\.theme) private var theme
    let question: QuizQuestion
    let text: QuizText
    let isCorrect: Bool

    @ViewBuilder
    private func source(_ excerpt: String, _ place: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !excerpt.isEmpty {
                Text(verbatim: quoted(excerpt)).typography(.secondary).italic().foregroundStyle(
                    theme.colors.text2
                )
                .lineLimit(6).textSelection(.enabled)
            }
            if !place.isEmpty {
                Text(verbatim: place).typography(.footnote).foregroundStyle(theme.colors.text2)
            }
        }
    }

    var body: some View {
        let b = text.citation(question)
        let correctText =
            question.options.indices.contains(question.correct)
            ? text.option(question.options[question.correct], question: question) : ""
        VStack(alignment: .leading, spacing: 10) {
            Text(
                verbatim: isCorrect
                    ? localized("bugun.soru.dogru") : localized("bugun.soru.yanlis \(correctText)")
            )
            .typography(.emphasized).foregroundStyle(isCorrect ? theme.colors.successText : theme.colors.text)
            if !b.arabic.isEmpty {
                Text(verbatim: b.arabic).typography(.arabic(size: 22)).multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing).lineLimit(4).accessibilityHidden(true)
            }
            if question.kind == .bank {
                // Bank questions: per source the literal quotation and below it work, volume, page.
                source(b.excerpt, b.source)
                if let k = b.second { source(k.excerpt, k.source) }
            } else {
                if !b.excerpt.isEmpty {
                    Text(verbatim: b.excerpt).typography(.secondary).foregroundStyle(theme.colors.text2)
                        .lineLimit(6)
                }
                Text(verbatim: b.source).typography(.footnote).foregroundStyle(theme.colors.text2)
            }
            if let h = b.goal {
                NavigationLink(value: h) {
                    HStack(spacing: 4) {
                        Text(verbatim: b.mapButton)
                        Image(systemName: "chevron.right").font(.footnote.weight(.bold)).accessibilityHidden(
                            true)
                    }
                    .typography(.emphasized).foregroundStyle(theme.colors.accent).frame(minHeight: 44)
                    .contentShape(
                        .rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.surface, in: .rect(cornerRadius: 22))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 22)
                .fill(isCorrect ? theme.colors.sage : theme.colors.accent).frame(width: 5)
        }
    }
}

/// Once before the first duel: under which name the opponent sees you.
struct DuelNamePrompt: View {
    @Environment(\.theme) private var theme
    @Environment(AppSettings.self) private var settings
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(app: "quiz.duello.adin").typography(.title2).foregroundStyle(theme.colors.text)
            Text(app: "quiz.duello.adin.aciklama").typography(.secondary).foregroundStyle(theme.colors.text2)
            TextField(localized("quiz.duello.adin.yer"), text: $name)
                .textContentType(.givenName)
                .padding(14)
                .background(theme.colors.surface, in: .rect(cornerRadius: 14))
            Button(localized("quiz.devam")) {
                settings.duelName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .buttonStyle(PrimaryButton())
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Spacer()
        }
        .padding(20)
    }
}
