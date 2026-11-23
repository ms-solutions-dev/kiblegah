import Foundation

/// Store for verse files that are about to be played: the engine (`RecitationPlayer`) only chains
/// local files together sample-accurately, so it first fetches each file here. Unlike
/// `AudioStore` (deliberately downloaded surahs) this is a temporary cache under `Caches`
/// that the system may clear; files older than 30 days are cleared by `clear()` itself.
public actor AudioCache {
    let root: URL
    private let session: URLSession
    private var completedDownloads: [URL: Task<URL?, Never>] = [:]

    public init(root: URL? = nil, session: URLSession = .shared) {
        self.root = root ?? URL.cachesDirectory.appending(path: "SesOnbellek")
        self.session = session
    }

    /// Local path for `url`: host and path are kept as folders, so that two
    /// reciters with the same file name do not overwrite each other.
    nonisolated func local(_ url: URL) -> URL {
        root.appending(path: url.host() ?? "-")
            .appending(path: String(url.path(percentEncoded: false).drop(while: { $0 == "/" })))
    }

    nonisolated func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: local(url).path(percentEncoded: false))
    }

    /// Returns the local file, downloading it if needed; concurrent requests share the
    /// download. `nil` if the network does not deliver.
    public func fetch(_ url: URL) async -> URL? {
        let goal = local(url)
        if exists(url) { return goal }
        if let t = completedDownloads[url] { return await t.value }
        let session = self.session
        let t = Task<URL?, Never> {
            guard let (temporary, answer) = try? await session.download(from: url),
                (answer as? HTTPURLResponse)?.statusCode == 200
            else { return nil }
            try? FileManager.default.createDirectory(
                at: goal.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: goal)
            return (try? FileManager.default.moveItem(at: temporary, to: goal)) == nil ? nil : goal
        }
        completedDownloads[url] = t
        let result = await t.value
        completedDownloads[url] = nil
        return result
    }

    /// Clears files that have not been touched for more than `day` days.
    public func clear(day: Int = 30) {
        let limit = Date(timeIntervalSinceNow: -Double(day) * 86400)
        guard
            let e = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey])
        else { return }
        for case let d as URL in e {
            guard let v = try? d.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                v.isRegularFile == true, let t = v.contentModificationDate, t < limit
            else { continue }
            try? FileManager.default.removeItem(at: d)
        }
    }
}
