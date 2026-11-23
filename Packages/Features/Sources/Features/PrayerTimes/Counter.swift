import Core
import DesignSystem
import Foundation
import PrayerTimes
import WidgetBridge

/// Countdown building blocks: „5 sa 13 dk 07 sn“ visible, VoiceOver only hours and minutes.
struct Counter: Equatable {
    let time: Int
    let minutes: Int
    let seconds: Int

    init(remaining: TimeInterval) {
        let total = max(0, Int(remaining.rounded(.down)))
        time = total / 3600
        minutes = total % 3600 / 60
        seconds = total % 60
    }

    /// „5 sa 13 dk“ without seconds - the view sets the seconds smaller next to it.
    var text: String {
        time > 0 ? localized("sayac.sa_dk \(time) \(minutes)") : localized("sayac.dk \(minutes)")
    }

    var secondsText: String { localized("sayac.sn \(String(format: "%02d", seconds))") }

    /// For VoiceOver: full words, rounded up to the minute, so that „0 Minuten“ never occurs.
    var spoken: String {
        let dk = time * 60 + minutes + (seconds > 0 ? 1 : 0)
        let s = dk / 60
        let d = dk % 60
        if s > 0 && d > 0 { return localized("sayac.sesli.sa_dk \(s) \(d)") }
        if s > 0 { return localized("sayac.sesli.sa \(s)") }
        return localized("sayac.sesli.dk \(max(d, 1))")
    }
}

extension Prayer {
    /// Display name; on Fridays Dhuhr is called „Cuma“.
    func name(friday: Bool = false) -> String {
        switch self {
        case .imsak: localized("vakit.imsak")
        case .sunrise: localized("vakit.gunes")
        case .dhuhr: friday ? localized("vakit.cuma") : localized("vakit.ogle")
        case .asr: localized("vakit.ikindi")
        case .maghrib: localized("vakit.aksam")
        case .isha: localized("vakit.yatsi")
        }
    }

    /// The head of the countdown („Öğle'ye“ / „bis Mittag“ / „until Dhuhr“) with placeholder.
    func targetTitle(friday: Bool, ramadan: Bool) -> String {
        if ramadan && self == .maghrib { return localized("vakit.hedef.iftar") }
        if ramadan && self == .imsak { return localized("vakit.hedef.sahur") }
        switch self {
        case .imsak: return localized("vakit.hedef.imsak")
        case .sunrise: return localized("vakit.hedef.gunes")
        case .dhuhr: return friday ? localized("vakit.hedef.cuma") : localized("vakit.hedef.ogle")
        case .asr: return localized("vakit.hedef.ikindi")
        case .maghrib: return localized("vakit.hedef.aksam")
        case .isha: return localized("vakit.hedef.yatsi")
        }
    }
}

extension Date {
    /// „13:06“ (or „1:06 PM“ with a 12-hour clock) in the time zone of the place, not of the device.
    func timeText(_ tz: TimeZone) -> String {
        clockText(in: tz, locale: AppLanguage.clockLocale)
    }
}
