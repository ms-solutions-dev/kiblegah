import ContentPacks
import Core
import DesignSystem
import PrayerTimes
import SwiftUI
import UserData

/// The start tab „Bugün“: the next prayer time as a large card,
/// the other times in one row, below that daily points, reading week and a swipe stack of
/// verse of the day, question of the day and continue reading.
///
/// „Büyük ve sade“ shows only countdown and time table as before. Only the upper part
/// runs every second; the cards below read user data and follow the minute.
struct TodayScreen: View {
    /// For testing only: `-saatKaydir 3600` shifts the start page's clock (karahat states,).
    #if DEBUG
        static let timeShift = UserDefaults.standard.double(forKey: "saatKaydir")
    #else
        static let timeShift: TimeInterval = 0
    #endif

    @Environment(PrayerTimeModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var direction
    @Environment(\.theme) private var theme
    @State private var selectingLocation = false
    @State private var karahatOpen = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            if PadLayout.isPad, sizeClass == .regular {
                PadTodayScreen(selectingLocation: $selectingLocation, karahatOpen: $karahatOpen)
            } else if let table = model.table, settings.location != nil {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            parent(table, time: context.date + Self.timeShift)
                        }
                        if !settings.largeAndSimple {
                            TimelineView(.everyMinute) { context in
                                TodayCards(day: Day(context.date, timeZoneIdentifier: .current))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .refreshable {
                    if let k = settings.location { await model.refresh(k, settings: settings, force: true) }
                }
            } else if settings.location == nil {
                NoLocationScreen { selectingLocation = true }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .pageBackground()
        .hideTopBar()
        .sheet(isPresented: $selectingLocation) { LocationPickerScreen() }
        .sheet(isPresented: $karahatOpen) { KarahatScreen() }
    }

    @ViewBuilder
    private func parent(_ table: PrayerTimeTable, time: Date) -> some View {
        let tz = table.location.timeZone
        let today = Day(time, timeZoneIdentifier: tz)
        if let status = PrayerTimeStatus(table: table, time: time), let todayEntry = table.day(today) {
            let night = status.current == .isha && status.next == .imsak && time > todayEntry[.isha]
            let listDay = night ? (table.day(today.added(1)) ?? todayEntry) : todayEntry
            let timeline = DayTimeline(
                today: todayEntry, tomorrow: table.day(today.added(1)),
                karahatMinutes: settings.karahatMinutes)
            let ramadan = timeline.isRamadan
            let friday = DayTimeline(today: listDay, tomorrow: nil).isFriday
            VStack(alignment: .leading, spacing: 16) {
                title(table, todayEntry: todayEntry, ramadan: ramadan)
                if let suggestion = model.suggestedLocation { locationBanner(suggestion) }
                if settings.largeAndSimple {
                    counter(status, time: time, timeline: timeline, ramadan: ramadan, tz: tz)
                } else {
                    NextPrayerCard(
                        status: status, time: time, tz: tz, friday: timeline.isFriday, ramadan: ramadan,
                        timeline: timeline
                    ) { karahatOpen = true }
                    // A narrow window on the iPad (board G11): the list of the times.
                    if PadLayout.isPad {
                        PrayerTimeList(
                            day: listDay, status: status, tz: tz, friday: friday, ramadan: ramadan,
                            tomorrow: night)
                    } else {
                        OtherTimes(day: listDay, status: status, tz: tz, friday: friday, tomorrow: night)
                    }
                }
                // Without „sade“ the card itself shows the karahat ().
                if settings.largeAndSimple, let k = timeline.karahat(time) { karahatBanner(k, tz: tz) }
                if night, let end = timeline.lastThird {
                    Text(app: "vakit.gece.son_ucte_bir \(end.timeText(tz))")
                        .typography(.body).foregroundStyle(theme.colors.text2)
                }
                if ramadan { ramadanRow(todayEntry, tz: tz) }
                if let kandil = model.upcomingReligiousDay(today: today) {
                    kandilBanner(kandil, today: today)
                }
                if settings.largeAndSimple {
                    PrayerTimeList(
                        day: listDay, status: status, tz: tz, friday: friday, ramadan: ramadan,
                        tomorrow: night)
                    sourceRow(table, day: listDay, today: today)
                    allPrayerTimes
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        allPrayerTimes
                        Spacer(minLength: 8)
                    }
                    sourceRow(table, day: listDay, today: today)
                }
            }
        } else {
            EmptyState(title: "vakit.bos.baslik", explanation: "vakit.bos.aciklama")
                .padding(20)
        }
    }

    private var allPrayerTimes: some View {
        NavigationLink(value: Goal.allPrayerTimes) {
            Label {
                Text(app: "vakit.tum_vakitler")
            } icon: {
                Image(systemName: "chevron.right")
            }
            .labelStyle(TrailingIcon())
            .typography(.emphasized).foregroundStyle(theme.colors.accent)
            .frame(minHeight: 44)
        }
    }

    private func title(_ table: PrayerTimeTable, todayEntry: DailyPrayerTimes, ramadan: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Button {
                    selectingLocation = true
                } label: {
                    HStack(spacing: 6) {
                        // Never break place names in the middle of a word; at AX sizes prefer smaller.
                        Text(verbatim: table.location.name).typography(.emphasized)
                            .lineLimit(1).minimumScaleFactor(0.5)
                        Image(systemName: "chevron.down").font(.footnote.weight(.bold)).accessibilityHidden(
                            true)
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(localized("vakit.konum.degistir \(table.location.name)"))
                Spacer()
                NavigationLink(value: Goal.notifications) {
                    Image(systemName: "bell").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(localized("bildirim.baslik"))
            }
            Text(verbatim: dateLine(todayEntry, ramadan: ramadan, tz: table.location.timeZone))
                .typography(.secondary).foregroundStyle(theme.colors.text2)
        }
        .padding(.top, 8)
    }

    private func dateLine(_ g: DailyPrayerTimes, ramadan: Bool, tz: TimeZone) -> String {
        var style = Date.FormatStyle(date: .complete, time: .omitted).year(.omitted)
        style.locale = AppLanguage.locale
        style.timeZone = tz
        let gregorian = g.day.start(tz).addingTimeInterval(12 * 3600).formatted(style)
        guard let h = g.hijri else { return gregorian }
        // Month name in the app language (Diyanet's spelling in Turkish).
        let month = localized(key: "hicri.ay.\(h.month)", fallback: h.monthName)
        // No-break spaces and hyphens: in large type the Hijri date wraps as a whole
        // („22 Jumada al-Ula 1448“), not after the day or the article.
        let hijri =
            "\(h.day) \(month) \(h.year)".replacingOccurrences(of: " ", with: "\u{00A0}")
            .replacingOccurrences(of: "-", with: "\u{2011}")
            + (g.source == .diyanet || HijriDate.exact(g.day) ? "" : " (\(localized("vakit.yaklasik")))")
        return "\(gregorian) · \(hijri)"
    }

    /// Countdown in „Büyük ve sade“: without seconds - the per-second flicker is restlessness for 60+ without
    /// benefit. Rounded up to the full minute like VoiceOver, so that „0 dk“ never appears.
    private func counter(
        _ d: PrayerTimeStatus, time: Date, timeline: DayTimeline, ramadan: Bool, tz: TimeZone
    ) -> some View {
        let s = Counter(remaining: (d.nextTime.timeIntervalSince(time) / 60).rounded(.up) * 60)
        let friday = d.next == .dhuhr && timeline.isFriday
        let title = d.next.targetTitle(friday: friday, ramadan: ramadan)
        return VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: title).typography(.title2).foregroundStyle(theme.colors.accent)
            Text(verbatim: s.text).typography(.accent).monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(s.spoken)")
    }

    private func karahatBanner(_ k: KarahatWindow, tz: TimeZone) -> some View {
        Button {
            karahatOpen = true
        } label: {
            Hint(.warning) {
                HStack {
                    Text(app: "kerahat.bant \(k.end.timeText(tz))")
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(localized("kerahat.nedir"))
    }

    private func locationBanner(_ k: Location) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text(app: "konum.degisti \(k.name)").typography(.emphasized)
                HStack {
                    Button(localized("konum.degisti.evet")) {
                        Task { await model.selectLocation(k, settings: settings, automatic: true) }
                    }
                    .buttonStyle(PrimaryButton())
                    Button(localized("konum.degisti.hayir")) { model.dismissSuggestion() }
                        .buttonStyle(SecondaryButton())
                }
            }
        }
    }

    private func ramadanRow(_ g: DailyPrayerTimes, tz: TimeZone) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(app: "ramazan.sahur").typography(.footnote).foregroundStyle(theme.colors.text2)
                Text(verbatim: g[.imsak].timeText(tz)).typography(.title2).monospacedDigit()
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(app: "ramazan.iftar").typography(.footnote).foregroundStyle(theme.colors.text2)
                Text(verbatim: g[.maghrib].timeText(tz)).typography(.title2).monospacedDigit()
            }
        }
        .padding(16)
        .background(theme.colors.surface2, in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    private func kandilBanner(_ d: ReligiousDay, today: Day) -> some View {
        Hint(.success) {
            Text(verbatim: d.text(today: today))
        }
    }

    private func sourceRow(_ t: PrayerTimeTable, day: DailyPrayerTimes, today: Day) -> some View {
        // Without „… tarihine kadar“: nobody can do anything with the stock date.
        let key: String =
            day.source == .diyanet
            ? localized("vakit.kaynak.diyanet \(t.location.name)")
            : localized("vakit.kaynak.hesaplanan \(t.location.name)")
        return Label {
            Text(verbatim: key)
        } icon: {
            Image(systemName: day.source == .diyanet ? "checkmark.seal" : "clock")
        }
        .typography(.footnote).foregroundStyle(theme.colors.text2)
    }
}

/// The six times; „Sıradaki“ strong, „şimdi“ quiet.
struct PrayerTimeList: View {
    @Environment(\.theme) private var theme
    let day: DailyPrayerTimes
    let status: PrayerTimeStatus?
    let tz: TimeZone
    let friday: Bool
    let ramadan: Bool
    let tomorrow: Bool

    var body: some View {
        VStack(spacing: 2) {
            if tomorrow {
                Text(app: "vakit.yarin.baslik").typography(.footnote).foregroundStyle(theme.colors.text2)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.top, 8)
            }
            ForEach(Prayer.allCases, id: \.self) { n in
                row(n)
            }
        }
        .padding(6)
        .background(theme.colors.surface, in: .rect(cornerRadius: 24))
    }

    private func row(_ n: Prayer) -> some View {
        let time = day[n]
        let next = status?.next == n && status?.nextTime == time
        let now = !tomorrow && status?.current == n && status?.currentStart == time
        var ek = ""
        if ramadan && n == .maghrib { ek = " · " + localized("ramazan.iftar") }
        if ramadan && n == .isha { ek = " · " + localized("ramazan.teravih") }
        return HStack {
            if now {
                Circle().fill(theme.colors.sage).frame(width: 8, height: 8).accessibilityHidden(true)
            }
            Text(verbatim: n.name(friday: friday) + ek)
            if next {
                Text(app: tomorrow ? "vakit.siradaki.yarin" : "vakit.siradaki").typography(.secondary)
            } else if now {
                Text(app: "vakit.simdi").typography(.secondary).foregroundStyle(theme.colors.text2)
            }
            Spacer()
            Text(verbatim: time.timeText(tz)).monospacedDigit()
        }
        .typography(next ? .emphasized : .body)
        .foregroundStyle(
            next
                ? (PadLayout.isPad ? theme.colors.accent : theme.colors.onAccent)
                : (n == .sunrise ? theme.colors.text2 : theme.colors.text)
        )
        .padding(.horizontal, 14)
        .padding(.vertical, next ? 14 : 11)
        .background(
            next ? (PadLayout.isPad ? theme.colors.surface2 : theme.colors.accent) : .clear,
            in: .rect(cornerRadius: PadLayout.isPad ? 16 : 18)
        )
        .accessibilityElement(children: .combine)
    }
}

/// Label with symbol on the right (for „Tüm vakitler ›“).
struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon.font(.footnote.weight(.bold)).accessibilityHidden(true)
        }
    }
}

extension ReligiousDay {
    /// „Yarın akşam Regaip Kandili“ / „Bugün Ramazan Bayramı“.
    func text(today: Day) -> String {
        let name = AppLanguage.bundle.localizedString(forKey: "dini." + kind.rawValue, value: nil, table: nil)
        if day == today {
            return isNight ? localized("dini.bu_aksam \(name)") : localized("dini.bugun \(name)")
        }
        if day == today.added(1) {
            return isNight ? localized("dini.yarin_aksam \(name)") : localized("dini.yarin \(name)")
        }
        let difference =
            Calendar(identifier: .gregorian).dateComponents(
                [.day], from: today.start(.gmt), to: day.start(.gmt)
            ).day ?? 0
        return localized("dini.gun_sonra \(difference) \(name)")
    }
}
