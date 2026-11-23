import CoreGraphics
import Foundation

/// Compass directions on the dial: compass, map ring and watch show the same four letters
/// (TR K/D/G/B, DE N/O/S/W, EN N/E/S/W) and always keep them upright.
///
/// The letters are offset via sine and cosine instead of being rotated along; so they are never
/// upside down, even when looking south.
public enum CompassLetter {
    /// Catalog key of direction `i` (0 = north, 1 = east, 2 = south, 3 = west).
    public static func key(_ i: Int) -> String { "kible.harita.yon.\(((i % 4) + 4) % 4)" }

    /// Offset from the center for direction `i` on a ring of radius `r`, when the device points
    /// to `direction` (degrees); y grows downwards as in SwiftUI.
    public static func location(_ i: Int, direction: Double, r: Double) -> CGPoint {
        point(angle: Double(i) * 90 - direction, r: r)
    }

    /// Point on a ring for a clockwise angle from the top.
    public static func point(angle: Double, r: Double) -> CGPoint {
        let a = angle * .pi / 180
        return CGPoint(x: sin(a) * r, y: -cos(a) * r)
    }
}

/// Viewport for „Kâbe'yi göster“: location and Kaaba should not stick to the edge.
///
/// Around the route a fixed margin of 25 % of the longer side remains; bars at the top and bottom
/// (the panel above the map) do not count as free area. The result has exactly the
/// aspect ratio of the map, so that MapKit takes it over without padding of its own.
public enum QiblaFraming {
    public static let tolerance = 0.25

    /// - Parameters:
    ///   - path: Outline of the route in map points (y grows southwards).
    ///   - size: Size of the map in screen points.
    ///   - top: Obscured height at the top.
    ///   - bottom: Obscured height at the bottom, e.g. the panel.
    /// - Returns: The map viewport in map points that fills the entire map area.
    public static func frame(path: CGRect, size: CGSize, top: Double = 0, bottom: Double = 0) -> CGRect {
        let border = max(path.width, path.height) * tolerance
        let goal = path.insetBy(dx: -border, dy: -border)
        let freeHeight = max(Double(size.height) - top - bottom, Double(size.height) * 0.3, 1)
        let width = max(Double(size.width), 1)
        let scale = max(goal.width / width, goal.height / freeHeight)
        let fullWidth = width * scale
        let fullHeight = max(Double(size.height), 1) * scale
        let freeCenter = top + freeHeight / 2
        return CGRect(
            x: goal.midX - fullWidth / 2,
            y: goal.midY - freeCenter * scale,
            width: fullWidth, height: fullHeight)
    }
}
