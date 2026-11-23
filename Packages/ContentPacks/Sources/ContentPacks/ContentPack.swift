import Foundation

/// The manifest of a content package.
public struct PackManifest: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let kind: String
    public let language: String
    public let title: String
    public let author: String?
    public let source: String
    public let sourceURL: URL?
    public let license: String
    public let storeEligible: Bool
    public let version: String
    /// Set for packages that depend on word boundaries or character offsets.
    public let textVersion: String?
    /// „ungeprüft“ as long as a hoca has not seen the content.
    public let review: String?

    enum CodingKeys: String, CodingKey {
        case id, kind = "art", language = "sprache", title = "titel", author = "yazar", source = "quelle",
            license = "lizenz", version, textVersion = "textstand", review = "inceleme"
        case sourceURL = "quelle_url"
        case storeEligible = "store_tauglich"
    }

    public var unreviewed: Bool { review == "ungeprüft" }
}

public enum ContentPackError: Error, Equatable, Sendable {
    case couldNotOpen(String)
    case manifestCorrupt(String)
    case quranMissing
}

/// A loaded package: manifest and database.
public final class ContentPack: Sendable {
    public let manifest: PackManifest
    let db: Database

    init(folder: URL) throws(ContentPackError) {
        let data: Data
        do {
            data = try Data(contentsOf: folder.appending(path: "manifest.json"))
        } catch {
            throw .manifestCorrupt(folder.lastPathComponent)
        }
        guard let m = try? JSONDecoder().decode(PackManifest.self, from: data) else {
            throw .manifestCorrupt(folder.lastPathComponent)
        }
        manifest = m
        db = try Database(url: folder.appending(path: "veri.sqlite"))
    }
}
