import ContentPacks
import Core
import DesignSystem
import SwiftUI
import UserData

/// Result of a round (concept „Sonuç“): daily round with points, exercises only with rate. Per question
/// checkmark, citation and - for correct ones - „Tekrar'a ekle“; wrong ones are already in the review.
struct QuizResultScreen: View {
    @Environment(\.theme) private var theme
    @Environment(UserStore.self) private var store
    let session: QuizSession
    let text: QuizText
    @State private var shareImage: Image?
    @State private var rematchCode: String?
    @Environment(AppSettings.self) private var settings
    private let syncer = DuelSync.shared

    var body: some View {
        let _ = store.version
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    if session.kind.cesit == "gunluk" {
                        Text(app: "quiz.puan \(session.correctCount * QuizScoring.perPoint)").typography(
                            .accent
                        )
                        .foregroundStyle(theme.colors.text)
                    }
                    Text(verbatim: "\(session.correctCount) / \(session.questions.count)")
                        .typography(session.kind.cesit == "gunluk" ? .title2 : .accent).monospacedDigit()
                        .foregroundStyle(theme.colors.text)
                    Text(app: subtitle).typography(.secondary).foregroundStyle(theme.colors.text2)
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
                if session.kind.cesit == "duello" && syncer.opponents[session.kind.kod]?.finished != true {
                    duelShare
                }
            }
            if session.kind.cesit == "duello" { duelSection }
            Section {
                ForEach(session.questions, id: \.index) { s in
                    row(s.index, s.question)
                }
            } header: {
                Text(app: "quiz.sonuc.sorular")
            }
        }
        .pageBackground()
        .task {
            if session.kind.cesit == "duello" { await syncer.update(store, code: session.kind.kod) }
        }
        .refreshable {
            if session.kind.cesit == "duello" { await syncer.update(store, code: session.kind.kod) }
        }
    }

    // MARK: Düello (package 5, variant B "question by question")

    /// Both score rows, shared mistakes with citation and rematch. As long as the opponent is not
    /// finished, only their standing is shown; their answers stay hidden until you are finished yourself
    /// (always the case here, the screen only comes after your own round).
    @ViewBuilder private var duelSection: some View {
        let opponent = syncer.opponents[session.kind.kod]
        Section {
            if let opponent, opponent.finished {
                let ben = session.correctCount
                VStack(spacing: 4) {
                    Text(verbatim: "\(ben) : \(opponent.correct)").typography(.title1).monospacedDigit()
                        .foregroundStyle(theme.colors.text)
                    Text(
                        verbatim: ben > opponent.correct
                            ? localized("quiz.duello.kazandin")
                            : ben < opponent.correct
                                ? localized("quiz.duello.kazandi \(opponent.name)")
                                : localized("quiz.duello.berabere")
                    )
                    .typography(.secondary).foregroundStyle(theme.colors.text2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                dotRow(
                    localized("quiz.duello.sen"), session.questions.map { session.answers[$0.index]?.correct }
                )
                dotRow(
                    opponent.name,
                    session.questions.map { s in
                        opponent.answers.indices.contains(s.index - 1) ? opponent.answers[s.index - 1] : nil
                    })
            } else if let opponent {
                Text(
                    app:
                        "quiz.duello.devam_ediyor \(opponent.name) \(opponent.answers.compactMap { $0 }.count) \(opponent.answers.count)"
                )
                .typography(.secondary).foregroundStyle(theme.colors.text2)
            } else {
                Text(app: syncer.noAccount ? "quiz.duello.icloud_yok" : "quiz.duello.rakip_bekleniyor")
                    .typography(.secondary).foregroundStyle(theme.colors.text2)
            }
            if let k = rematchCode {
                ShareLink(
                    item: localized("quiz.duello.davet \(DuelCode.formatted(k))")
                        + "\nkiblegah://quiz/duello/\(k)"
                ) {
                    Label(localized("quiz.duello.davet_gonder"), systemImage: "square.and.arrow.up")
                }
                .frame(minHeight: 44)
                NavigationLink(value: Goal.quizGame("duello:\(k)")) { Text(app: "quiz.duello.oyna") }
            } else if opponent?.finished == true {
                Button(localized("quiz.duello.rovans")) {
                    rematchCode = DuelCode.create(
                        seed: UInt64.random(in: 0..<DuelCode.seedTop),
                        area: QuizArea(rawValue: session.kind.alan), length: QuizDuelScreen.length)
                }
                .foregroundStyle(theme.colors.accent)
                .frame(minHeight: 44)
            }
        } header: {
            Text(app: "quiz.duello")
        }
        if let opponent, opponent.finished {
            let shared = session.questions.filter { s in
                session.answers[s.index]?.correct == false && opponent.answers.indices.contains(s.index - 1)
                    && opponent.answers[s.index - 1] == false
            }
            if !shared.isEmpty {
                Section {
                    ForEach(shared, id: \.index) { s in row(s.index, s.question) }
                } header: {
                    Text(app: "quiz.duello.ortak_hatalar \(shared.count)")
                } footer: {
                    Text(app: "quiz.duello.ortak_hatalar.alt \(opponent.name)")
                }
            }
        }
    }

    private func dotRow(_ name: String, _ l: [Bool?]) -> some View {
        HStack {
            Text(verbatim: name).typography(.emphasized).foregroundStyle(theme.colors.text).lineLimit(1)
            Spacer()
            HStack(spacing: 4) {
                ForEach(Array(l.enumerated()), id: \.offset) { _, d in
                    Circle()
                        .fill(
                            d == true
                                ? theme.colors.sage
                                : d == false ? theme.colors.accent.opacity(0.75) : theme.colors.line
                        )
                        .frame(width: 14, height: 14)
                }
            }
            Text(verbatim: "\(l.filter { $0 == true }.count)").typography(.emphasized).monospacedDigit()
                .foregroundStyle(theme.colors.text).frame(minWidth: 22, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            localized("quiz.duello.nokta.sesli \(name) \(l.filter { $0 == true }.count) \(l.count)"))
    }

    private var subtitle: LocalizedStringKey {
        switch session.kind.cesit {
        case "gunluk": "quiz.sonuc.gunluk"
        case "duello": "quiz.sonuc.duello"
        case "tekrar": "quiz.sonuc.tekrar"
        default: "quiz.sonuc.alistirma"
        }
    }

    private func row(_ index: Int, _ s: QuizQuestion) -> some View {
        let c = session.answers[index]
        let b = text.citation(s)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: c?.correct == true ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(c?.correct == true ? theme.colors.sage : theme.colors.accent)
                    .accessibilityLabel(localized(c?.correct == true ? "quiz.dogru" : "quiz.yanlis"))
                Text(verbatim: text.title(s)).typography(.body).foregroundStyle(theme.colors.text).lineLimit(
                    3)
            }
            Text(verbatim: b.source).typography(.footnote).foregroundStyle(theme.colors.text2)
            HStack(spacing: 16) {
                if let h = b.goal {
                    NavigationLink(value: h) { Text(app: "quiz.beleg") }
                        .buttonStyle(.plain).foregroundStyle(theme.colors.accent).typography(.secondary)
                        .frame(minHeight: 44)
                }
                let k = s.reviewID
                if c?.correct == true && !store.isInReview(k) {
                    Button(localized("quiz.tekrara_ekle")) { store.addToReview(k) }
                        .buttonStyle(.plain).foregroundStyle(theme.colors.accent).typography(.secondary)
                        .frame(minHeight: 44)
                } else if store.isInReview(k) {
                    Label(localized("quiz.tekrarda"), systemImage: "arrow.counterclockwise").typography(
                        .footnote
                    )
                    .foregroundStyle(theme.colors.text2)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Result card of the duel as image and text with code; sharing only on tap.
    @ViewBuilder
    private var duelShare: some View {
        let code = DuelCode.formatted(session.kind.kod)
        let area = QuizArea(rawValue: session.kind.alan)?.name ?? localized("quiz.karisik")
        let shareText =
            localized(
                "quiz.duello.paylas_sonuc \(session.correctCount) \(session.questions.count) \(area) \(code)")
            + "\nkiblegah://quiz/duello/\(session.kind.kod)"
        if let shareImage {
            ShareLink(
                item: shareImage, message: Text(verbatim: shareText),
                preview: SharePreview(Text(app: "quiz.duello"), image: shareImage)
            ) {
                Label(localized("quiz.duello.sonucu_paylas"), systemImage: "square.and.arrow.up")
            }
            .frame(minHeight: 44)
        } else {
            ShareLink(item: shareText) {
                Label(localized("quiz.duello.sonucu_paylas"), systemImage: "square.and.arrow.up")
            }
            .frame(minHeight: 44)
            .task { prepareImage(code: code, area: area) }
        }
    }

    @MainActor private func prepareImage(code: String, area: String) {
        let card = DuelCard(
            correct: session.correctCount, total: session.questions.count, area: area, code: code
        ).environment(\.theme, theme)
        let r = ImageRenderer(content: card)
        r.scale = 3
        if let g = r.cgImage { shareImage = Image(decorative: g, scale: 3) }
    }
}

/// The shared result card: hits, rate, area, code - no answers.
struct DuelCard: View {
    @Environment(\.theme) private var theme
    let correct: Int
    let total: Int
    let area: String
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: "Kıblegâh · \(localized("quiz.duello"))").typography(.footnote).textCase(
                .uppercase
            )
            .foregroundStyle(theme.colors.label)
            Text(app: "quiz.puan \(correct * QuizScoring.perPoint)").typography(.accent).foregroundStyle(
                theme.colors.text)
            Text(verbatim: "\(correct) / \(total) · \(area)").typography(.title2).foregroundStyle(
                theme.colors.text)
            Text(verbatim: code).typography(.title1).monospaced().foregroundStyle(theme.colors.accent)
        }
        .padding(28)
        .frame(width: 360, alignment: .leading)
        .background(theme.colors.surface)
    }
}
