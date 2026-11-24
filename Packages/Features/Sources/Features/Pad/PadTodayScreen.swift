import ContentPacks
import Core
import DesignSystem
import PrayerTimes
import Quran
import SwiftUI
import UserData

/// „Heute“ on the iPad (boards G01, G02, G03): hero with the next prayer, six time cards with their
/// bell, „Für dich heute“ and „Weiterlesen“. Everything further from the iPhone page (daily points, the
/// reading week, all times, the source) follows below the first screen.
struct PadTodayScreen: View {
    @Environment(RecitationPlayer.self) private var player
    @Environment(PrayerTimeModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var direction
    @Environment(UserStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.padWindow) private var window
    @Binding var selectingLocation: Bool
    @Binding var karahatOpen: Bool
    @State private var page = CGSize.zero

    /// Portrait layout of board G02. By the window, not the page: the open sidebar makes the page narrow.
    private var tall: Bool { window.height > window.width }
    /// Landscape with a folded sidebar: the band moves from its foot to the bottom of the page.
    private var bandBelow: Bool { tall || page.width >= window.width - 1 }

    var body: some View {
        Group {
            if settings.location == nil {
                PadNoLocation { selectingLocation = true }
            } else if let table = model.table {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            upper(table, time: context.date + TodayScreen.timeShift)
                        }
                        if !settings.largeAndSimple {
                            TimelineView(.everyMinute) { context in
                                PadTodayCards(
                                    day: Day(context.date, timeZoneIdentifier: .current), tall: tall)
                            }
                        }
                    }
                    .padding(.horizontal, tall ? 28 : 16)
                    .padding(.bottom, 20)
                }
                .refreshable {
                    if let k = settings.location { await model.refresh(k, settings: settings, force: true) }
                }
            } else {
                PadTodayLoading()
            }
        }
        .safeAreaInset(edge: .bottom) {
            // While something plays the player takes this place: two floating bars would cover the page.
            if bandBelow, settings.location != nil, !player.isActive {
                bottomBand
            }
        }
        .onGeometryChange(for: CGSize.self, of: \.size) { page = $0 }
    }

    /// Foot of the page: in portrait across the width with „Zeiten ansehen“, in landscape as a short capsule.
    private var bottomBand: some View {
        PrayerBand(style: .capsule, trailing: tall ? localized("ipad.band.zeiten_ansehen") : nil)
            .frame(maxWidth: tall ? .infinity : 380)
            .padding(.horizontal, tall ? 28 : 16)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .shadow(color: .black.opacity(tall ? 0 : 0.12), radius: 12, y: 6)
            .background(alignment: .bottom) {
                // The page must not run visibly past the band.
                LinearGradient(
                    colors: [theme.colors.background.opacity(0), theme.colors.background],
                    startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.45)
                )
                .padding(.top, -16)
                .ignoresSafeArea(edges: .bottom)
            }
    }

    @ViewBuilder
    private func upper(_ table: PrayerTimeTable, time: Date) -> some View {
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
            VStack(alignment: .leading, spacing: 14) {
                header(table, todayEntry: todayEntry, ramadan: ramadan)
                banners(
                    timeline: timeline, table: table, today: today, time: time, night: night, tz: tz,
                    day: todayEntry)
                if settings.largeAndSimple {
                    PadSimpleList(
                        status: status, day: listDay, time: time, tz: tz, friday: friday, ramadan: ramadan,
                        tomorrow: night)
                    if ramadan { ramadanRow(todayEntry, tz: tz) }
                    PadTodayFoot(table: table, day: listDay, today: today)
                } else {
                    PadHero(
                        status: status, time: time, tz: tz, friday: timeline.isFriday, ramadan: ramadan,
                        timeline: timeline, tall: tall
                    ) { karahatOpen = true }
                    .padEnter()
                    if ramadan { ramadanRow(todayEntry, tz: tz) }
                    PadTimeGrid(
                        day: listDay, status: status, tz: tz, friday: friday, tomorrow: night, tall: tall)
                }
            }
        } else {
            EmptyState(title: "vakit.bos.baslik", explanation: "vakit.bos.aciklama").padding(20)
        }
    }

    private func header(_ table: PrayerTimeTable, todayEntry: DailyPrayerTimes, ramadan: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if tall {
                    Text(app: "sekme.vakit").typography(.label(size: 13)).textCase(.uppercase).tracking(1.1)
                        .foregroundStyle(theme.colors.label)
                    Text(app: "ipad.heute.titel").typography(.display(size: 34))
                } else {
                    Text(app: "sekme.vakit").typography(.display(size: 34))
                }
                HStack(spacing: 6) {
                    Button {
                        selectingLocation = true
                    } label: {
                        HStack(spacing: 5) {
                            Text(verbatim: table.location.name).typography(.emphasized).lineLimit(1)
                            Image(systemName: "chevron.down").font(.footnote.weight(.bold))
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(localized("vakit.konum.degistir \(table.location.name)"))
                    Text(verbatim: "·").foregroundStyle(theme.colors.text2).accessibilityHidden(true)
                    Text(
                        verbatim: TodayDateLine.text(todayEntry, tz: table.location.timeZone)
                    )
                    .typography(.secondary).foregroundStyle(theme.colors.text2).lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                roundButton("magnifyingglass", label: localized("kesfet.ara")) {
                    direction.open(.search, tabs: settings.tabs)
                }
                NavigationLink(value: Goal.notifications) {
                    roundIcon("bell")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(localized("bildirim.baslik"))
                if tall {
                    roundButton("gearshape", label: localized("ayarlar.baslik")) {
                        direction.padSettingsOpen = true
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private func roundButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { roundIcon(symbol) }.buttonStyle(.plain).accessibilityLabel(label)
    }

    private func roundIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18))
            .foregroundStyle(theme.colors.text)
            .frame(width: 44, height: 44)
            .background(theme.colors.surface.opacity(0.74), in: .circle)
            .overlay(Circle().strokeBorder(theme.colors.line))
            .contentShape(.circle)
    }

    /// The special states stand above the hero (board G03); Ramadan below it.
    @ViewBuilder
    private func banners(
        timeline: DayTimeline, table: PrayerTimeTable, today: Day, time: Date, night: Bool, tz: TimeZone,
        day: DailyPrayerTimes
    ) -> some View {
        if let suggestion = model.suggestedLocation {
            PadBanner(symbol: "mappin.and.ellipse", text: localized("konum.degisti \(suggestion.name)")) {
                Button(localized("konum.degisti.evet")) {
                    Task { await model.selectLocation(suggestion, settings: settings, automatic: true) }
                }
                .buttonStyle(PadPillButton(filled: true))
                Button(localized("konum.degisti.hayir")) { model.dismissSuggestion() }
                    .buttonStyle(PadPillButton(filled: false))
            }
        }
        if timeline.isFriday, !settings.largeAndSimple {
            PadBanner(
                symbol: "sun.max",
                text: localized(
                    "ipad.heute.freitag \(Prayer.dhuhr.name(friday: true)) \(day[.dhuhr].timeText(tz))"))
        }
        if night, let end = timeline.lastThird {
            PadBanner(symbol: "moon", text: localized("vakit.gece.son_ucte_bir \(end.timeText(tz))"))
        }
        if let kandil = model.upcomingReligiousDay(today: today) {
            PadBanner(symbol: "sparkles", text: kandil.text(today: today))
        }
        if let k = timeline.karahat(time) {
            Button {
                karahatOpen = true
            } label: {
                PadBanner(
                    symbol: "bell", text: localized("kerahat.bant \(k.end.timeText(tz))"), warning: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint(localized("kerahat.nedir"))
        }
    }

    private func ramadanRow(_ g: DailyPrayerTimes, tz: TimeZone) -> some View {
        HStack(spacing: 14) {
            PadBanner(symbol: "moon", text: localized("ramazan.sahur"), value: g[.imsak].timeText(tz))
            PadBanner(
                symbol: "sun.horizon", text: localized("ramazan.iftar"), value: g[.maghrib].timeText(tz))
        }
    }
}

/// The date line with the Hijri date: the same text as on the iPhone page.
enum TodayDateLine {
    @MainActor static func text(_ g: DailyPrayerTimes, tz: TimeZone) -> String {
        var style = Date.FormatStyle(date: .complete, time: .omitted).year(.omitted)
        style.locale = AppLanguage.locale
        style.timeZone = tz
        let gregorian = g.day.start(tz).addingTimeInterval(12 * 3600).formatted(style)
        guard let h = g.hijri else { return gregorian }
        let month = localized(key: "hicri.ay.\(h.month)", fallback: h.monthName)
        let hijri =
            "\(h.day) \(month) \(h.year)"
            + (g.source == .diyanet || HijriDate.exact(g.day) ? "" : " (\(localized("vakit.yaklasik")))")
        return "\(gregorian) · \(hijri)"
    }
}

/// The countdown card (hero on board G01). The color follows the deadline of the current prayer, as on the
/// iPhone; the bar shows karahat hatched.
struct PadHero: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let status: PrayerTimeStatus
    let time: Date
    let tz: TimeZone
    let friday: Bool
    let ramadan: Bool
    let timeline: DayTimeline
    let tall: Bool
    var openKarahat: () -> Void = {}
    @State private var weekOpen = false

    var body: some View {
        let base = NextPrayerCard(
            status: status, time: time, tz: tz, friday: friday, ramadan: ramadan, timeline: timeline,
            openKarahat: openKarahat)
        let s = Counter(remaining: status.nextTime.timeIntervalSince(time))
        let r = Urgency.calculate(status, timeline: timeline, time: time)
        let (background, parent) = colors(r.level)
        let fridayNext = status.next == .dhuhr && friday
        let title = status.next.targetTitle(friday: fridayNext, ramadan: ramadan)
        let nameAndTime =
            "\(status.current.name(friday: status.current == .dhuhr && friday)) \(status.currentStart.timeText(tz))"
        let previous =
            NextPrayerCard.isYesterday(status.currentStart, time: time, tz: tz)
            ? localized("bugun.dun \(nameAndTime)") : nameAndTime
        let note = base.noteText(r)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(app: "ipad.heute.naechstes \(base.name(fridayNext))").typography(.label(size: 19))
                Spacer(minLength: 8)
                Text(verbatim: status.nextTime.timeText(tz)).typography(.display(size: 24)).monospacedDigit()
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(verbatim: s.text).typography(.display(size: tall ? 80 : 68)).monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
                Text(verbatim: s.secondsText).typography(.display(size: 30)).monospacedDigit().opacity(0.75)
                    .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: s.seconds)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.top, tall ? 18 : 14)
            .padding(.bottom, tall ? 20 : 16)
            if let note {
                noteRow(note, karahat: r.karahat != nil)
                    .padding(.bottom, 10)
            }
            base.strip(parent: parent).frame(height: 10)
            HStack(alignment: .center) {
                if !tall {
                    Text(verbatim: previous).typography(.label(size: 14)).opacity(0.92)
                }
                Spacer(minLength: 8)
                Button {
                    weekOpen = true
                } label: {
                    Text(app: "ipad.heute.sieben_tage").typography(.label(size: 15))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(parent.opacity(0.2), in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $weekOpen) { PadWeekPopover() }
            }
            .padding(.top, 8)
        }
        .foregroundStyle(parent)
        .padding(.horizontal, 30)
        .padding(.top, tall ? 26 : 22)
        .padding(.bottom, tall ? 16 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            background
                .overlay {
                    if r.level == .relaxed {
                        // The light of the board: a wide glow and the small sun next to the time.
                        GeometryReader { g in
                            RadialGradient(
                                colors: [.white.opacity(0.16), .clear], center: .center, startRadius: 0,
                                endRadius: 280
                            )
                            .frame(width: 560, height: 420)
                            .position(x: g.size.width - 180, y: 80)
                            RadialGradient(
                                colors: [PadColor.glowCore, PadColor.glowEdge.opacity(0)],
                                center: .center, startRadius: 0, endRadius: 48
                            )
                            .frame(width: 96, height: 96)
                            .position(x: g.size.width - 94, y: 74)
                        }
                    }
                }
                .accessibilityHidden(true)
        }
        .clipShape(.rect(cornerRadius: 34))
        .shadow(color: background.opacity(0.28), radius: 20, y: 18)
        .animation(.easeInOut(duration: 0.6), value: r.level)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title) \(s.spoken)")
    }

    private func noteRow(_ note: String, karahat: Bool) -> some View {
        let row = HStack(spacing: 4) {
            Text(verbatim: note)
            if karahat { Image(systemName: "info.circle").accessibilityHidden(true) }
        }
        .typography(.footnote)
        .fontWeight(.semibold)
        return Group {
            if karahat {
                Button(action: openKarahat) { row }.buttonStyle(.plain)
            } else {
                row
            }
        }
    }

    private func colors(_ level: Urgency.Level) -> (Color, Color) {
        switch level {
        // Dark: the deep tone of the palette with white on it (board G01: #9C3A25 for Seher), not the bright
        // accent, the largest area of the page must not glare at night.
        case .relaxed:
            theme.colors.dark
                ? (
                    PalettePicker.colors(settings.palette, dark: false).accent.mix(with: .black, by: 0.12),
                    .white
                )
                : (theme.colors.accent, theme.colors.onAccent)
        case .az: (theme.colors.warningBackground, theme.colors.warningText)
        case .karahat: (theme.colors.errorBackground, theme.colors.errorText)
        }
    }
}

/// The six times as cards with their bell, always 3 x 2.
struct PadTimeGrid: View {
    @Environment(\.theme) private var theme
    let day: DailyPrayerTimes
    let status: PrayerTimeStatus
    let tz: TimeZone
    let friday: Bool
    let tomorrow: Bool
    let tall: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if tomorrow {
                Text(app: "vakit.yarin.baslik").typography(.footnote).foregroundStyle(theme.colors.text2)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(Array(Prayer.allCases.enumerated()), id: \.element) { i, n in
                    cell(n).padEnter(delay: Double(i) * 0.07)
                }
            }
        }
    }

    private func cell(_ n: Prayer) -> some View {
        let now = !tomorrow && status.current == n && status.currentStart == day[n]
        let next = status.next == n && status.nextTime == day[n]
        return HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: tall ? 10 : 8) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(next ? theme.colors.accent : now ? theme.colors.sage : theme.colors.surface2)
                        .frame(width: 9, height: 9)
                        .accessibilityHidden(true)
                    Text(verbatim: n == .imsak ? localized("vakit.imsak.kisa") : n.name(friday: friday))
                        .typography(.label(size: 14)).foregroundStyle(theme.colors.text2)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                Text(verbatim: day[n].timeText(tz)).typography(.display(size: tall ? 32 : 28))
                    .monospacedDigit()
                    .foregroundStyle(theme.colors.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            PrayerBell(prayer: n)
        }
        .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, tall ? 10 : 8)
        .background(next ? theme.colors.surface2 : theme.colors.surface, in: .rect(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(next ? theme.colors.accent.opacity(0.5) : theme.colors.line)
        )
        .padShadow(theme)
        .accessibilityElement(children: .contain)
        .accessibilityValue(now ? localized("vakit.simdi") : next ? localized("vakit.siradaki") : "")
    }
}

/// „Für dich heute“ and „Weiterlesen“, in landscape next to each other, in portrait stacked; below them what
/// the iPhone page also has.
struct PadTodayCards: View {
    @Environment(Router.self) private var direction
    @Environment(\.contentProvider) private var contentProvider
    @Environment(UserStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(PrayerTimeModel.self) private var model
    @Environment(\.theme) private var theme
    let day: Day
    let tall: Bool
    @State private var page = 0

    private var lastPosition: ContentKey? {
        (store.lastPosition(khatm: settings.activeKhatm) ?? store.lastPosition()).flatMap {
            ContentKey(text: $0)
        }
    }

    var body: some View {
        let _ = store.version
        VStack(alignment: .leading, spacing: 14) {
            if tall {
                continueCard(compact: true)
                forYou
            } else {
                HStack(alignment: .top, spacing: 14) {
                    forYou.frame(maxWidth: .infinity)
                    continueCard(compact: false).frame(width: 316, height: forYouHeight)
                }
            }
            lowerFunctions
        }
    }

    private var forYouHeight: CGFloat { tall ? 250 : 250 }

    /// Vers des Tages and Frage des Tages, to be swiped.
    private var forYou: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(
                    verbatim:
                        "\(localized("ipad.heute.fuer_dich")) · \(localized(page == 0 ? "ipad.heute.vers" : "ipad.heute.frage"))"
                )
                .typography(.label(size: 13)).textCase(.uppercase).tracking(1.1)
                .foregroundStyle(theme.colors.label)
                Spacer(minLength: 8)
                Text(app: "ipad.heute.wischen").typography(.footnote).foregroundStyle(theme.colors.text2)
                    .accessibilityHidden(true)
            }
            TabView(selection: $page) {
                ScrollView { PadVerseOfTheDay(day: day, tall: tall) }.scrollIndicators(.hidden).tag(0)
                ScrollView { QuestionOfTheDayCard(day: day, optionColumns: 2, showsTitle: false) }
                    .scrollIndicators(.hidden).tag(1)
            }
            #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
            HStack(spacing: 0) {
                dot(0, label: "ipad.heute.vers")
                dot(1, label: "ipad.heute.frage")
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 4)
        .frame(height: forYouHeight)
        .padCard(theme)
        .padEnter()
    }

    private func dot(_ i: Int, label: String.LocalizationValue) -> some View {
        Button {
            withAnimation { page = i }
        } label: {
            Capsule()
                .fill(page == i ? theme.colors.accent : theme.colors.surface2)
                .frame(width: page == i ? 24 : 8, height: 8)
                .frame(width: 44, height: 30)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.4), value: page)
        .accessibilityLabel(localized(label))
    }

    private func continueCard(compact: Bool) -> some View {
        let goal = lastPosition ?? .verse(surah: 1, verse: 1)
        return Button {
            direction.open(.verse(goal), tabs: settings.tabs)
        } label: {
            HStack(spacing: 14) {
                if compact {
                    Image(systemName: "book").font(.system(size: 20)).foregroundStyle(theme.colors.accent)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: compact ? 5 : 6) {
                    Text(app: "kuran.kaldigin_yer").typography(.label(size: 13)).textCase(.uppercase)
                        .tracking(1.1)
                        .foregroundStyle(theme.colors.label)
                    if let contentProvider, case .verse(let s, let n) = goal,
                        let surah = contentProvider.surah(s)
                    {
                        Text(app: "kuran.kaldigin.ayet \(surah.name(language: translationLanguage())) \(n)")
                            .typography(.label(size: compact ? 18 : 20)).foregroundStyle(theme.colors.text)
                        if !compact, let page = contentProvider.verse(goal)?.page {
                            Text(app: "ipad.heute.seite \(page)").typography(.secondary)
                                .foregroundStyle(theme.colors.text2)
                        }
                    }
                }
                Spacer(minLength: 4)
                if compact {
                    Image(systemName: "chevron.right").foregroundStyle(theme.colors.text2)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, compact ? 24 : 22).padding(.vertical, 18)
            .frame(maxWidth: .infinity, maxHeight: compact ? nil : .infinity, alignment: .leading)
            .padCard(theme)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padEnter(delay: 0.1)
    }

    /// Below the first screen: daily points, reading week, all times and source. Nothing is lost from the iPhone.
    @ViewBuilder
    private var lowerFunctions: some View {
        TodayCardsPoints(page: $page)
        WeekReading(reading: store.weeklyReading())
        if let table = model.table,
            let entry = table.day(Day(.now, timeZoneIdentifier: table.location.timeZone))
        {
            PadTodayFoot(table: table, day: entry, today: entry.day)
        }
    }
}

/// The links to all times and the seven-day view, and where the times come from.
struct PadTodayFoot: View {
    @Environment(\.theme) private var theme
    let table: PrayerTimeTable
    let day: DailyPrayerTimes
    let today: Day

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
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
            Spacer(minLength: 8)
            Label {
                Text(
                    verbatim: day.source == .diyanet
                        ? localized("vakit.kaynak.diyanet \(table.location.name)")
                        : localized("vakit.kaynak.hesaplanan \(table.location.name)"))
            } icon: {
                Image(systemName: day.source == .diyanet ? "checkmark.seal" : "clock")
            }
            .typography(.footnote).foregroundStyle(theme.colors.text2)
        }
    }
}

/// Verse of the day inside the low card: Arabic right, translation and source below it, share in the corner.
struct PadVerseOfTheDay: View {
    @Environment(Router.self) private var direction
    @Environment(AppSettings.self) private var settings
    @Environment(\.contentProvider) private var contentProvider
    @Environment(\.theme) private var theme
    let day: Day
    let tall: Bool

    var body: some View {
        let a = VerseOfTheDay.key(day)
        if let contentProvider, case .verse(let s, let n) = a, let surah = contentProvider.surah(s),
            let verse = contentProvider.verse(a)
        {
            let pack = contentProvider.translations(language: translationLanguage()).first
            let translation = pack.flatMap { contentProvider.translation(a, pack: $0.id) }?.text ?? ""
            let surahName = surah.name(language: translationLanguage())
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    direction.open(.verse(a), tabs: settings.tabs)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: verse.text)
                            .typography(
                                .arabic(size: verse.text.count > 120 ? (tall ? 28 : 23) : (tall ? 34 : 28))
                            )
                            .foregroundStyle(theme.colors.text)
                            .multilineTextAlignment(.trailing)
                            // Quran text is never cut off with an ellipsis.
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text(verbatim: translation).typography(.secondary).fontWeight(.medium)
                            .foregroundStyle(theme.colors.text2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint(localized("bugun.ayet.ac"))
                HStack {
                    Text(verbatim: "\(surahName) \(s):\(n)").typography(.footnote).foregroundStyle(
                        theme.colors.text2)
                    Spacer(minLength: 8)
                    ShareButton(
                        .verse(
                            arabic: verse.text, translation: translation,
                            source: "\(surahName) \(s):\(n) · \(pack?.title ?? "")",
                            surah: s, verse: n, parent: localized("gunun_ayeti \(surahName) \(n)"))
                    )
                    .frame(minWidth: 44, minHeight: 44)
                }
            }
        }
    }
}

/// A row above or below the hero (board G03).
struct PadBanner<Actions: View>: View {
    @Environment(\.theme) private var theme
    let symbol: String
    let text: String
    var value: String? = nil
    var warning = false
    @ViewBuilder var actions: () -> Actions

    init(
        symbol: String, text: String, value: String? = nil, warning: Bool = false,
        @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.symbol = symbol
        self.text = text
        self.value = value
        self.warning = warning
        self.actions = actions
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 19)).accessibilityHidden(true)
            HStack(spacing: 8) {
                Text(verbatim: text).typography(.label(size: 16))
                if let value {
                    Text(verbatim: value).typography(.display(size: 18)).monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            actions()
        }
        .foregroundStyle(warning ? theme.colors.warningText : theme.colors.text)
        .padding(.horizontal, 20).padding(.vertical, 14)
        .frame(minHeight: 50)
        .background(
            warning ? theme.colors.warningBackground : theme.colors.surface2, in: .rect(cornerRadius: 20)
        )
        .overlay {
            if warning {
                RoundedRectangle(cornerRadius: 20).strokeBorder(theme.colors.warningText, lineWidth: 1.5)
            }
        }
    }
}

extension PadBanner where Actions == EmptyView {
    init(symbol: String, text: String, value: String? = nil, warning: Bool = false) {
        self.init(symbol: symbol, text: text, value: value, warning: warning) { EmptyView() }
    }
}

/// The 44 pt buttons of the iPad boards.
struct PadPillButton: ButtonStyle {
    @Environment(\.theme) private var theme
    let filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .typography(.label(size: 15))
            .foregroundStyle(filled ? theme.colors.onAccent : theme.colors.text)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(filled ? theme.colors.accent : theme.colors.surface2, in: .capsule)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(.capsule)
    }
}

/// „Büyük ve sade“ (board G03): large rows only. Without seconds, as on the iPhone: the flicker
/// every second is restlessness for those who chose this mode.
struct PadSimpleList: View {
    @Environment(\.theme) private var theme
    let status: PrayerTimeStatus
    let time: Date
    let day: DailyPrayerTimes
    let tz: TimeZone
    let friday: Bool
    let ramadan: Bool
    let tomorrow: Bool

    init(
        status: PrayerTimeStatus, day: DailyPrayerTimes, time: Date, tz: TimeZone, friday: Bool,
        ramadan: Bool,
        tomorrow: Bool
    ) {
        self.status = status
        self.day = day
        self.time = time
        self.tz = tz
        self.friday = friday
        self.ramadan = ramadan
        self.tomorrow = tomorrow
    }

    var body: some View {
        let s = Counter(remaining: (status.nextTime.timeIntervalSince(time) / 60).rounded(.up) * 60)
        VStack(spacing: 10) {
            row(
                name: status.next.targetTitle(friday: status.next == .dhuhr && friday, ramadan: ramadan),
                value: s.text, highlight: true
            )
            .accessibilityLabel("\(status.next.targetTitle(friday: friday, ramadan: ramadan)) \(s.spoken)")
            if tomorrow {
                Text(app: "vakit.yarin.baslik").typography(.footnote).foregroundStyle(theme.colors.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(Prayer.allCases, id: \.self) { n in
                row(
                    name: n.name(friday: friday), value: day[n].timeText(tz),
                    highlight: false, next: status.next == n && status.nextTime == day[n])
            }
        }
    }

    private func row(name: String, value: String, highlight: Bool, next: Bool = false) -> some View {
        HStack {
            Text(verbatim: name).typography(.label(size: 30)).lineLimit(1).minimumScaleFactor(0.6)
            Spacer(minLength: 12)
            Text(verbatim: value).typography(.display(size: 44)).monospacedDigit().lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(highlight ? theme.colors.onAccent : next ? theme.colors.accent : theme.colors.text)
        .padding(.horizontal, 26)
        .frame(minHeight: 76)
        .background(
            highlight ? theme.colors.accent : next ? theme.colors.surface2 : theme.colors.surface,
            in: .rect(cornerRadius: 24)
        )
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(highlight ? .clear : theme.colors.line))
        .accessibilityElement(children: .combine)
    }
}

/// Without a location: why, and the two ways to one (board G03).
struct PadNoLocation: View {
    @Environment(PrayerTimeModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var open
    let searchCity: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "mappin.and.ellipse").font(.system(size: 40)).foregroundStyle(
                    theme.colors.accent
                )
                .accessibilityHidden(true)
                Text(app: "konum.yok.baslik").typography(.display(size: 34))
                Text(app: model.noLocationPermission ? "konum.yok.izin_yok" : "konum.yok.aciklama")
                    .typography(.body).foregroundStyle(theme.colors.text2)
                    .frame(maxWidth: 560, alignment: .leading)
                HStack(spacing: 10) {
                    if model.noLocationPermission {
                        Button(localized("konum.izin_ac")) {
                            if let url = URL(string: "app-settings:") { open(url) }
                        }
                        .buttonStyle(PadPillButton(filled: true))
                    } else {
                        Button(localized("konum.kullan")) {
                            Task { await model.checkLocation(settings) }
                        }
                        .buttonStyle(PadPillButton(filled: true))
                    }
                    Button(localized("konum.sehir_ara"), action: searchCity)
                        .buttonStyle(PadPillButton(filled: false))
                }
                Text(app: "konum.gizlilik").typography(.footnote).foregroundStyle(theme.colors.text2)
            }
            .padding(40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padCard(theme)
            .padding(.horizontal, 28)
            .padding(.top, 24)
        }
    }
}

/// While the times load: the shape of the page, still with „reduce motion“.
struct PadTodayLoading: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 18) {
                bar(width: 0.55, height: 20)
                bar(width: 0.78, height: 70)
                bar(width: 0.94, height: 12)
            }
            .padding(.horizontal, 32).padding(.vertical, 26)
            .padCard(theme)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(0..<6, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 22).fill(theme.colors.surface).frame(height: 76)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .accessibilityLabel(localized("ipad.heute.laedt"))
    }

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        GeometryReader { g in
            RoundedRectangle(cornerRadius: height / 3).fill(theme.colors.surface2)
                .frame(width: g.size.width * width)
        }
        .frame(height: height)
    }
}

/// „Sieben Tage“ from the hero: five prayers, seven days, in one view (board G01).
struct PadWeekPopover: View {
    @Environment(PrayerTimeModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var direction
    @Environment(AppSettings.self) private var settings

    private static let shown: [Prayer] = [.imsak, .dhuhr, .asr, .maghrib, .isha]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(app: "ipad.heute.sieben_tage").typography(.label(size: 13)).textCase(.uppercase).tracking(
                1.1
            )
            .foregroundStyle(theme.colors.label)
            .padding(.bottom, 6)
            if let t = model.table {
                let tz = t.location.timeZone
                let today = Day(.now, timeZoneIdentifier: tz)
                Grid(alignment: .trailing, horizontalSpacing: 18, verticalSpacing: 2) {
                    GridRow {
                        Text(app: "ipad.heute.tag").gridColumnAlignment(.leading)
                        ForEach(Self.shown, id: \.self) { n in
                            Text(verbatim: n == .imsak ? localized("vakit.imsak.kisa") : n.name())
                        }
                    }
                    .typography(.label(size: 12)).foregroundStyle(theme.colors.label)
                    ForEach(0..<7, id: \.self) { i in
                        if let g = t.day(today.added(i)) {
                            GridRow {
                                Text(verbatim: dayName(g, tz: tz)).gridColumnAlignment(.leading)
                                ForEach(Self.shown, id: \.self) { n in
                                    Text(verbatim: g[n].timeText(tz)).monospacedDigit()
                                }
                            }
                            .font(.custom("Plus Jakarta Sans", size: 15).weight(i == 0 ? .semibold : .medium))
                            .foregroundStyle(i == 0 ? theme.colors.text : theme.colors.text2)
                            .padding(.vertical, 5)
                            .background(i == 0 ? theme.colors.surface2 : .clear, in: .rect(cornerRadius: 12))
                        }
                    }
                }
            }
            Button {
                dismiss()
                direction.open(.allPrayerTimes, tabs: settings.tabs)
            } label: {
                Label {
                    Text(app: "vakit.tum_vakitler")
                } icon: {
                    Image(systemName: "chevron.right")
                }
                .labelStyle(TrailingIcon())
                .typography(.emphasized).foregroundStyle(theme.colors.accent)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(20)
        .frame(minWidth: 560)
        .presentationCompactAdaptation(.popover)
    }

    private func dayName(_ g: DailyPrayerTimes, tz: TimeZone) -> String {
        var style = Date.FormatStyle().weekday(.abbreviated).day().month(.twoDigits)
        style.locale = AppLanguage.locale
        style.timeZone = tz
        return g.day.start(tz).addingTimeInterval(12 * 3600).formatted(style)
    }
}
