import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

/// Colors of the Home Screen widgets, style A: the app's Seher colors, light
/// during the day, at night dark green-black instead of system black. The countdown's traffic light runs in
/// app tones: sage green → amber → terracotta. As a pair, because widgets follow the system.
public enum WidgetColor {
    public static let background = pair(0xF7F3EC, 0x1E2320)
    public static let surface2 = pair(0xEFE8DC, 0x262B27)
    public static let track = pair(0xE4DCCD, 0x323833)
    public static let text = pair(0x1F2421, 0xF2EEE6)
    public static let text2 = pair(0x4A4F4B, 0xB4BAB5)
    public static let label = pair(0x6B4A2E, 0xE9B58C)
    public static let accent = pair(0xB0452E, 0xE9876D)
    public static let onAccent = pair(0xFFFFFF, 0x141816)
    public static let green = pair(0x4F7357, 0x8FB596)
    public static let orange = pair(0xA8621A, 0xE9A050)
    public static let red = pair(0xB0452E, 0xE9876D)
    public static let bar = pair(0xCFC6B5, 0x4A524C)

    /// Fixed size: otherwise widgets grow only partially with the text size.
    public static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(Typography.sans, fixedSize: size).weight(weight)
    }

    static func pair(_ light: UInt32, _ dark: UInt32) -> Color {
        #if canImport(UIKit)
            Color(
                UIColor { m in
                    let d = m.userInterfaceStyle == .dark ? dark : light
                    return UIColor(
                        red: CGFloat((d >> 16) & 0xFF) / 255, green: CGFloat((d >> 8) & 0xFF) / 255,
                        blue: CGFloat(d & 0xFF) / 255, alpha: 1)
                })
        #else
            Color(hex: light)
        #endif
    }
}
