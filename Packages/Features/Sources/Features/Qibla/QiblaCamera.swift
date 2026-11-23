import DesignSystem
import Qibla
import SwiftUI

#if os(iOS)
    import AVFoundation
    import UIKit
#endif

/// Camera with a light beam in the Qibla direction: A vertical
/// beam stands in the image where the Qibla lies and moves along when turning; if it lies outside,
/// a sign at the edge shows the degree number. When the beam hits the ring, the Kaaba appears with
/// distance, everything turns green. Same evaluation as the compass – with interference no beam, the
/// camera is not a cross-check.
struct QiblaCamera: View {
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var open
    let sensor: QiblaSensor
    let qibla: Double
    /// Distance to the Kaaba in meters, for the label on a hit.
    var distance: Double? = nil
    /// As in the compass: after „Şimdilik atla“ uncalibrated counts as rough.
    let accuracy: Accuracy
    /// „Şimdi değil“ on the pre-prompt card: back to the compass, without a system dialog.
    let switchToCompass: () -> Void

    @State private var wasHit = false
    #if os(iOS)
        /// Own state so that a denial in the system dialog immediately shows the notice (K10).
        @State private var allowed = AVCaptureDevice.authorizationStatus(for: .video)
    #endif

    var body: some View {
        #if os(iOS)
            switch allowed {
            case .notDetermined:
                previewCard
            case .denied, .restricted:
                VStack(alignment: .leading, spacing: 12) {
                    Text(app: "kible.kamera.izin_yok").typography(.body)
                    Button(localized("bildirim.ayarlari_ac")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { open(url) }
                    }
                    .buttonStyle(SecondaryButton())
                }
                .padding(20)
                .frame(maxHeight: .infinity, alignment: .top)
            default:
                ZStack(alignment: .bottom) {
                    CameraPreview().ignoresSafeArea(edges: .bottom)
                    // Same evaluation as the compass: no beam on interference or without calibration,
                    // hit window by accuracy, „yaklaşık“ for a rough orientation.
                    let status = QiblaState.parse(
                        qibla: qibla, direction: sensor.direction, accuracy: accuracy, area: sensor.area,
                        wasHit: wasHit
                    )
                    QiblaBeam(status: status, distance: distance).ignoresSafeArea(edges: .bottom)
                    VStack(spacing: 8) {
                        Label {
                            Text(verbatim: status.title)
                        } icon: {
                            if let icon = status.cameraSymbol { Image(systemName: icon) }
                        }
                        .typography(.emphasized).foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(
                            status.isDone
                                ? AnyShapeStyle(ColorTokens.dawnLight.sage)
                                : AnyShapeStyle(.black.opacity(0.55)),
                            in: .capsule)
                        Text(app: "kible.kamera.not").typography(.footnote).foregroundStyle(
                            .white.opacity(0.85)
                        )
                        .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 20).padding(.bottom, 24)
                    .onChange(of: status.isDone) { _, yeni in wasHit = yeni }
                    .sensoryFeedback(.success, trigger: status.isDone) { _, yeni in yeni }
                }
            }
        #else
            Text(app: "kible.sensor_yok").padding(20)
        #endif
    }

    #if os(iOS)
        /// Own explanation before the system prompt, as with location; only the
        /// button „Kamerayı aç“ triggers `requestAccess`, so a reflexive „Nicht erlauben“ is avoided.
        private var previewCard: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 48, weight: .light)).foregroundStyle(theme.colors.accent)
                        .accessibilityHidden(true)
                    Text(app: "kible.kamera.on.baslik").typography(.title1)
                    Text(app: "kible.kamera.on.aciklama").typography(.body).foregroundStyle(
                        theme.colors.text2)
                    Button(localized("kible.kamera.on.ac")) {
                        Task {
                            allowed = await AVCaptureDevice.requestAccess(for: .video) ? .authorized : .denied
                        }
                    }
                    .buttonStyle(PrimaryButton())
                    Button(localized("kible.kamera.on.simdi_degil"), action: switchToCompass)
                        .buttonStyle(SecondaryButton())
                }
                .padding(20)
            }
        }
    #endif
}

#if os(iOS)
    /// The capture session on its own queue; AVFoundation starts there without blocking the UI.
    final class CameraSession: @unchecked Sendable {
        let session = AVCaptureSession()
        private let queue = DispatchQueue(label: "kiblegah.kamera")

        func start() {
            AVCaptureDevice.requestAccess(for: .video) { allowed in
                guard allowed else { return }
                self.queue.async {
                    guard self.session.inputs.isEmpty,
                        let device = AVCaptureDevice.default(
                            .builtInWideAngleCamera, for: .video, position: .back),
                        let entry = try? AVCaptureDeviceInput(device: device), self.session.canAddInput(entry)
                    else { return }
                    self.session.addInput(entry)
                    self.session.startRunning()
                }
            }
        }

        func stop() { queue.async { self.session.stopRunning() } }
    }

    /// Rear camera as preview; appears only after the pre-prompt card, so the check in `start()` is just a safeguard.
    struct CameraPreview: UIViewRepresentable {
        final class PreviewView: UIView {
            override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
            var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
            let camera = CameraSession()
        }

        func makeUIView(context: Context) -> PreviewView {
            let v = PreviewView()
            v.previewLayer.videoGravity = .resizeAspectFill
            v.previewLayer.session = v.camera.session
            v.camera.start()
            return v
        }

        func updateUIView(_ uiView: PreviewView, context: Context) {}

        static func dismantleUIView(_ uiView: PreviewView, coordinator: ()) {
            uiView.camera.stop()
        }
    }
#endif

extension QiblaState {
    /// Arrow or checkmark only when a reliable direction is available.
    var cameraSymbol: String? {
        switch self {
        case .done: "checkmark.circle.fill"
        case .turn(let f, _): f > 0 ? "arrow.right.circle.fill" : "arrow.left.circle.fill"
        default: nil
        }
    }
}

#if os(iOS)
    /// The overlay above the camera image: ring in the center, light beam at the Qibla direction,
    /// edge shield outside the image, Kaaba with distance on a hit.
    struct QiblaBeam: View {
        let status: QiblaState
        let distance: Double?

        /// Half of the visible field of view as a tangent: the preview fills the screen (aspect fill),
        /// the 4:3 image held upright is cropped at the sides; what stays visible is
        /// tan(fov/2) · width/height, using the wide-angle camera's field of view (otherwise 65°).
        static func tanHalfFov(_ size: CGSize) -> Double {
            let fov =
                AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                .map { Double($0.activeFormat.videoFieldOfView) } ?? 65
            return tan(fov / 2 * .pi / 180) * size.width / max(size.height, 1)
        }

        /// Horizontal position of the beam (0 = center, ±1 = image edge) or `nil` if it lies outside.
        static func location(difference: Double, tanHalfFov: Double) -> Double? {
            guard abs(difference) < 89 else { return nil }
            let x = tan(difference * .pi / 180) / tanHalfFov
            return abs(x) <= 1 ? x : nil
        }

        var body: some View {
            GeometryReader { g in
                let w = g.size.width
                let center = CGPoint(x: w / 2, y: g.size.height * 0.42)
                let difference: Double? = {
                    switch status {
                    case .done: 0
                    case .turn(let f, _): f
                    default: nil
                    }
                }()
                let done = status.isDone
                let color = done ? ColorTokens.dawnDark.sage : ColorTokens.dawnDark.kaaba
                ZStack {
                    ring(done: done, color: color).position(center)
                    if let difference {
                        if let x = Self.location(difference: difference, tanHalfFov: Self.tanHalfFov(g.size))
                        {
                            Rectangle().fill(color).frame(width: 4)
                                .shadow(color: color.opacity(0.8), radius: 12)
                                .position(x: w / 2 + x * w / 2, y: g.size.height / 2)
                                .frame(height: g.size.height)
                                .animation(.interactiveSpring, value: x)
                        } else {
                            edgeArrow(difference).position(x: difference > 0 ? w - 50 : 50, y: center.y)
                        }
                    }
                    if done {
                        VStack(spacing: 8) {
                            KaabaMarker(size: 40)
                            if let distance {
                                let km = (distance / 1000).formatted(.number.precision(.fractionLength(0)))
                                Text(app: "kible.harita.uzaklik \(km)").typography(.footnote).foregroundStyle(
                                    .white
                                )
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(.black.opacity(0.55), in: .capsule)
                            }
                        }
                        .position(x: center.x, y: center.y + 22)
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }

        private func ring(done: Bool, color: Color) -> some View {
            ZStack {
                Circle().fill(done ? color.opacity(0.22) : .clear)
                Circle().stroke(done ? color : .white, lineWidth: done ? 4 : 3)
                if !done {
                    VStack(spacing: 104) {
                        Rectangle().fill(.white).frame(width: 2, height: 30)
                        Rectangle().fill(.white).frame(width: 2, height: 30)
                    }
                }
            }
            .frame(width: 96, height: 96)
        }

        /// „48° ›“ at the edge when the Qibla lies outside the image.
        private func edgeArrow(_ difference: Double) -> some View {
            let degrees = Int(abs(difference).rounded())
            return Text(verbatim: difference > 0 ? "\(degrees)° ›" : "‹ \(degrees)°")
                .font(.headline.monospacedDigit()).foregroundStyle(.black)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(ColorTokens.dawnDark.kaaba, in: .capsule)
        }
    }
#endif
