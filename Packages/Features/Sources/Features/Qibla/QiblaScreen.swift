import Core
import DesignSystem
import MapKit
import Qibla
import SwiftUI
import UserData

/// Qibla (K-Don, K-Tamam, K-Kalibre, K-Parazit): Pusula, camera, Harita.
struct QiblaScreen: View {
    enum QiblaMode: String, Hashable { case compass = "pusula", camera = "kamera", map = "harita" }

    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme
    @State private var sensor = QiblaSensor()
    /// View chosen by hand; until then ``startView(argument:selection:end:)`` applies.
    @State private var selectedMode: QiblaMode?

    /// Start view: a launch argument `-kibleGorunum harita|kamera` (screenshots) takes precedence,
    /// otherwise the choice in Ayarlar; „last choice“ falls back to the compass without a remembered view.
    static func startView(argument: String?, selection: QiblaStart, end: String) -> QiblaMode {
        if let argument, let g = QiblaMode(rawValue: argument) { return g }
        switch selection {
        case .compass: return .compass
        case .map: return .map
        case .lastChoice: return QiblaMode(rawValue: end) ?? .compass
        }
    }

    private var appearance: QiblaMode {
        selectedMode
            ?? Self.startView(
                argument: UserDefaults.standard.string(forKey: "kibleGorunum"),
                selection: settings.qiblaStart, end: settings.qiblaLastMode)
    }

    private var modeSelection: Binding<QiblaMode> {
        Binding(get: { appearance }, set: { sec($0) })
    }

    private func sec(_ g: QiblaMode) {
        selectedMode = g
        settings.qiblaLastMode = g.rawValue
    }
    @State private var calibrationSkipped = false
    /// Last hit state, for the hysteresis.
    @State private var wasHit = false
    @State private var selectingLocation = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var width: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker(localized("kible.gorunum"), selection: modeSelection) {
                Text(app: "kible.pusula").tag(QiblaMode.compass)
                Text(app: "kible.kamera").tag(QiblaMode.camera)
                Text(app: "kible.harita").tag(QiblaMode.map)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: PadLayout.isPad ? 360 : nil)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: PadLayout.isPad ? .leading : .center)
            .zIndex(1)

            if let location = settings.location {
                let qibla = QiblaCalculation.angle(location)
                switch appearance {
                case .compass:
                    if PadLayout.isPad, sizeClass == .regular, width >= 860 {
                        // Landscape on the iPad: the instrument next to the map (board G15).
                        HStack(spacing: 14) {
                            compass(location, qibla: qibla)
                                .padCard(theme, radius: 28)
                                .clipShape(.rect(cornerRadius: 28))
                                .frame(width: width * 0.53)
                            QiblaMap(
                                location: location, sensor: sensor, qibla: qibla,
                                accuracy: calibrationSkipped && sensor.accuracy == .unavailable
                                    ? .low : sensor.accuracy,
                                switchToCompass: { sec(.compass) }
                            )
                            .clipShape(.rect(cornerRadius: 28))
                        }
                        .padding([.horizontal, .bottom], 14)
                    } else {
                        compass(location, qibla: qibla)
                    }
                case .camera:
                    QiblaCamera(
                        sensor: sensor, qibla: qibla, distance: QiblaCalculation.distance(location),
                        accuracy: calibrationSkipped && sensor.accuracy == .unavailable
                            ? .low : sensor.accuracy,
                        switchToCompass: { sec(.compass) })
                case .map:
                    QiblaMap(
                        location: location, sensor: sensor, qibla: qibla,
                        accuracy: calibrationSkipped && sensor.accuracy == .unavailable
                            ? .low : sensor.accuracy,
                        switchToCompass: { sec(.compass) })
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(app: "kible.konum_yok.baslik").typography(.title1)
                        Text(app: "kible.konum_yok.aciklama").typography(.body).foregroundStyle(
                            theme.colors.text2)
                        Button(localized("konum.sehir_ara")) { selectingLocation = true }.buttonStyle(
                            PrimaryButton())
                    }
                    .padding(20)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        .pageBackground()
        .navigationTitle(localized("sekme.kible"))
        .smallTitle()
        .toolbar {
            if let location = settings.location {
                ToolbarItem(placement: .primaryAction) { ShareButton(.qibla(location)) }
            }
        }
        .sheet(isPresented: $selectingLocation) { LocationPickerScreen() }
        .onAppear { sensor.start() }
        .onDisappear { sensor.stop() }
    }

    /// Compass view. Without a sensor the large degree number has no reference, then only the small
    /// Bilgi line stands above the hint and the sun fallback.
    @ViewBuilder
    private func compass(_ location: Location, qibla: Double) -> some View {
        let accuracy = calibrationSkipped && sensor.accuracy == .unavailable ? .low : sensor.accuracy
        let status = QiblaState.parse(
            qibla: qibla, direction: sensor.direction, accuracy: accuracy, area: sensor.area, wasHit: wasHit)
        let degreeRing = settings.compassStyle == .degreeRing
        ScrollView {
            VStack(spacing: 18) {
                if degreeRing && sensor.available {
                    angleTitle(location, qibla: qibla)
                } else {
                    Text(verbatim: infoLine(location, qibla: qibla))
                        .typography(.secondary).foregroundStyle(theme.colors.text2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !sensor.available {
                    Hint(.warning) { Text(app: "kible.sensor_yok") }
                    SunQibla(location: location, qibla: qibla)
                } else {
                    switch status {
                    case .calibrating:
                        calibrating
                    case .interference:
                        interference(location, qibla: qibla)
                    default:
                        Dial(
                            style: settings.compassStyle, direction: sensor.direction, qibla: qibla,
                            done: status.isDone,
                            sade: settings.largeAndSimple
                        )
                        .frame(maxWidth: 360)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(localized("sekme.kible"))
                        .accessibilityValue(status.spoken)
                        HStack(spacing: 8) {
                            if status.isDone && !degreeRing {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(
                                    theme.colors.sage
                                )
                                .accessibilityHidden(true)
                            }
                            Text(verbatim: status.title)
                        }
                        .typography(.title1).foregroundStyle(
                            status.isDone ? theme.colors.successText : theme.colors.text
                        )
                        .multilineTextAlignment(.center)
                        .onChange(of: status.isDone) { _, yeni in
                            wasHit = yeni
                            if yeni { AccessibilityNotification.Announcement(status.title).post() }
                        }
                        .onChange(of: status.spokenStep) { _, step in
                            if step != nil { AccessibilityNotification.Announcement(status.spoken).post() }
                        }
                        // After „Şimdilik atla“ the quality is unknown: text yes, haptics no (K5).
                        .sensoryFeedback(.success, trigger: status.isDone) { _, yeni in
                            yeni && !(calibrationSkipped && sensor.accuracy == .unavailable)
                        }
                        if degreeRing && sensor.pose != .flat {
                            Label(localized("kible.harita.duz_tut"), systemImage: "iphone.gen3")
                                .typography(.body).foregroundStyle(theme.colors.text2)
                        }
                        HStack(spacing: 10) {
                            chip(localized("kible.dogruluk"), accuracy.text)
                            chip(localized("kible.tutus"), sensor.pose.text)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    /// Head of the degree ring: large Qibla number, below it location and distance (variant C).
    private func angleTitle(_ k: Location, qibla: Double) -> some View {
        let km = (QiblaCalculation.distance(k) / 1000).formatted(.number.precision(.fractionLength(0)))
        return VStack(spacing: 2) {
            Text(app: "kible.aci_baslik").typography(.secondary).foregroundStyle(theme.colors.text2)
            Text(verbatim: "\(Int(qibla.rounded()))°").typography(.accent).foregroundStyle(theme.colors.text)
            Text(verbatim: k.name + " · " + localized("kible.harita.uzaklik \(km)"))
                .typography(.secondary).foregroundStyle(theme.colors.text2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var calibrating: some View {
        VStack(alignment: .leading, spacing: 12) {
            Hint(.warning) { Text(app: "kible.kalibre.dusuk") }
            Text(app: "kible.kalibre.baslik").typography(.title1)
            Image(systemName: "infinity").font(.system(size: 64, weight: .light)).frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            Text(app: "kible.kalibre.aciklama").typography(.body)
            Button(localized("kible.kalibre.atla")) { calibrationSkipped = true }.buttonStyle(
                SecondaryButton())
        }
    }

    private func interference(_ location: Location, qibla: Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Hint(.error) { Text(app: "kible.parazit.baslik") }
            Text(app: "kible.parazit.aciklama").typography(.body)
            Text(app: "kible.parazit.ne_yap").typography(.emphasized)
            VStack(alignment: .leading, spacing: 6) {
                Text(app: "kible.parazit.kilif")
                Text(app: "kible.parazit.metal")
                Text(app: "kible.parazit.arac")
            }
            .typography(.body)
            Button(localized("kible.haritada_goster")) { sec(.map) }.buttonStyle(PrimaryButton())
            SunQibla(location: location, qibla: qibla)
        }
    }

    private func chip(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title).typography(.footnote).foregroundStyle(theme.colors.text2)
            Text(verbatim: value).typography(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.surface, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private func infoLine(_ k: Location, qibla: Double) -> String {
        let km = (QiblaCalculation.distance(k) / 1000).formatted(.number.precision(.fractionLength(0)))
        let direction = localized(
            String.LocalizationValue(stringLiteral: "kible.yon.\(QiblaCalculation.inEighths(qibla))"))
        return localized("kible.bilgi \(Int(qibla.rounded())) \(direction) \(km)")
    }
}

/// „Güneşe göre“: Qibla relative to the sun, entirely without a compass.
struct SunQibla: View {
    @Environment(\.theme) private var theme
    let location: Location
    let qibla: Double

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { b in
            let g = SunPosition.calculate(
                time: b.date, latitude: location.latitude, longitude: location.longitude)
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    Text(app: "kible.gunes.baslik").typography(.emphasized)
                    if g.altitude > SunPosition.visibleHeight {
                        let f = QiblaCalculation.difference(g.azimuth, qibla)
                        Text(
                            verbatim: f >= 0
                                ? localized("kible.gunes.sag \(Int(abs(f).rounded()))")
                                : localized("kible.gunes.sol \(Int(abs(f).rounded()))")
                        )
                        .typography(.body)
                        Text(app: "kible.gunes.ipucu").typography(.footnote).foregroundStyle(
                            theme.colors.text2)
                    } else {
                        Text(app: "kible.gunes.batti").typography(.body)
                    }
                }
            }
        }
    }
}

extension QiblaState {
    var isDone: Bool { if case .done = self { true } else { false } }

    /// For VoiceOver: turning direction in 10° steps instead of „-20 degrees“.
    var spoken: String {
        guard let step = spokenStep else { return title }
        if step > 0 { return localized("kible.don.sag \(step)") }
        if step < 0 { return localized("kible.don.sol \(-step)") }
        return title
    }

    var title: String {
        switch self {
        case .done(let y): y ? localized("kible.tamam.yaklasik") : localized("kible.tamam")
        case .turn(let f, _):
            f > 0
                ? localized("kible.don.sag \(Int(f.rounded()))")
                : localized("kible.don.sol \(Int((-f).rounded()))")
        case .searching: localized("kible.araniyor")
        case .calibrating: localized("kible.kalibre.baslik")
        case .interference: localized("kible.parazit.baslik")
        case .noLocation: localized("kible.konum_yok.baslik")
        }
    }
}

extension Accuracy {
    var text: String {
        switch self {
        case .good: localized("kible.dogruluk.iyi")
        case .intermediate: localized("kible.dogruluk.orta")
        case .low: localized("kible.dogruluk.dusuk")
        case .unavailable: localized("kible.dogruluk.yok")
        }
    }
}

extension DeviceAttitude.Pose {
    var text: String {
        switch self {
        case .flat: localized("kible.tutus.duz")
        case .tilted: localized("kible.tutus.egik")
        case .upright: localized("kible.tutus.dik")
        }
    }
}
