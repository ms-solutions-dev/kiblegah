import Foundation
import Observation

/// The mushaf editions. This build ships no page packs: layouts come through the relay
/// (``MushafLayoutSource``), page fonts from the Quran Foundation, otherwise the text is reflowed.
/// Every edition is therefore always "ready"; switching only changes the setting.
@MainActor @Observable final class MushafPack {
    static let shared = MushafPack()

    enum LoadStatus: Equatable {
        case yok
        case downloading(Double)
        case ready
        case failed(String)
    }

    func status(_ s: MushafEdition) -> LoadStatus { .ready }

    func refresh() {}

    func download(_ s: MushafEdition) async {}

    nonisolated static func isReady(_ s: MushafEdition) -> Bool { true }

    /// A file of a local page pack; there are none in this build.
    nonisolated static func file(_ s: MushafEdition, _ name: String) -> URL? { nil }
}
