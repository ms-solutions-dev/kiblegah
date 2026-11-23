import Core
import DesignSystem
import MapKit
import Network
import Qibla
import SwiftUI

/// Map modeled on „Kıble Bul“: It rotates with the phone, a
/// compass ring lies around the own location, the Kaaba sits on the ring in the Qibla direction.
/// Whoever turns until the line points up is standing correctly – without matching streets themselves.
///
/// Without a compass or with interference it shows the line aligned upward; then buildings
/// and streets serve as the reference. „Kâbe'yi göster“ shows the whole great-circle route;
/// hearts show the way.
///
/// The panel at the bottom starts collapsed (degrees, km, two buttons); the hint text appears only after
/// pulling it up. Map and ring are shifted up by the panel height,
/// so that the ring is in the middle of the free area – also in „Büyük ve sade“ and at AX3 (K4, K8).
/// Without network the map loads no tiles; then a hint leads to the compass (K16).
struct QiblaMap: View {
    enum Framing { case yakin, fullRoute }

    @Environment(\.theme) private var theme
    let location: Location
    let sensor: QiblaSensor
    let qibla: Double
    let accuracy: Accuracy
    let switchToCompass: () -> Void

    @State private var framing: Framing = .yakin
    @State private var camera: MapCameraPosition = .automatic
    /// Is a camera flight (to the location) currently running? Ends only when MapKit has set the camera down at the
    /// location, not with the SwiftUI animation (see ``flyClose(animated:)``).
    @State private var inFlight = false
    /// Number of the running flight; the emergency brake after ``flightLimit`` applies only to its own.
    @State private var flightID = 0
    @State private var lastHeading: Double?
    /// Last seen camera distance; after a zoom by the user `kamera.camera` is empty (K6).
    @State private var distance: Double = 900
    /// The ring appears only once the camera has arrived at the location;
    /// during the return flight from „Kâbe'yi göster“ it would otherwise be misplaced.
    @State private var ringReady = false
    /// Last hit state, for the hysteresis in ``QiblaState/parse(qibla:direction:accuracy:area:wasHit:)``.
    @State private var wasHit = false
    @State private var panelOpen = false
    /// Height of the panel including margin; map, ring and „Kâbe'yi göster“ subtract it.
    /// The map is extended upward by this height and cut off at the top, so that its center
    /// (the location) lies in the middle of the free area.
    @State private var panelHeight: CGFloat = 0
    @State private var mapSize: CGSize = .zero
    @State private var ag = NetworkMonitor()

    /// From this change on the camera is tracked; finer, the map only jitters.
    /// The ring follows the same steps without its own animation, otherwise it would run away from the map (K11).
    static let headingStep = 1.5
    /// Hearts along the route in „Kâbe'yi göster“.
    static let arrowCount = 5
    /// At the latest then a flight counts as finished, in case MapKit reports no end.
    static let flightLimit: Duration = .seconds(4)

    private var start: CLLocationCoordinate2D {
        .init(latitude: location.latitude, longitude: location.longitude)
    }
    private var kaaba: CLLocationCoordinate2D {
        .init(latitude: QiblaCalculation.kaabaLatitude, longitude: QiblaCalculation.kaabaLongitude)
    }
    private var status: QiblaState {
        QiblaState.parse(
            qibla: qibla, direction: sensor.direction, accuracy: accuracy, area: sensor.area, wasHit: wasHit)
    }
    /// The direction the map is aligned to: compass, otherwise Qibla up.
    private var cardHeading: Double {
        switch status {
        case .turn, .done: sensor.direction ?? qibla
        default: qibla
        }
    }
    private var hasCompass: Bool {
        switch status {
        case .turn, .done: true
        default: false
        }
    }

    var body: some View {
        GeometryReader { g in
            let bottom = min(panelHeight, g.size.height * 0.7)
            ZStack {
                map
                if framing == .yakin && ringReady {
                    MapRing(
                        direction: lastHeading ?? cardHeading, qibla: qibla, done: status.isDone,
                        radius: min(g.size.width, g.size.height - bottom) * 0.36
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .frame(width: g.size.width, height: g.size.height + bottom)
            .offset(y: -bottom / 2)
            .frame(width: g.size.width, height: g.size.height)
            .clipped()
            // `clipped` only cuts the image: Without its own hit area, the map shifted upward
            // intercepted the taps on „Kamera/Pusula“.
            .contentShape(.rect)
            .onAppear { mapSize = g.size }
            .onChange(of: g.size) { _, yeni in mapSize = yeni }
        }
        .overlay(alignment: .top) {
            if !ag.connected { offlineHint.padding(12) }
        }
        .overlay(alignment: .bottom) {
            altPanel.onGeometryChange(for: CGFloat.self) {
                $0.size.height
            } action: {
                panelHeight = $0
            }
        }
        .onAppear {
            ag.start()
            // Screenshots: `-kibleKadraj fullRoute` immediately opens the whole route.
            if UserDefaults.standard.string(forKey: "kibleKadraj") == "tumYol" {
                showFullRoute()
            } else {
                flyClose(animated: false)
            }
        }
        .onDisappear { ag.stop() }
        .onChange(of: sensor.direction) { _, _ in rotateCamera() }
        .onChange(of: status.isDone) { _, yeni in wasHit = yeni }
        .sensoryFeedback(.success, trigger: status.isDone) { _, yeni in yeni && framing == .yakin }
    }

    private var offlineHint: some View {
        Hint(.warning) {
            VStack(alignment: .leading, spacing: 10) {
                Text(app: "kible.harita.cevrimdisi")
                Button(localized("kible.harita.pusulaya_gec"), action: switchToCompass)
                    .buttonStyle(SecondaryButton())
            }
        }
    }

    private var map: some View {
        Map(position: $camera, interactionModes: framing == .yakin ? [.zoom] : .all) {
            // Bright yellow with a dark edge: clearly visible on light and dark tiles.
            MapPolyline(MKGeodesicPolyline(coordinates: [start, kaaba], count: 2))
                .stroke(.black.opacity(0.55), style: StrokeStyle(lineWidth: 9, lineCap: .round))
            MapPolyline(MKGeodesicPolyline(coordinates: [start, kaaba], count: 2))
                .stroke(theme.colors.qiblaYellow, style: StrokeStyle(lineWidth: 6, lineCap: .round))
            if framing == .fullRoute {
                ForEach(Array(Self.arrowPoints(start, kaaba).enumerated()), id: \.offset) { _, n in
                    Annotation("", coordinate: n.coordinate, anchor: .center) {
                        HeartMarker(size: 22).rotationEffect(.degrees(n.direction + 180))
                            .accessibilityHidden(true)
                    }
                }
                Annotation(localized("kible.harita.sen"), coordinate: start) { locationDot }
            }
            Annotation(localized("kible.harita.kabe"), coordinate: kaaba) {
                Image(systemName: "cube.fill").font(.system(size: 22))
                    .foregroundStyle(.white).padding(6)
                    .background(Color.black, in: .rect(cornerRadius: 8))
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls {}
        .onMapCameraChange(frequency: .onEnd) { ctx in
            guard framing == .yakin else { return }
            distance = ctx.camera.distance
            if inFlight {
                if MKMapPoint(ctx.camera.centerCoordinate).distance(to: MKMapPoint(start)) < 200 {
                    flightDone()
                }
            } else if !ringReady {
                withAnimation(.easeOut(duration: 0.25)) { ringReady = true }
            }
        }
    }

    private var locationDot: some View {
        Circle().fill(theme.colors.sage).frame(width: 18, height: 18)
            .overlay(Circle().stroke(.white, lineWidth: 3))
    }

    private var altPanel: some View {
        VStack(spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { panelOpen.toggle() }
            } label: {
                VStack(spacing: 6) {
                    Capsule().fill(theme.colors.text2.opacity(0.5)).frame(width: 36, height: 5)
                    HStack(spacing: 8) {
                        Text(verbatim: summary).typography(.emphasized)
                            .foregroundStyle(status.isDone ? theme.colors.successText : theme.colors.text)
                            .multilineTextAlignment(.center)
                        Image(systemName: panelOpen ? "chevron.down" : "chevron.up")
                            .foregroundStyle(theme.colors.text2)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(summary)
            .accessibilityValue(framing == .yakin ? status.spoken : "")
            .accessibilityHint(localized(panelOpen ? "kible.harita.panel_kapat" : "kible.harita.panel_ac"))
            .gesture(
                DragGesture(minimumDistance: 12).onEnded { d in
                    withAnimation(.easeOut(duration: 0.2)) {
                        if d.translation.height < -20 { panelOpen = true }
                        if d.translation.height > 20 { panelOpen = false }
                    }
                })
            if panelOpen {
                Group {
                    if framing != .yakin || !hasCompass {
                        Text(app: "kible.harita.ipucu")
                    } else if sensor.pose != .flat {
                        Label(localized("kible.harita.duz_tut"), systemImage: "iphone.gen3")
                    } else {
                        Text(verbatim: status.title)
                    }
                }
                .typography(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(status.isDone ? theme.colors.successText : theme.colors.text)
                .accessibilityAddTraits(.updatesFrequently)
                .transition(.opacity)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { buttons }
                VStack(spacing: 10) { buttons }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: .rect(cornerRadius: 20))
        .padding(12)
    }

    /// Collapsed row: Qibla angle and distance.
    private var summary: String {
        let km = (QiblaCalculation.distance(location) / 1000).formatted(.number.precision(.fractionLength(0)))
        return localized("kible.harita.aci \(Int(qibla.rounded()))") + " · "
            + localized("kible.harita.uzaklik \(km)")
    }

    /// The button of the currently inactive view is the strong one. The label is short
    /// („Konum“, „Kâbe“) so that both fit side by side; VoiceOver reads the full text.
    @ViewBuilder private var buttons: some View {
        mapButton(
            "kible.harita.konum_kisa", tam: "kible.harita.konumuma_don", icon: "location.fill",
            emphasized: framing == .fullRoute
        ) {
            flyClose(animated: true)
        }
        mapButton(
            "kible.harita.kabe", tam: "kible.harita.kabeyi_goster", icon: "globe.europe.africa.fill",
            emphasized: framing == .yakin
        ) {
            showFullRoute()
        }
    }

    @ViewBuilder
    private func mapButton(
        _ key: String.LocalizationValue, tam: String.LocalizationValue, icon: String, emphasized: Bool,
        _ action: @escaping () -> Void
    ) -> some View {
        let label = Label(localized(key), systemImage: icon).frame(maxWidth: .infinity)
        if emphasized {
            Button(action: action) { label }.buttonStyle(PrimaryButton()).accessibilityLabel(localized(tam))
        } else {
            Button(action: action) { label }.buttonStyle(SecondaryButton()).accessibilityLabel(localized(tam))
        }
    }

    private func flyClose(animated: Bool) {
        framing = .yakin
        ringReady = !animated
        lastHeading = cardHeading
        distance = 900
        let yeni = MapCameraPosition.camera(
            MapCamera(centerCoordinate: start, distance: 900, heading: cardHeading, pitch: 0))
        if animated {
            inFlight = true
            flightID += 1
            let number = flightID
            withAnimation(.easeInOut(duration: 0.6)) { camera = yeni }
            Task {
                try? await Task.sleep(for: Self.flightLimit)
                if flightID == number && inFlight { flightDone() }
            }
        } else {
            camera = yeni
        }
    }

    /// The flight has arrived: show the ring and catch up on the rotation that the compass
    /// accumulated along the way.
    private func flightDone() {
        inFlight = false
        guard framing == .yakin else { return }
        withAnimation(.easeOut(duration: 0.25)) { ringReady = true }
        rotateCamera()
    }

    /// During the flight Kaaba → location the compass does not follow the rotation; every hard setting of the camera
    /// aborted the animation and made it stutter.
    private func rotateCamera() {
        guard framing == .yakin, !inFlight else { return }
        let y = cardHeading
        if let s = lastHeading, abs(QiblaCalculation.difference(s, y)) < Self.headingStep { return }
        lastHeading = y
        camera = .camera(MapCamera(centerCoordinate: start, distance: distance, heading: y, pitch: 0))
    }

    private func showFullRoute() {
        framing = .fullRoute
        ringReady = false
        inFlight = false
        let path = MKGeodesicPolyline(coordinates: [start, kaaba], count: 2).boundingMapRect
        let screen = mapSize == .zero ? CGSize(width: 390, height: 600) : mapSize
        let bottom = Double(min(panelHeight, screen.height * 0.7))
        let c = QiblaFraming.frame(
            path: CGRect(
                x: path.origin.x, y: path.origin.y, width: path.size.width, height: path.size.height),
            size: CGSize(width: screen.width, height: screen.height + bottom), top: bottom, bottom: bottom)
        withAnimation(.easeInOut(duration: 0.8)) {
            camera = .rect(MKMapRect(x: c.minX, y: c.minY, width: c.width, height: c.height))
        }
    }

    struct ArrowPoint {
        let coordinate: CLLocationCoordinate2D
        /// Direction to the Kaaba at this point (degrees, north = 0) – on the great circle it changes.
        let direction: Double
    }

    /// Evenly spaced points on the great circle between start and Kaaba (without the ends).
    static func arrowPoints(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> [ArrowPoint] {
        let p1 = MKMapPoint(a)
        let path = MKGeodesicPolyline(coordinates: [a, b], count: 2)
        let points = UnsafeBufferPointer(start: path.points(), count: path.pointCount)
        guard points.count > 2, MKMapPoint(b).distance(to: p1) > 50_000 else { return [] }
        return (1...arrowCount).map { i in
            let n = points[points.count * i / (arrowCount + 1)].coordinate
            return ArrowPoint(
                coordinate: n, direction: QiblaCalculation.angle(latitude: n.latitude, longitude: n.longitude)
            )
        }
    }
}

/// Compass ring around the own location (map center): cardinal directions rotate with the map,
/// the Kaaba sits on the ring in the Qibla direction, an arrow at the top as soon as the user is aligned.
struct MapRing: View {
    @Environment(\.theme) private var theme
    let direction: Double
    let qibla: Double
    let done: Bool
    /// Radius from the free map area above the panel, not from the whole height (K4, K8).
    let radius: CGFloat

    var body: some View {
        GeometryReader { g in
            let r = radius
            ZStack {
                Circle().stroke(theme.colors.text.opacity(0.55), lineWidth: 1.5).frame(
                    width: r * 2, height: r * 2)
                DirectionLetters(direction: direction, r: r - 16)
                Image(systemName: "cube.fill").font(.system(size: 20))
                    .foregroundStyle(.white).padding(5)
                    .background(Color.black, in: .rect(cornerRadius: 7))
                    .rotationEffect(.degrees(-(qibla - direction)))
                    .offset(y: -r)
                    .rotationEffect(.degrees(qibla - direction))
                if done {
                    HeartMarker(size: 40).offset(y: -r * 0.55)
                        .transition(.scale.combined(with: .opacity))
                }
                Circle().fill(theme.colors.sage).frame(width: 18, height: 18)
                    .overlay(Circle().stroke(.white, lineWidth: 3))
            }
            .frame(width: g.size.width, height: g.size.height)
            .animation(.easeOut(duration: 0.2), value: done)
        }
    }
}

/// A heart in Qibla yellow with a dark edge; the tip points down, so rotate by the direction + 180°.
struct HeartMarker: View {
    @Environment(\.theme) private var theme
    let size: CGFloat

    var body: some View {
        ZStack {
            Image(systemName: "heart.fill").font(.system(size: size + 5)).foregroundStyle(
                .black.opacity(0.7))
            Image(systemName: "heart.fill").font(.system(size: size)).foregroundStyle(
                theme.colors.qiblaYellow)
        }
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }
}

/// Reports whether there is network; without network MapKit loads no tiles and the map would stay empty (K16).
@MainActor @Observable final class NetworkMonitor {
    private(set) var connected = true
    private var monitor: NWPathMonitor?

    func start() {
        guard monitor == nil else { return }
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in
            let link = path.status == .satisfied
            Task { @MainActor in self?.connected = link }
        }
        m.start(queue: .global(qos: .utility))
        monitor = m
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
    }
}
