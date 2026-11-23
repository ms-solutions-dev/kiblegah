import ActivityKit
import AppIntents
import Core
import DesignSystem
import SwiftUI
import WidgetBridge
import WidgetKit

/// Live Activity: countdown to the next prayer, in the Karahat phase with its end.
struct PrayerTimeLiveActivity: Widget {
    /// Range up to the prayer; empty after the prayer instead of reversed.
    static func remaining(_ time: Date) -> ClosedRange<Date> {
        let now = Date.now
        return now...max(now, time)
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VakitEtkinligi.self) { ctx in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: ctx.attributes.location).font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: ctx.state.nextName).font(.headline)
                    if let k = ctx.state.karahatEnd {
                        // The activity carries no time zone of its own: device time zone, app language.
                        Text(
                            app:
                                "widget.kerahat \(k.clockText(in: .current, locale: AppLanguage.clockLocale))"
                        )
                        .font(.caption)
                    }
                }
                Spacer()
                Text(timerInterval: Self.remaining(ctx.state.nextTime), countsDown: true)
                    .font(.title2.monospacedDigit()).multilineTextAlignment(.trailing)
            }
            .padding()
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text(verbatim: ctx.state.nextName).font(.headline) }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Self.remaining(ctx.state.nextTime), countsDown: true)
                        .monospacedDigit()
                }
            } compactLeading: {
                Text(verbatim: String(ctx.state.nextName.prefix(3)))
            } compactTrailing: {
                Text(timerInterval: Self.remaining(ctx.state.nextTime), countsDown: true).monospacedDigit()
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "clock")
            }
            .widgetURL(URL(string: "kiblegah://vakit"))
        }
    }
}

/// Qibla control for lock screen, Control Center and Action Button.
struct QiblaControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "dev.ms-solutions.kiblegah.kible") {
            ControlWidgetButton(action: KibleAcNiyeti()) {
                Label {
                    Text(app: "kible.kontrol.baslik")
                } icon: {
                    Image(systemName: "location.north.circle")
                }
            }
        }
        .displayName(LocalizedStringResource("kible.kontrol.baslik"))
        .description(LocalizedStringResource("kible.kontrol.aciklama"))
    }
}
