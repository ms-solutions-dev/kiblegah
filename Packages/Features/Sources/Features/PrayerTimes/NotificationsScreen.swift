import Core
import DesignSystem
import PrayerTimes
import SwiftUI
import UserData
import UserNotifications

/// Bildirimler: one row per prayer time with switch and „önceden“ menu
///, honest „X tarihine kadar planlı“, sound and full adhan via AlarmKit.
struct NotificationsScreen: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PrayerTimeModel.self) private var prayerTimes
    @Environment(NotificationManager.self) private var notification
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var open
    @State private var setting: [Prayer: NotificationSetting] = [:]

    var body: some View {
        List {
            Section {
                status
            }
            // Without permission the switches do not look „on“ although nothing can arrive.
            Section {
                ForEach(Prayer.allCases, id: \.self) { n in
                    row(n)
                }
            } footer: {
                Text(app: "bildirim.ozet.alt")
            }
            .disabled(!hasPermission)
            Section {
                Toggle(isOn: karahatBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app: "bildirim.kerahat")
                        Text(app: "bildirim.kerahat.alt").typography(.footnote).foregroundStyle(
                            theme.colors.text2)
                    }
                }
                .disabled(!hasPermission)
            }
            Section {
                Toggle(isOn: liveBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app: "bildirim.canli")
                        Text(app: "bildirim.canli.alt").typography(.footnote).foregroundStyle(
                            theme.colors.text2)
                    }
                }
            }
            Section {
                Picker(localized("bildirim.ses"), selection: soundBinding) {
                    Text(app: "bildirim.ses.varsayilan").tag("varsayilan")
                    Text(app: "bildirim.ses.kisa_ezan").tag("kisaEzan")
                }
            } header: {
                Text(app: "bildirim.ses")
            }
            #if os(iOS)
                Section {
                    if notification.alarmPermission {
                        ForEach(Prayer.allCases.filter(\.isPrayer), id: \.self) { n in
                            Toggle(isOn: binding(n, \.fullAdhan)) { Text(verbatim: n.name()) }
                        }
                    } else {
                        Button(localized("bildirim.tam_ezan.izin")) {
                            Task { await notification.requestAlarmPermission() }
                        }
                    }
                } header: {
                    Text(app: "bildirim.tam_ezan")
                } footer: {
                    Text(app: "bildirim.tam_ezan.alt")
                }
            #endif
        }
        .pageBackground()
        .navigationTitle(localized("bildirim.baslik"))
        .smallTitle()
        .task {
            setting = NotificationManager.settings(settings)
            await notification.readPermissionStatus()
        }
        .onChange(of: setting) { _, yeni in
            NotificationManager.save(yeni, settings)
            Task { await notification.schedule(table: prayerTimes.table, settings: settings) }
        }
    }

    private var hasPermission: Bool {
        switch notification.allowed {
        case .denied, .notDetermined: false
        default: true
        }
    }

    @ViewBuilder private var status: some View {
        switch notification.allowed {
        case .denied:
            VStack(alignment: .leading, spacing: 8) {
                Text(app: "bildirim.izin_yok").typography(.body)
                Button(localized("bildirim.ayarlari_ac")) {
                    if let url = URL(string: "app-settings:") { open(url) }
                }
            }
        case .notDetermined:
            VStack(alignment: .leading, spacing: 8) {
                Text(app: "bildirim.izin_sor").typography(.body)
                Button(localized("bildirim.izin_ver")) {
                    Task {
                        await notification.requestPermission()
                        await notification.schedule(table: prayerTimes.table, settings: settings)
                    }
                }
                .buttonStyle(PrimaryButton())
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                if let end = notification.lastDay, let tz = prayerTimes.table?.location.timeZone {
                    Text(app: "bildirim.planli \(date(end, tz))").typography(.emphasized)
                } else {
                    Text(app: "bildirim.plan_yok").typography(.emphasized)
                }
                Text(app: "bildirim.planli.alt").typography(.footnote).foregroundStyle(theme.colors.text2)
            }
        }
    }

    private func row(_ n: Prayer) -> some View {
        let a = setting[n] ?? .standard(n)
        let time = prayerTimes.table.flatMap { t in
            t.day(Day(.now, timeZoneIdentifier: t.location.timeZone)).map {
                $0[n].timeText(t.location.timeZone)
            }
        }
        return VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: binding(n, \.atTime)) {
                HStack {
                    Text(verbatim: n.name())
                    if let time {
                        Text(verbatim: time).foregroundStyle(theme.colors.text2).monospacedDigit()
                    }
                }
            }
            .accessibilityLabel(localized("bildirim.vaktinde.etiket \(n.name())"))
            Picker(localized("bildirim.onceden.kisa"), selection: binding(n, \.minutesBefore)) {
                ForEach(NotificationSetting.minutesBeforeOptions, id: \.self) { dk in
                    if dk == 0 {
                        Text(app: "bildirim.onceden.yok").tag(0)
                    } else {
                        Text(app: "bildirim.dk \(dk)").tag(dk)
                    }
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel(localized("bildirim.onceden.etiket \(n.name())"))
            Text(verbatim: summary(n, a)).typography(.footnote).foregroundStyle(theme.colors.text2)
        }
        .padding(.vertical, 4)
    }

    /// Plain text instead of symbols: „Vaktinde ve 15 dk önce“.
    private func summary(_ n: Prayer, _ a: NotificationSetting) -> String {
        switch (a.atTime, a.minutesBefore) {
        case (true, 0): localized("bildirim.ozet.vaktinde")
        case (true, let dk): localized("bildirim.ozet.ikisi \(dk)")
        case (false, 0): localized("bildirim.ozet.kapali")
        case (false, let dk): localized("bildirim.ozet.onceden \(dk)")
        }
    }

    private func binding<T>(_ n: Prayer, _ path: WritableKeyPath<NotificationSetting, T>) -> Binding<T> {
        Binding(
            get: { (setting[n] ?? .standard(n))[keyPath: path] },
            set: { yeni in
                var a = setting[n] ?? .standard(n)
                a[keyPath: path] = yeni
                setting[n] = a
            })
    }

    private var liveBinding: Binding<Bool> {
        Binding(
            get: { settings.liveActivity },
            set: { yeni in
                settings.liveActivity = yeni
                if let t = prayerTimes.table { WidgetWriter.save(t, settings: settings) }
            })
    }

    private var karahatBinding: Binding<Bool> {
        Binding(
            get: { settings.karahatReminder },
            set: { yeni in
                settings.karahatReminder = yeni
                Task { await notification.schedule(table: prayerTimes.table, settings: settings) }
            })
    }

    private var soundBinding: Binding<String> {
        Binding(
            get: { settings.notificationSound },
            set: { yeni in
                settings.notificationSound = yeni
                Task { await notification.schedule(table: prayerTimes.table, settings: settings) }
            })
    }

    private func date(_ g: Day, _ tz: TimeZone) -> String {
        var s = Date.FormatStyle(date: .long, time: .omitted).year(.omitted)
        s.locale = AppLanguage.locale
        s.timeZone = tz
        return g.start(tz).addingTimeInterval(12 * 3600).formatted(s)
    }
}
