import SwiftUI

/// Fixed colors of the iPad screens (canvas boards of the iPad briefing), independent of the theme.
///
/// They paint scenes, not surfaces: the onboarding sky, the sun on the Today screen, the green desk behind
/// the full screen book and the backdrop of the debug widget gallery. Kept here because DesignSystem is the
/// only place with color values.
public enum PadColor {
    /// Onboarding sky, top to bottom, plus the sun and its edge.
    public static let skyTop = Color(hex: 0x1F3D30)
    public static let skyMiddle = Color(hex: 0x86693C)
    public static let skyLow = Color(hex: 0x474530)
    public static let sun = Color(hex: 0xFDEBC2)
    public static let sunEdge = Color(hex: 0xF3D08A)

    /// The small sun glow in the corner of the Today screen.
    public static let glowCore = Color(hex: 0xFFE9B8)
    public static let glowEdge = Color(hex: 0xFFDC96)

    /// The desk behind the full screen book, center to edge.
    public static let desk = [Color(hex: 0x2D5742), Color(hex: 0x1B3A2C), Color(hex: 0x10241A)]

    /// The warm shadow under the cards in light mode.
    public static let warmShadow = Color(hex: 0x3C2814)

    /// Backdrop of the debug widget gallery (`-widgetGaleri`).
    public static let galleryBackdrop = [Color(hex: 0x2E5742), Color(hex: 0x1C3B2B), Color(hex: 0x3B2921)]
}
