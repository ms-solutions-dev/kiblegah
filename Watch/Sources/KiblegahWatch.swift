import CoreLocation
import Qibla
import SwiftUI
import WatchConnectivity
import WidgetKit
import WidgetBridge

/// Watch app: next prayer with countdown, times of the day, Qibla compass.
///
/// Calculates nothing itself: on every update the iPhone sends the widget snapshot
/// (`PrayerTimesSnapshot`) via WatchConnectivity; the watch keeps the latest one and shows it even without the phone.
@main
struct KiblegahWatch: App {
    @State private var link = WatchConnection()
    @State private var page = 0

    init() {
        #if DEBUG
            if UserDefaults.standard.string(forKey: "saatEkran") == "kible" { _page = State(initialValue: 1) }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
                // Screenshots without taps (tools/screenshots.sh): `-saatEkran kible` opens the
                // Qibla page, `-saatEkran komplikasyon1|komplikasyon2` the complication views.
                let screen = UserDefaults.standard.string(forKey: "saatEkran") ?? ""
                if screen.hasPrefix("komplikasyon") {
                    ComplicationGallery(snapshot: link.snapshot, page: screen)
                } else {
                    pages
                }
            #else
                pages
            #endif
        }
    }

    private var pages: some View {
        TabView(selection: $page) {
            PrayerTimePage(snapshot: link.snapshot).tag(0)
            QiblaPage(snapshot: link.snapshot).tag(1)
        }
        .tabViewStyle(.verticalPage)
    }
}

/// Receives the snapshot from the iPhone and stores it.
@MainActor @Observable final class WatchConnection: NSObject, WCSessionDelegate {
    private(set) var snapshot: PrayerTimesSnapshot?

    private static var file: URL { URL.applicationSupportDirectory.appending(path: PrayerTimesSnapshot.fileName) }

    override init() {
        super.init()
        snapshot = PrayerTimesSnapshot.load(Self.file)
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    nonisolated func session(
        _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let c = session.receivedApplicationContext
        let (veri, reading) = (c["anlik"] as? Data, c["okuma"] as? Data)
        Task { @MainActor in self.al(veri, reading) }
    }

    nonisolated func session(
        _ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        let (veri, reading) = (applicationContext["anlik"] as? Data, applicationContext["okuma"] as? Data)
        Task { @MainActor in self.al(veri, reading) }
    }

    /// Stores the state: for the app itself and in the App Group for the complications ().
    private func al(_ veri: Data?, _ reading: Data? = nil) {
        if let reading, let o = try? JSONDecoder().decode(ReadingSnapshot.self, from: reading) { o.save() }
        if let veri, let a = try? JSONDecoder().decode(PrayerTimesSnapshot.self, from: veri) {
            try? FileManager.default.createDirectory(
                at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
            a.save(Self.file)
            a.save()
            snapshot = a
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

struct PrayerTimePage: View {
    let snapshot: PrayerTimesSnapshot?

    var body: some View {
        TimelineView(.everyMinute) { c in
            if let a = snapshot, let g = a.entry(time: c.date) {
                // Times in the time zone of the place, as on the iPhone and in the complications.
                let tz = TimeZone(identifier: a.timeZoneIdentifier) ?? .current
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: g.next.name).font(.headline).foregroundStyle(.tint)
                        Text(timerInterval: c.date...max(c.date, g.next.time), countsDown: true)
                            .font(.system(.title, design: .rounded).monospacedDigit())
                        if let k = g.karahatEnd {
                            Label {
                                Text("saat.kerahat \(k.clockText(in: tz))")
                            } icon: {
                                Image(systemName: "exclamationmark.triangle")
                            }
                            .font(.footnote).foregroundStyle(.orange)
                        }
                        Divider()
                        ForEach(today(a, c.date), id: \.identifier) { v in
                            HStack {
                                Text(verbatim: v.name)
                                Spacer()
                                Text(verbatim: v.time.clockText(in: tz)).monospacedDigit()
                            }
                            .font(.footnote)
                            .foregroundStyle(
                                v.identifier == g.next.identifier && v.time == g.next.time ? .primary : .secondary
                            )
                        }
                        Text(verbatim: a.location).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("saat.bos").multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
        }
    }

    private func today(_ a: PrayerTimesSnapshot, _ time: Date) -> [PrayerTimesSnapshot.PrayerTime] {
        var t = Calendar(identifier: .gregorian)
        t.timeZone = TimeZone(identifier: a.timeZoneIdentifier) ?? .current
        return a.prayerTimes.filter { t.isDate($0.time, inSameDayAs: time) }
    }
}

/// Compass with Qibla arrow and upright, localized cardinal directions as in the app (K13);
/// without a compass (or on interference) „güneşe göre“ remains.
struct QiblaPage: View {
    let snapshot: PrayerTimesSnapshot?
    @State private var compass = Compass()

    var body: some View {
        VStack(spacing: 6) {
            if let a = snapshot, let qibla = a.qiblaAngle {
                ZStack {
                    Circle().strokeBorder(.secondary.opacity(0.4), lineWidth: 2)
                    ForEach(0..<4, id: \.self) { i in
                        let p = CompassLetter.location(i, direction: compass.direction ?? 0, r: 50)
                        Text(LocalizedStringKey(CompassLetter.key(i))).font(.caption2.bold())
                            .foregroundStyle(i == 0 ? Color.accentColor : .secondary)
                            .offset(x: p.x, y: p.y)
                    }
                    Image(systemName: "location.north.fill").font(.system(size: 34)).foregroundStyle(
                        aligned(qibla) ? .green : .accentColor
                    )
                    .rotationEffect(.degrees(qibla - (compass.direction ?? 0)))
                    .opacity(compass.direction == nil ? 0.35 : 1)
                }
                .frame(width: 120, height: 120)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("saat.kible"))
                if compass.direction == nil {
                    sunDirection(a, qibla)
                } else {
                    Text("saat.kible.derece \(Int(qibla.rounded()))").font(.footnote).foregroundStyle(
                        .secondary)
                }
            } else {
                Text("saat.bos").multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
        }
        .onAppear { compass.start() }
        .onDisappear { compass.stop() }
    }

    private func aligned(_ qibla: Double) -> Bool {
        guard let y = compass.direction, compass.trueNorth else { return false }
        return abs(QiblaCalculation.difference(y, qibla)) < max(5, compass.accuracy)
    }

    @ViewBuilder private func sunDirection(_ a: PrayerTimesSnapshot, _ qibla: Double) -> some View {
        if let e = a.latitude, let b = a.longitude {
            let f = SunPosition.qiblaOffset(time: .now, latitude: e, longitude: b, qibla: qibla)
            if f.altitude > SunPosition.visibleHeight {
                let d = Int(abs(f.difference).rounded())
                Text(f.difference >= 0 ? "widget.gunes.sag \(d)" : "widget.gunes.sol \(d)").font(.footnote)
            }
        }
    }
}

@MainActor @Observable final class Compass: NSObject, CLLocationManagerDelegate {
    private(set) var direction: Double?
    /// `false` as long as only magnetic north is known (declination up to over 10°).
    private(set) var trueNorth = false
    /// `headingAccuracy` in degrees; the hit window is never narrower.
    private(set) var accuracy: Double = 5
    private let manager = CLLocationManager()

    /// True north is only available while location data is also running;
    /// rough is enough, the declination barely changes over kilometers.
    func start() {
        guard CLLocationManager.headingAvailable() else { return }
        manager.delegate = self
        manager.headingFilter = 2
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
    }

    func stop() {
        manager.stopUpdatingHeading()
        manager.stopUpdatingLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let hasTrueHeading = newHeading.trueHeading >= 0
        let y = hasTrueHeading ? newHeading.trueHeading : newHeading.magneticHeading
        let valid = newHeading.headingAccuracy >= 0
        let d = newHeading.headingAccuracy
        Task { @MainActor in
            self.direction = valid ? y : nil
            self.trueNorth = hasTrueHeading
            self.accuracy = d
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation])
    {}

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
