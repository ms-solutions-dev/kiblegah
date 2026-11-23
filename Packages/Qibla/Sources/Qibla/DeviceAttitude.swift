import Foundation

/// The attitude of the device and the resulting viewing direction – flat and upright without a mode switch.
///
/// The viewing direction is the horizontal component of (top edge − screen normal):
/// when flat, the top edge is horizontal; when upright, the back (−z) points forward;
/// in between, both components point in the same direction. So no threshold is needed
/// and there is no jump when tilting.
public struct DeviceAttitude: Sendable, Equatable {
    /// Device axes in the reference frame `xTrueNorthZVertical`: x = north, y = west, z = up.
    public let x: SIMD3<Double>
    public let y: SIMD3<Double>
    public let z: SIMD3<Double>

    public init(x: SIMD3<Double>, y: SIMD3<Double>, z: SIMD3<Double>) {
        self.x = x
        self.y = y
        self.z = z
    }

    /// From the CoreMotion matrix (rows m1x, m2x, m3x). Which reading (rows or columns)
    /// carries the device axes is decided by gravity in the device frame: it must equal
    /// "down" of the reference frame. So nothing depends on a convention that cannot be
    /// checked at a desk.
    public init(matrix m: [[Double]], gravity g: SIMD3<Double>) {
        let row = (
            SIMD3(m[0][0], m[0][1], m[0][2]), SIMD3(m[1][0], m[1][1], m[1][2]),
            SIMD3(m[2][0], m[2][1], m[2][2])
        )
        let column = (
            SIMD3(m[0][0], m[1][0], m[2][0]), SIMD3(m[0][1], m[1][1], m[2][1]),
            SIMD3(m[0][2], m[1][2], m[2][2])
        )
        // "Down" (0,0,−1) in the device frame: with the row reading the axes are the rows,
        // so down_device = (−x.z, −y.z, −z.z).
        let bottomRow = SIMD3(-row.0.z, -row.1.z, -row.2.z)
        let bottomColumn = SIMD3(-column.0.z, -column.1.z, -column.2.z)
        let gn = g / max(1e-9, (g * g).sum().squareRoot())
        if (bottomRow * gn).sum() >= (bottomColumn * gn).sum() {
            self.init(x: row.0, y: row.1, z: row.2)
        } else {
            self.init(x: column.0, y: column.1, z: column.2)
        }
    }

    /// Viewing direction in degrees from north, or `nil` if undetermined (screen facing down, etc.).
    public var direction: Double? {
        let v = y - z
        let north = v.x
        let east = -v.y
        guard (north * north + east * east).squareRoot() > 0.2 else { return nil }
        return QiblaCalculation.normalize(atan2(east, north) * 180 / .pi)
    }

    /// How upright the device is: 0 = flat, 1 = vertical.
    public var tilt: Double { 1 - min(1, abs(z.z)) }

    public enum Pose: Sendable, Equatable { case flat, tilted, upright }

    public var pose: Pose {
        switch tilt {
        case ..<0.35: .flat
        case ..<0.75: .tilted
        default: .upright
        }
    }
}
