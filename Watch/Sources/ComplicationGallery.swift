#if DEBUG
    import SwiftUI
    import WidgetBridge
    import WidgetKit

    /// README screenshots of the complications, opened with `-saatEkran komplikasyon1` (rectangular)
    /// or `-saatEkran komplikasyon2` (circular), see tools/screenshots.sh.
    ///
    /// A watch face cannot be set up from the command line, so the watch app shows the same views
    /// as the widget extension (ComplicationViews.swift) with the same snapshot, at the sizes of a
    /// 45/46 mm watch face, in full colour on black. The corner complication is left out: its curved
    /// text only exists on a watch face.
    struct ComplicationGallery: View {
        let snapshot: PrayerTimesSnapshot?
        let page: String

        var body: some View {
            TimelineView(.everyMinute) { c in
                let g = WatchEntry(
                    date: c.date, snapshot: snapshot,
                    status: snapshot.flatMap { PrayerStatus.status($0, now: c.date) })
                Group {
                    if page == "komplikasyon2" {
                        HStack(spacing: 10) {
                            PrayerTimeComplicationView(g: g, family: .accessoryCircular).circular()
                            QiblaComplicationView(snapshot: snapshot).circular()
                            ReadingComplicationView(o: ReadingSnapshot.load()?.valid(time: c.date)).circular()
                        }
                    } else {
                        VStack(spacing: 14) {
                            PrayerTimeComplicationView(g: g, family: .accessoryRectangular).rectangular()
                            DayScheduleView(g: g).rectangular()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
            }
        }
    }

    extension View {
        /// Circular complications are masked to a circle by the watch face.
        fileprivate func circular() -> some View { frame(width: 50, height: 50).clipShape(Circle()) }
        fileprivate func rectangular() -> some View { frame(width: 184, height: 80) }
    }
#endif
