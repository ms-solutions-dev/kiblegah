import SwiftUI

/// Colors of the book reader (`Okuyucu`,): paper and ink of the reading themes as in StoryShelf
/// (sepia `#F3EBDD`) and the three highlight colors, strong enough for sepia and night.
/// As `0xRRGGBB` because Readium wants them as a number.
public enum ReadingColors {
    public static let lightPaper: UInt32 = 0xFDFCF8
    public static let lightInk: UInt32 = 0x1B1A17
    public static let sepiaPaper: UInt32 = 0xF3EBDD
    public static let sepiaInk: UInt32 = 0x4A3B2C
    public static let darkPaper: UInt32 = 0x141210
    public static let darkInk: UInt32 = 0xE6E2DA
    public static let nightPaper: UInt32 = 0x000000
    public static let nightInk: UInt32 = 0xBDB6AA

    public static let yellow: UInt32 = 0xF5D76E
    public static let green: UInt32 = 0x9ED4A8
    public static let pink: UInt32 = 0xF2A7A7

    /// One of these colors for SwiftUI.
    public static func color(_ hex: UInt32) -> Color { Color(hex: hex) }
}
