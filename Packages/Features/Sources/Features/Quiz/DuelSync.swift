import Foundation
import Observation
import UserData
import os

/// Keeps duels in sync with the public space (``DuelRoom``): own answers in, the opponent's
/// out. Replaces typing in the opponent's result (package 5, variant D).
///
/// Without an iCloud account everything stays local; then ``noAccount`` is set and the overview offers
/// manual entry again.
@MainActor @Observable final class DuelSync {
    static let shared = DuelSync()
    static let daily = Logger(subsystem: "dev.ms-solutions.kiblegah", category: "duello")

    /// Opponent per code, as last read.
    private(set) var opponents: [String: DuelRoom.Player] = [:]
    private(set) var noAccount = false
    private(set) var isLoading = false

    /// Writes the own state of a duel round. Errors stay silent; on the next answer
    /// or open it is written again.
    func gonder(_ kind: QuizTuru, store: UserStore, name: String) {
        guard kind.cesit == "duello", !kind.kod.isEmpty else { return }
        let c = store.answers(kind: kind.kimlik)
        let list: [Bool?] = (1...max(1, kind.uzunluk)).map { s in c.first { $0.sira == s }?.dogru }
        let code = kind.kod
        let finished = kind.isFinished
        Task {
            do {
                try await DuelRoom.save(code: code, name: name, answers: list, finished: finished)
                noAccount = false
            } catch DuelRoom.DuelError.noAccount {
                noAccount = true
            } catch {
                Self.daily.notice(
                    "yaz \(code, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Reads the opponent of all duels whose result is still missing (or only of the one code), and
    /// enters name and hits into the local ``Duello``.
    func update(_ store: UserStore, code: String? = nil) async {
        let list = store.duels().filter {
            code == nil ? $0.karsiDogru == nil || opponents[$0.kod] == nil : $0.kod == code
        }
        guard !list.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        await withTaskGroup(of: (String, [DuelRoom.Side: DuelRoom.Player]?).self) { g in
            for d in list {
                let k = d.kod
                g.addTask { (k, try? await DuelRoom.load(code: k)) }
            }
            for await (k, oda) in g {
                guard let oda, let opponent = oda.values.first(where: { !$0.mine }) else { continue }
                opponents[k] = opponent
                guard let d = list.first(where: { $0.kod == k }) else { continue }
                let correct = opponent.finished ? opponent.correct : nil
                if d.karsiAd != opponent.name || d.karsiDogru != correct {
                    store.updateDuel(d, opponentName: opponent.name, opponentCorrect: correct)
                }
            }
        }
    }
}
