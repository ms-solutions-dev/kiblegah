import Foundation
import Testing

// Helpers for the golden tests. Exists once in every test target.

/// Decodes `json` as `T`, re-encodes and requires the same keys and values. Breaks as soon as a
/// stored field is renamed without `CodingKeys`.
func goldenRoundTrip<T: Codable>(
    _ type: T.Type, _ json: String, sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let data = Data(json.utf8)
    let before = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
    let value = try JSONDecoder().decode(T.self, from: data)
    let after = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(value), options: .fragmentsAllowed)
    let same = (before as? NSObject)?.isEqual(after) ?? false
    #expect(same, "\(T.self) kodiert anders: \(after)", sourceLocation: sourceLocation)
}

/// All Swift source of the package (`Sources/`), for keys that exist only as a literal in the code.
func goldenSourceText(_ file: String = #filePath) -> String {
    let sources = URL(filePath: file).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "Sources")
    var text = ""
    let walker = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
    while let url = walker?.nextObject() as? URL {
        if url.pathExtension == "swift" { text += (try? String(contentsOf: url, encoding: .utf8)) ?? "" }
    }
    return text
}

/// Every name must appear as a string literal (`"name"`) in the source; prefixes as `"präfix`.
func expectLiterals(
    _ names: [String], prefixes: [String] = [], in text: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    for n in names {
        #expect(
            text.contains("\"\(n)\""), "Literal \"\(n)\" missing from the source",
            sourceLocation: sourceLocation)
    }
    for p in prefixes {
        #expect(
            text.contains("\"\(p)"), "Prefix \"\(p)…\" missing from the source",
            sourceLocation: sourceLocation)
    }
}
