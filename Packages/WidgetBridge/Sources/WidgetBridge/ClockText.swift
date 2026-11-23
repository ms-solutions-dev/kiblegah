import Foundation

extension Date {
    /// A prayer time as a clock time in the time zone of the place, not of the device:
    /// „15:42“ in 24-hour locales, „3:42 PM“ in 12-hour locales. The AM/PM marker is never dropped,
    /// otherwise „Asr 03:42“ reads like a time in the morning.
    ///
    /// Shared by the app, the widgets, the Live Activity, the watch app and its complications.
    public func clockText(in timeZone: TimeZone, locale: Locale = .autoupdatingCurrent) -> String {
        formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone))
    }
}
