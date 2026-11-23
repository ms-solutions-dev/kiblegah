import Core
import Foundation
import Observation

@MainActor @Observable public final class AudioStore {
    public enum LoadStatus: Equatable, Sendable {
        case yok
        case downloading(Double)
        case ready
    }

    public private(set) var states: [String: LoadStatus] = [:]
    let root: URL
    private let session: URLSession
    private var tasks: [String: Task<Void, Never>] = [:]

    public init(root: URL? = nil, session: URLSession = .shared) {
        self.root = root ?? Self.defaultRoot()
        self.session = session
    }

    /// Are the recitations in the app's own `Application Support` (without App Group)? For Depolama.
    public var rootInApp: Bool {
        root.path(percentEncoded: false).hasPrefix(
            URL.applicationSupportDirectory.path(percentEncoded: false))
    }

    /// The folder in the App Group; without a group (tests, macOS) the old one in the app's own `Application Support`.
    nonisolated static func defaultRoot() -> URL {
        let old = URL.applicationSupportDirectory.appending(path: "Sesler")
        guard
            let group = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: AppLanguage.appGroup)
        else { return old }
        let yeni = group.appending(path: "Library/Application Support/Sesler")
        migrate(old, yeni)
        return yeni
    }

    /// Move once: if the new folder is missing, the old one is renamed; if both exist, every
    /// file missing in the new one is moved over. The old folder only disappears when no file is left in it
    /// (duplicates in the new one are removed beforehand). Same volume, so fast.
    nonisolated static func migrate(_ old: URL, _ yeni: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: old.path(percentEncoded: false)) else { return }
        try? fm.createDirectory(at: yeni.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: yeni.path(percentEncoded: false)) {
            try? fm.moveItem(at: old, to: yeni)
        } else {
            let rootPath = old.standardizedFileURL.path(percentEncoded: false)
            let files =
                fm.enumerator(at: old, includingPropertiesForKeys: [.isRegularFileKey])?
                .compactMap { $0 as? URL } ?? []
            for d in files
            where (try? d.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                let path = d.standardizedFileURL.path(percentEncoded: false)
                guard path.hasPrefix(rootPath) else { continue }
                let goal = yeni.appending(path: String(path.dropFirst(rootPath.count)))
                // If the file is already in the group, the old one is a duplicate and may go.
                guard !fm.fileExists(atPath: goal.path(percentEncoded: false)) else {
                    try? fm.removeItem(at: d)
                    continue
                }
                try? fm.createDirectory(
                    at: goal.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fm.moveItem(at: d, to: goal)
            }
            // Only delete what is really empty: if a move failed, the file stays where it is.
            let remaining =
                fm.enumerator(at: old, includingPropertiesForKeys: [.isRegularFileKey])?
                .compactMap { $0 as? URL }
                .contains { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
                ?? false
            if !remaining { try? fm.removeItem(at: old) }
        }
        var fallback = URLResourceValues()
        fallback.isExcludedFromBackup = true
        var y = yeni
        try? y.setResourceValues(fallback)
    }

    static func key(_ k: Reciter, _ surah: Int) -> String { "\(k.id).\(surah)" }

    public func local(_ k: Reciter, surah: Int, verse: Int) -> URL {
        root.appending(path: k.id).appending(path: Reciter.fileName(surah: surah, verse: verse))
    }

    public func exists(_ k: Reciter, surah: Int, verse: Int) -> Bool {
        FileManager.default.fileExists(
            atPath: local(k, surah: surah, verse: verse).path(percentEncoded: false))
    }

    public func status(_ k: Reciter, surah: Int, verseCount: Int) -> LoadStatus {
        if let d = states[Self.key(k, surah)], case .downloading = d { return d }
        return (1...verseCount).allSatisfy { exists(k, surah: surah, verse: $0) } ? .ready : .yok
    }

    /// Downloads a surah verse by verse; aborts on network error and leaves finished files in place.
    public func download(_ k: Reciter, surah: Int, verseCount: Int) {
        let a = Self.key(k, surah)
        // Surah files (tamSure) are streamed, not downloaded verse by verse.
        guard tasks[a] == nil, k.fullSurah == nil else { return }
        states[a] = .downloading(0)
        tasks[a] = Task {
            defer { tasks[a] = nil }
            let folder = root.appending(path: k.id)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var fallback = URLResourceValues()
            fallback.isExcludedFromBackup = true
            var rootURL = root
            try? rootURL.setResourceValues(fallback)
            for verse in 1...verseCount {
                if Task.isCancelled { break }
                if !exists(k, surah: surah, verse: verse) {
                    guard
                        let (temporary, answer) = try? await session.download(
                            from: k.remote(surah: surah, verse: verse)),
                        (answer as? HTTPURLResponse)?.statusCode == 200
                    else {
                        states[a] = .yok
                        return
                    }
                    try? FileManager.default.moveItem(at: temporary, to: local(k, surah: surah, verse: verse))
                }
                states[a] = .downloading(Double(verse) / Double(verseCount))
            }
            states[a] = status(k, surah: surah, verseCount: verseCount) == .ready ? .ready : .yok
        }
    }

    public func cancel(_ k: Reciter, surah: Int) {
        tasks[Self.key(k, surah)]?.cancel()
    }

    public func delete(_ k: Reciter, surah: Int, verseCount: Int) {
        for verse in 1...verseCount {
            try? FileManager.default.removeItem(at: local(k, surah: surah, verse: verse))
        }
        states[Self.key(k, surah)] = .yok
    }

    /// Downloaded surahs per reciter, for İndirilenler.
    /// Remove all surahs of a reciter at once (storage management).
    public func deleteAll(_ k: Reciter) {
        try? FileManager.default.removeItem(at: root.appending(path: k.id))
    }

    public func downloaded() -> [(reciter: Reciter, surah: Int, bytes: Int64)] {
        var result: [(Reciter, Int, Int64)] = []
        for k in Reciter.all {
            let folder = root.appending(path: k.id)
            guard
                let files = try? FileManager.default.contentsOfDirectory(
                    at: folder, includingPropertiesForKeys: [.fileSizeKey])
            else { continue }
            var surahs: [Int: Int64] = [:]
            for d in files where d.pathExtension == "mp3" {
                guard let s = Int(d.lastPathComponent.prefix(3)) else { continue }
                let b = (try? d.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 } ?? 0
                surahs[s, default: 0] += Int64(b)
            }
            for (s, b) in surahs.sorted(by: { $0.key < $1.key }) { result.append((k, s, b)) }
        }
        return result
    }
}
