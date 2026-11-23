/// Areas that are built but currently belong in the backlog: code and tests stay,
/// only the entry points are closed.
///
/// Namaz-Rehber: no entry in Keşfet, `kiblegah://guide`
/// opens Keşfet. To bring it back, set the switch to `true`; `GuideScreen` and
/// `GuideStepScreen` remain attached to `Goal.guide`.
enum Backlog {
    static let prayerGuide = false
}
