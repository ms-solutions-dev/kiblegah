#if os(iOS)
    import ActivityKit
    import AppIntents
    import Foundation

    /// Live Activity „sıradaki vakit“ with Karahat phase. App and widget share the type.
    public struct VakitEtkinligi: ActivityAttributes {
        enum CodingKeys: String, CodingKey {
            case location = "konum"
        }

        public struct ContentState: Codable, Hashable, Sendable {
            enum CodingKeys: String, CodingKey {
                case nextName = "siradakiAd"
                case nextTime = "siradakiAn"
                case karahatEnd = "kerahatSonu"
            }

            public let nextName: String
            public let nextTime: Date
            public let karahatEnd: Date?

            public init(nextName: String, nextTime: Date, karahatEnd: Date?) {
                self.nextName = nextName
                self.nextTime = nextTime
                self.karahatEnd = karahatEnd
            }
        }

        public let location: String

        public init(location: String) {
            self.location = location
        }
    }

    /// Opens the app directly on Qibla - for the control (lock screen, Control Center)
    /// and Action Button. A live compass in the widget is not possible (no sensor access),
    /// hence the jump into the app.
    public struct KibleAcNiyeti: AppIntent {
        public static let title: LocalizedStringResource = "kible.kontrol.baslik"
        public static let description = IntentDescription("kible.kontrol.aciklama")
        public static let supportedModes: IntentModes = .foreground

        public init() {}

        /// Thanks to `.foreground` runs in the app's process: the target lands in the App Group, the app
        /// reads it when becoming active (`KibleAcNiyeti.pending`). `OpenURLIntent` with a custom scheme
        /// does not work from controls (only universal links, StoryShelf finding of Sep 20).
        @MainActor
        public func perform() async throws -> some IntentResult {
            UserDefaults(suiteName: PrayerTimesSnapshot.appGroup)?.set("kiblegah://kible", forKey: Self.key)
            return .result()
        }

        static let key = "acilisHedefi"

        /// The target of a control that was just pressed, one-time (deleted afterwards).
        public static func pending() -> URL? {
            let d = UserDefaults(suiteName: PrayerTimesSnapshot.appGroup)
            defer { d?.removeObject(forKey: key) }
            return d?.string(forKey: key).flatMap(URL.init(string:))
        }
    }
#endif
