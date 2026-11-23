import CoreGraphics
import UserData

/// The two layouts of the memorization card (variant 09): A fixed at the bottom, B as a stack to swipe.
///
/// Raw values stay fixed because they are stored in the default settings under ``key``.
enum MemorizationLayout: String, CaseIterable, Sendable {
    case bottom = "alt", deck = "deste"

    static let key = "ezberDuzeni"
}

/// Swipe direction → rating in the stack: left Zor, right Kolay, up İyi.
///
/// A pure function so that threshold and precedence are testable. Horizontal wins on a
/// tie, because a diagonal upward swipe would otherwise hit „İyi“ instead of the intended side.
enum MemorizationSwipe {
    static let threshold: CGFloat = 110

    /// - Parameter yukariSerbest: `false` while the card itself is scrolling - then the
    ///   upward swipe belongs to scrolling, not to the rating.
    static func score(
        _ t: CGSize, threshold: CGFloat = threshold, allowUp: Bool = true
    ) -> MemorizationScheduler.Rating? {
        if abs(t.width) >= abs(t.height) {
            if t.width <= -threshold { return .zor }
            if t.width >= threshold { return .kolay }
            return nil
        }
        return allowUp && t.height <= -threshold ? .good : nil
    }
}
