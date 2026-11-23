#if os(iOS)
    import Foundation
    import WatchConnectivity
    import WidgetBridge

    /// Sends the widget snapshot to the Watch app. Only the latest one counts,
    /// hence `updateApplicationContext` instead of messages.
    @MainActor final class WatchSender: NSObject, WCSessionDelegate {
        static let shared = WatchSender()

        func gonder(_ a: PrayerTimesSnapshot) {
            guard let veri = try? JSONEncoder().encode(a) else { return }
            context["anlik"] = veri
            send()
        }

        /// Reading state for complication F (); travels in the same context, because
        /// `updateApplicationContext` always replaces the entire content.
        func gonder(reading: ReadingSnapshot) {
            guard let veri = try? JSONEncoder().encode(reading) else { return }
            context["okuma"] = veri
            send()
        }

        private var context: [String: Any] = [:]
        private var isPending = false

        private func send() {
            guard WCSession.isSupported() else { return }
            let s = WCSession.default
            if s.delegate == nil {
                s.delegate = self
                s.activate()
            }
            guard s.activationState == .activated, s.isPaired, s.isWatchAppInstalled else {
                isPending = true
                return
            }
            try? s.updateApplicationContext(context)
        }

        nonisolated func session(
            _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
            error: Error?
        ) {
            Task { @MainActor in
                let s = WCSession.default
                if self.isPending, s.isPaired, s.isWatchAppInstalled {
                    try? s.updateApplicationContext(self.context)
                    self.isPending = false
                }
            }
        }

        nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
        nonisolated func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
    }
#endif
