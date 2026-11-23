import CloudKit
import Foundation

/// Shared duel room in the public CloudKit database (package 5, variant D).
///
/// Two records per duel with a fixed name, `duello-<code>-A` (who challenges) and `…-B` (who
/// accepts). Each app writes only its own; in the public database only the
/// creator may change a record, hence no shared one. Reading is by name, not by
/// query: so the schema needs no queryable index, and a third participant gets an error
/// instead of a silent overwrite when writing to a foreign B record.
///
/// Only what the comparison needs is written: the self-chosen name, per question correct or
/// wrong, and whether the round is finished. No Apple ID, no device.
public enum DuelRoom {
    public enum Side: String, Sendable, CaseIterable {
        case a = "A", b = "B"
    }

    /// A player in the room.
    public struct Player: Sendable, Equatable {
        public var name: String
        /// Per slot: `true` correct, `false` wrong, `nil` still open.
        public var answers: [Bool?]
        public var finished: Bool
        public var mine: Bool

        public init(name: String, answers: [Bool?], finished: Bool, mine: Bool = false) {
            self.name = name
            self.answers = answers
            self.finished = finished
            self.mine = mine
        }

        public var correct: Int { answers.filter { $0 == true }.count }
    }

    public enum DuelError: Error, Equatable {
        /// Both slots already belong to others.
        case full
        /// No iCloud account on the device.
        case noAccount
    }

    static let kind = "Duello"
    static var database: CKDatabase {
        CKContainer(identifier: "iCloud.dev.ms-solutions.kiblegah").publicCloudDatabase
    }

    static func identifier(_ code: String, _ t: Side) -> CKRecord.ID {
        CKRecord.ID(recordName: "duello-\(code)-\(t.rawValue)")
    }

    /// `"10-1"`: 1 correct, 0 wrong, `-` open.
    static func text(_ c: [Bool?]) -> String { String(c.map { $0.map { $0 ? "1" : "0" } ?? "-" }) }
    static func answers(_ s: String) -> [Bool?] {
        s.map { $0 == "1" ? true : $0 == "0" ? false : nil }
    }

    /// Reads both slots; missing ones are missing from the result.
    public static func load(code: String) async throws -> [Side: Player] {
        let db = database
        let ben = try? await CKContainer(identifier: "iCloud.dev.ms-solutions.kiblegah").userRecordID()
        let result = try await db.records(for: Side.allCases.map { identifier(code, $0) })
        var l: [Side: Player] = [:]
        for t in Side.allCases {
            guard case .success(let r)? = result[identifier(code, t)] else { continue }
            l[t] = Player(
                name: r["ad"] as? String ?? "", answers: answers(r["cevaplar"] as? String ?? ""),
                finished: (r["bitti"] as? Int64 ?? 0) == 1,
                mine: r.creatorUserRecordID?.recordName == CKCurrentUserDefaultName
                    || (ben != nil && r.creatorUserRecordID == ben))
        }
        return l
    }

    /// Writes the own state. Without a fixed slot the app takes A if free, otherwise B; a slot
    /// that belongs to someone else is skipped. Returns the slot.
    @discardableResult
    public static func save(
        code: String, name: String, answers c: [Bool?], finished: Bool, taraf: Side? = nil
    )
        async throws -> Side
    {
        let db = database
        let container = CKContainer(identifier: "iCloud.dev.ms-solutions.kiblegah")
        guard (try? await container.accountStatus()) == .available else { throw DuelError.noAccount }
        let ben = try await container.userRecordID()
        for t in taraf.map({ [$0] }) ?? Side.allCases {
            let id = identifier(code, t)
            let r: CKRecord
            do {
                r = try await db.record(for: id)
                guard
                    r.creatorUserRecordID == ben
                        || r.creatorUserRecordID?.recordName == CKCurrentUserDefaultName
                else { continue }
            } catch let e as CKError where e.code == .unknownItem {
                r = CKRecord(recordType: kind, recordID: id)
            }
            r["kod"] = code
            r["ad"] = name
            r["cevaplar"] = text(c)
            r["bitti"] = finished ? 1 : 0
            do {
                _ = try await db.modifyRecords(saving: [r], deleting: [], savePolicy: .allKeys)
                return t
            } catch let e as CKError where e.code == .permissionFailure || e.code == .serverRecordChanged {
                continue
            }
        }
        throw DuelError.full
    }
}
