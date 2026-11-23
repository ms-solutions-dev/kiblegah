import Core
import DesignSystem
import PrayerTimes
import SwiftUI
import UserData

/// Tüm vakitler: today with extra times, then seven days.
/// From large font size the days stack as cards instead of a table.
struct AllPrayerTimesScreen: View {
    @Environment(PrayerTimeModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var size
    @State private var extraOpen = true

    var body: some View {
        ScrollView {
            if let t = model.table {
                let tz = t.location.timeZone
                let today = Day(.now, timeZoneIdentifier: tz)
                VStack(alignment: .leading, spacing: 16) {
                    if let g = t.day(today) {
                        let timeline = DayTimeline(
                            today: g, tomorrow: t.day(today.added(1)), karahatMinutes: settings.karahatMinutes
                        )
                        DisclosureGroup(isExpanded: $extraOpen) {
                            VStack(spacing: 8) {
                                extraRow("ek.israk", timeline.ishraq, tz)
                                extraRow("ek.kusluk_sonu", timeline.duha.upperBound, tz)
                                if let y = timeline.midnight { extraRow("ek.gece_yarisi", y, tz) }
                                if let s = timeline.lastThird { extraRow("ek.son_ucte_bir", s, tz) }
                                ForEach(timeline.karahatWindows, id: \.self) { k in
                                    HStack {
                                        Text(app: k.kind.title)
                                        Spacer()
                                        Text(verbatim: "\(k.start.timeText(tz))–\(k.end.timeText(tz))")
                                            .monospacedDigit()
                                    }
                                }
                            }
                            .typography(.body)
                            .padding(.top, 8)
                        } label: {
                            Text(app: "ek.baslik").typography(.title2)
                        }
                        .padding(16)
                        .background(theme.colors.surface, in: .rect(cornerRadius: 22))
                    }
                    Text(app: "vakit.yedi_gun").typography(.title2)
                    ForEach(0..<7, id: \.self) { i in
                        if let g = t.day(today.added(i)) {
                            dayCard(g, tz: tz, isToday: i == 0)
                        }
                    }
                }
                .padding(16)
            }
        }
        .pageBackground()
        .navigationTitle(localized("vakit.tum_vakitler.baslik"))
    }

    private func extraRow(_ key: LocalizedStringKey, _ time: Date, _ tz: TimeZone) -> some View {
        HStack {
            Text(app: key)
            Spacer()
            Text(verbatim: time.timeText(tz)).monospacedDigit()
        }
    }

    private func dayCard(_ g: DailyPrayerTimes, tz: TimeZone, isToday: Bool) -> some View {
        let friday = DayTimeline(today: g, tomorrow: nil).isFriday
        var style = Date.FormatStyle(date: .complete, time: .omitted).year(.omitted)
        style.locale = AppLanguage.locale
        style.timeZone = tz
        let title = g.day.start(tz).addingTimeInterval(12 * 3600).formatted(style)
        let columns = size.isAccessibilitySize ? 1 : 3
        return VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: title).typography(.emphasized).foregroundStyle(
                isToday ? theme.colors.accent : theme.colors.text)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: columns),
                spacing: 8
            ) {
                ForEach(Prayer.allCases, id: \.self) { n in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: n.name(friday: friday)).typography(.footnote).foregroundStyle(
                            theme.colors.text2)
                        Text(verbatim: g[n].timeText(tz)).typography(.body).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.surface, in: .rect(cornerRadius: 22))
    }
}

extension KarahatWindow.Kind {
    var title: LocalizedStringKey {
        switch self {
        case .atSunrise: "kerahat.tur.dogus"
        case .zawal: "kerahat.tur.zeval"
        case .atSunset: "kerahat.tur.batis"
        }
    }
}
