# Architecture

Kıblegâh is a SwiftUI app for iOS 26 and watchOS 26, written in Swift 6 with strict concurrency. The Xcode project is generated from `project.yml` by XcodeGen. Almost all code lives in local Swift packages; the app target only wires them together.

## Targets

| Target | Purpose |
|---|---|
| `Kiblegah` | The iPhone app (`App/Sources/KiblegahApp.swift`: settings, router, stores, background refresh) |
| `KiblegahWidget` | Home and lock screen widgets, the Live Activity for the next prayer and the qibla control |
| `KiblegahWatch`, `KiblegahWatchWidget` | Watch app and complications; they show the snapshot the iPhone sends over WatchConnectivity |

## Packages

Dependencies point downwards only.

```
Features ──► PrayerTimes, Qibla, Quran, Duas, UserData, ContentPacks, DesignSystem, WidgetBridge
Quran, Duas ──► ContentPacks ──► Core
PrayerTimes, Qibla, UserData, DesignSystem ──► Core
WidgetBridge (no dependencies; shared with the widget and watch targets)
```

| Package | Contents |
|---|---|
| `Core` | Content keys, app group defaults, feature flags, relay address, small shared helpers |
| `DesignSystem` | Theme (palettes, light/dark, night mode, large-and-simple mode), typography and bundled fonts, shared components |
| `ContentPacks` | Reads the content packs (`manifest.json` + SQLite) through `PackRegistry`: Quran text, translations, tafsir, hadith, names of Allah, full-text and semantic search, question of the day |
| `PrayerTimes` | On-device prayer time calculation (Diyanet method), sources and stock of times, Hijri calendar and religious days, notification planning within iOS's limit of 64 pending notifications |
| `Qibla` | Qibla bearing, compass smoothing and drawing |
| `Quran` | Reciters, audio download and playback, word-by-word data and timings |
| `Duas` | Supplications built on the Quran packs, dhikr and the step-by-step prayer guide |
| `UserData` | SwiftData models for bookmarks, notes, reading goals, memorization, daily points and quiz history (including the CloudKit duel room); optional iCloud sync; app settings |
| `Features` | All screens and navigation: Today, Quran (reader and mushaf), Qibla, Discover (duas, dhikr, names of Allah, hadith, search), Quiz, Settings, sharing; the plugin entry points (`Plugins.swift`) where other app targets can add screens |
| `WidgetBridge` | The snapshot format the app writes into the app group and the widgets and watch read |

Each package has its own tests (`swift test --package-path Packages/<Name>`). `GoldenHelpers.swift` in several test targets pins persisted formats (stored keys, JSON written to disk or to the app group) with golden round-trip tests, so a refactoring cannot silently break data on users' devices.

## Content packs

The app has no built-in religious texts. A content pack is a folder `App/Resources/Paketler/<id>/` with `manifest.json` (id, kind, language, source, license, text version) and `veri.sqlite`. `tools/content/fetch.sh` downloads the original sources and builds the packs; `tools/content/denetle.py` checks them (counts, text version, license flags). The folder is copied into the app bundle as a folder reference. Missing packs are not an error: the affected areas show an empty state, and prayer times, qibla and everything else keep working. See [CONTENT.md](CONTENT.md) for sources and terms.

Packs that depend on the exact Quran text (tajweed spans, word boundaries, transliteration) record the text version (`textstand`), and the checker refuses mismatches.

## Prayer times and notifications

`PrayerTimeModel` (Features) keeps a stock of upcoming days computed by `PrayerTimeCalculator`, writes the snapshot for widgets and the watch, and re-plans notifications whenever the app becomes active or a background refresh runs. Users may also enter the address of their own prayer time server; then times come from there and the device calculation is the fallback. The full adhan can be scheduled as an alarm through AlarmKit.

## Relay

Some Quran Foundation endpoints need OAuth client credentials, which must not ship in an app. `relay/` is a small Cloudflare Worker that holds them and proxies mushaf page layouts. Its host is a build setting (`RELAY_HOST`); without it the mushaf view falls back to the reflowed text. The page fonts are loaded from the Quran Foundation's font server; nothing of the mushaf is bundled.

## Localization

User-facing text lives in `App/Resources/Localizable.xcstrings` (Turkish, German, English) and `InfoPlist.xcstrings`. Keys are English or Turkish identifiers; many type and property names are Turkish terms of the domain (vakit, kıble, meal, tefsir) on purpose.
