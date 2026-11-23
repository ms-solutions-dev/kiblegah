#!/bin/bash
# Regenerates the README screenshots in docs/screenshots (next to this tools/ folder) on the
# iOS simulator. No taps: every screen is opened through launch arguments.
#
#   tools/screenshots.sh [name ...]    all screenshots, or only the named ones (e.g. 02-quran)
#
# Before running (macOS with Xcode):
#   1. Build the `Kiblegah` scheme for the simulator, Debug, into the derived data folder the script
#      reads (default: build/ at the repository root, override with DERIVED_DATA):
#        xcodegen generate
#        xcodebuild -scheme Kiblegah -configuration Debug -destination 'generic/platform=iOS Simulator' \
#            -derivedDataPath build build
#      This also builds the embedded watch app (Debug-watchsimulator). The content packs must be built (tools/content/fetch.sh), otherwise Quran and Discover are empty.
#   2. 07-mushaf needs a relay: the page layout only comes through it (RELAY_HOST in
#      Config/Local.xcconfig, see relay/README.md). Without one the shot shows the reflowed text.
#
# Simulators: "Kiblegah iPhone" (PHONE_TYPE, default iPhone 18 Pro) and "Kiblegah Watch"
# (WATCH_TYPE, default Apple Watch Series 12 (46mm)) are created on first use. Location: the DITIB
# Central Mosque in Cologne (CET like a host in Germany, so every clock agrees).
#
# Launch arguments used (DEBUG builds only, see App/Sources/KiblegahApp.swift):
#   -ayar.ilkAcilis YES       skip onboarding        -ornekVeri YES    demo reading/dhikr history
#   -ayar.dil en|tr           app language           -ayar.gorunum acik|koyu   light/dark
#   -ayar.palet seher|zumrut  color palette          -ayar.buyukVeSade YES|NO  large and simple mode
#   -ayar.mushafFassung v1    mushaf edition         -kibleGorunum harita      qibla on the map
#   -acilis kiblegah://…      screen to open (bugun, kuran/36:1, kuran/sayfa/3, kible, kesfet,
#                             takvim, arama?q=…)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null || dirname "$HERE")"
OUT="$(cd "$HERE/.." && pwd)/docs/screenshots"
RAW="$(mktemp -d)"
trap 'rm -rf "$RAW"' EXIT
mkdir -p "$OUT"
DD="${DERIVED_DATA:-$REPO/build}/Build/Products"
BID=dev.ms-solutions.kiblegah
WBID=dev.ms-solutions.kiblegah.watchkitapp
GROUP=group.dev.ms-solutions.kiblegah
# DITIB Central Mosque, Venloer Str. 160, Cologne-Ehrenfeld (OpenStreetMap way 151467218). The qibla
# map shows the surroundings in 3D: no church or other religious building may sit in the qibla circle.
LAT=50.9457534 LON=6.9283936

[ -d "$DD/Debug-iphonesimulator/Kiblegah.app" ] || { echo "Kiblegah.app missing in $DD (see the header)"; exit 1; }

udid() { xcrun simctl list devices | grep "$1 (" | grep -oE "[0-9A-F-]{36}" | head -1; }
PHONE=$(udid "Kiblegah iPhone")
[ -z "$PHONE" ] && PHONE=$(xcrun simctl create "Kiblegah iPhone" "${PHONE_TYPE:-iPhone 18 Pro}")
WATCH=$(udid "Kiblegah Watch")
[ -z "$WATCH" ] && WATCH=$(xcrun simctl create "Kiblegah Watch" "${WATCH_TYPE:-Apple Watch Series 12 (46mm)}")

xcrun simctl boot "$PHONE" 2>/dev/null; xcrun simctl bootstatus "$PHONE" -b >/dev/null
# Fresh install: a stored place or history from an earlier run would otherwise win over LAT/LON.
xcrun simctl uninstall "$PHONE" "$BID" 2>/dev/null
xcrun simctl install "$PHONE" "$DD/Debug-iphonesimulator/Kiblegah.app"
xcrun simctl privacy "$PHONE" grant location "$BID" 2>/dev/null
xcrun simctl location "$PHONE" set "$LAT,$LON"

bar() {
    xcrun simctl status_bar "$1" override --time "$(date +%H:%M)" --dataNetwork wifi --wifiMode active \
        --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 2>/dev/null
}

EN=(-ayar.dil en -AppleLanguages "(en)" -AppleLocale en_US)
TR=(-ayar.dil tr -AppleLanguages "(tr)" -AppleLocale tr_TR)

launch() {  # wait, args...
    local wait=$1; shift
    xcrun simctl terminate "$PHONE" "$BID" 2>/dev/null
    xcrun simctl launch "$PHONE" "$BID" -ayar.ilkAcilis YES -ornekVeri YES "$@" >/dev/null
    sleep "$wait"
}

shot() {  # name, wait, args...
    local name=$1 wait=$2; shift 2
    if [ "${#WANT[@]}" -gt 0 ] && [[ ! " ${WANT[*]} " =~ " $name " ]]; then return; fi
    launch "$wait" "$@"
    bar "$PHONE"; sleep 1
    xcrun simctl io "$PHONE" screenshot "$RAW/$name.png" >/dev/null 2>&1
    cp "$RAW/$name.png" "$OUT/$name.png"
    sips -Z 1300 "$OUT/$name.png" >/dev/null
    echo "$name"
}

WANT=("$@")
LIGHT=(-ayar.gorunum acik -ayar.palet seher -ayar.buyukVeSade NO)
DARK=(-ayar.gorunum koyu -ayar.palet seher -ayar.buyukVeSade NO)

# Warm-up: location, reverse geocoding, prewarm of the caches.
launch 25 "${EN[@]}" "${LIGHT[@]}" -acilis kiblegah://bugun

shot 01-today 8 "${EN[@]}" "${LIGHT[@]}" -acilis kiblegah://bugun
shot 02-quran 8 "${EN[@]}" "${LIGHT[@]}" -acilis kiblegah://kuran/36:1
shot 03-qibla 12 "${EN[@]}" "${LIGHT[@]}" -acilis kiblegah://kible -kibleGorunum harita
shot 04-today-dark 8 "${EN[@]}" "${DARK[@]}" -acilis kiblegah://bugun
shot 05-quran-dark 8 "${EN[@]}" "${DARK[@]}" -acilis kiblegah://kuran/36:1
shot 06-discover-dark 8 "${EN[@]}" "${DARK[@]}" -acilis kiblegah://kesfet
shot 07-mushaf 15 "${EN[@]}" "${LIGHT[@]}" -ayar.mushafFassung v1 -acilis kiblegah://kuran/sayfa/3
shot 08-search 10 "${EN[@]}" "${LIGHT[@]}" -acilis "kiblegah://arama?q=patience"
shot 09-calendar 8 "${EN[@]}" "${LIGHT[@]}" -acilis kiblegah://takvim
shot 10-palette 8 "${EN[@]}" -ayar.gorunum acik -ayar.palet zumrut -ayar.buyukVeSade NO -acilis kiblegah://bugun
shot 11-large-simple 8 "${EN[@]}" -ayar.gorunum acik -ayar.palet seher -ayar.buyukVeSade YES -acilis kiblegah://bugun
shot tr-01-today 8 "${TR[@]}" "${LIGHT[@]}" -acilis kiblegah://bugun
shot tr-02-quran 8 "${TR[@]}" "${LIGHT[@]}" -acilis kiblegah://kuran/36:1
shot tr-03-discover 8 "${TR[@]}" "${LIGHT[@]}" -acilis kiblegah://kesfet

# Watch: the app shows the snapshot the iPhone wrote (English, written by the last English launch);
# the reading complication reads the reading snapshot (demo data) from the App Group.
#   watch-01  the app: next prayer and today's times
#   watch-02  the app: Qibla page (-saatEkran kible; the simulator has no compass, so the arrow
#             stays dimmed and the sun hint shows, as on a watch without a compass reading)
#   watch-03  complications, rectangular: next prayer, day bar
#   watch-04  complications, circular: next prayer, Qibla, Quran daily goal
# 03/04 are the complication views of the widget extension rendered by the watch app
# (-saatEkran komplikasyon1|2, Watch/Sources/ComplicationGallery.swift): a watch face with
# complications cannot be set up from the command line.
WATCH_SHOTS=(watch-01 watch-02 watch-03 watch-04)
want_watch() {
    [ "${#WANT[@]}" -eq 0 ] && return 0
    local w; for w in "${WATCH_SHOTS[@]}"; do [[ " ${WANT[*]} " =~ " $w " ]] && return 0; done
    return 1
}
wshot() {  # name, args...
    local name=$1; shift
    if [ "${#WANT[@]}" -gt 0 ] && [[ ! " ${WANT[*]} " =~ " $name " ]]; then return; fi
    xcrun simctl terminate "$WATCH" "$WBID" 2>/dev/null
    xcrun simctl launch "$WATCH" "$WBID" -AppleLanguages "(en)" -AppleLocale en_US "$@" >/dev/null
    sleep 8
    bar "$WATCH"; sleep 1
    xcrun simctl io "$WATCH" screenshot "$RAW/$name.png" >/dev/null 2>&1
    cp "$RAW/$name.png" "$OUT/$name.png"
    echo "$name"
}
if want_watch; then
    launch 10 "${EN[@]}" "${LIGHT[@]}" -acilis kiblegah://bugun
    PGROUP="$(xcrun simctl get_app_container "$PHONE" "$BID" "$GROUP")"
    xcrun simctl boot "$WATCH" 2>/dev/null; xcrun simctl bootstatus "$WATCH" -b >/dev/null
    xcrun simctl uninstall "$WATCH" "$WBID" 2>/dev/null
    xcrun simctl install "$WATCH" "$DD/Debug-watchsimulator/KiblegahWatch.app"
    WDATA=$(xcrun simctl get_app_container "$WATCH" "$WBID" data)
    WGROUP=$(xcrun simctl get_app_container "$WATCH" "$WBID" "$GROUP")
    mkdir -p "$WDATA/Library/Application Support" "$WGROUP"
    cp "$PGROUP/anlik.json" "$WDATA/Library/Application Support/anlik.json"
    cp "$PGROUP/anlik.json" "$PGROUP/okuma.json" "$WGROUP/"
    wshot watch-01
    wshot watch-02 -saatEkran kible
    wshot watch-03 -saatEkran komplikasyon1
    wshot watch-04 -saatEkran komplikasyon2
fi