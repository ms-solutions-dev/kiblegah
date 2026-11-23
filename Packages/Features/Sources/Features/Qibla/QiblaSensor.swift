import Foundation
import Observation
import Qibla

#if os(iOS)
    import CoreMotion
#endif

/// Reads the device orientation via CoreMotion (`xTrueNorthZVertical`) - flat and upright.
///
/// Runs only while the Qibla screen is visible; 30 Hz is enough for a steady needle.
@MainActor @Observable final class QiblaSensor {
    private(set) var direction: Double?
    private(set) var pose: DeviceAttitude.Pose = .flat
    private(set) var accuracy: Accuracy = .unavailable
    /// Strength of the calibrated magnetic field in µT.
    private(set) var area: Double?
    private(set) var available = true

    #if os(iOS)
        private let motionManager = CMMotionManager()
    #endif

    func start() {
        #if DEBUG
            // Screenshots in the simulator without a compass: `-pusulaSahte 110` (degrees).
            if let d = UserDefaults.standard.object(forKey: "pusulaSahte") as? String, let y = Double(d) {
                direction = y
                accuracy = .good
                return
            }
        #endif
        #if os(iOS)
            guard CMMotionManager.availableAttitudeReferenceFrames().contains(.xTrueNorthZVertical),
                motionManager.isDeviceMotionAvailable
            else {
                available = false
                return
            }
            motionManager.deviceMotionUpdateInterval = 1.0 / 30
            motionManager.startDeviceMotionUpdates(using: .xTrueNorthZVertical, to: .main) {
                [weak self] motion, _ in
                guard let self, let motion else { return }
                MainActor.assumeIsolated { self.isle(motion) }
            }
        #else
            available = false
        #endif
    }

    func stop() {
        #if os(iOS)
            motionManager.stopDeviceMotionUpdates()
        #endif
    }

    #if os(iOS)
        private func isle(_ h: CMDeviceMotion) {
            let m = h.attitude.rotationMatrix
            let y = DeviceAttitude(
                matrix: [[m.m11, m.m12, m.m13], [m.m21, m.m22, m.m23], [m.m31, m.m32, m.m33]],
                gravity: SIMD3(h.gravity.x, h.gravity.y, h.gravity.z))
            if let yeni = y.direction {
                // Smooth gently, across the 0°/360° wrap.
                if let old = direction {
                    direction = QiblaCalculation.normalize(
                        old + QiblaCalculation.difference(old, yeni) * 0.25)
                } else {
                    direction = yeni
                }
            }
            pose = y.pose
            let f = h.magneticField
            area =
                f.accuracy == .uncalibrated
                ? nil : (f.field.x * f.field.x + f.field.y * f.field.y + f.field.z * f.field.z).squareRoot()
            accuracy =
                switch f.accuracy {
                case .high: .good
                case .medium: .intermediate
                case .low: .low
                default: .unavailable
                }
        }
    #endif
}
