import Core
import DesignSystem
import PrayerTimes
import SwiftUI
import UserData

/// Without a place: explain, search for a city or allow location.
struct NoLocationScreen: View {
    @Environment(PrayerTimeModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var open
    let searchCity: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(app: "konum.yok.baslik").typography(.title1)
                Text(app: model.noLocationPermission ? "konum.yok.izin_yok" : "konum.yok.aciklama")
                    .typography(.body).foregroundStyle(theme.colors.text2)
                Button(localized("konum.sehir_ara"), action: searchCity).buttonStyle(PrimaryButton())
                if model.noLocationPermission {
                    Button(localized("konum.izin_ac")) {
                        if let url = URL(string: "app-settings:") { open(url) }
                    }
                    .buttonStyle(SecondaryButton())
                } else {
                    Button(localized("konum.kullan")) {
                        Task { await model.checkLocation(settings, requested: true) }
                    }
                    .buttonStyle(SecondaryButton())
                }
                Text(app: "konum.gizlilik").typography(.footnote).foregroundStyle(theme.colors.text2)
            }
            .padding(20)
            .padding(.top, 40)
        }
    }
}

/// City search as a sheet; closes back to the caller. States „sonuç yok“ and offline.
struct LocationPickerScreen: View {
    @Environment(PrayerTimeModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var close
    @Environment(\.theme) private var theme
    @State private var search = ""
    @State private var results: [LocationService.PlaceResult] = []
    @State private var searching = false
    @State private var searched = false
    @State private var locating = false
    @State private var locationNotFound = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        Task {
                            locating = true
                            locationNotFound = false
                            let found = await model.checkLocation(settings, requested: true)
                            locating = false
                            if found { close() } else { locationNotFound = true }
                        }
                    } label: {
                        Label {
                            Text(app: "konum.kullan")
                        } icon: {
                            if locating { ProgressView() } else { Image(systemName: "location") }
                        }
                    }
                    .disabled(model.noLocationPermission || locating)
                    if locationNotFound {
                        Text(app: "konum.bulunamadi").typography(.footnote).foregroundStyle(
                            theme.colors.text2)
                    }
                }
                Section {
                    if searched && !searching && results.isEmpty {
                        Text(app: "konum.sonuc_yok").foregroundStyle(theme.colors.text2)
                    }
                    ForEach(results, id: \.self) { s in
                        Button {
                            // Close at once; the board loads behind it (the server must not slow this down).
                            Task {
                                await model.selectLocation(s.location, settings: settings, automatic: false)
                            }
                            close()
                        } label: {
                            VStack(alignment: .leading) {
                                Text(verbatim: s.location.name).foregroundStyle(theme.colors.text)
                                Text(verbatim: s.explanation).typography(.footnote).foregroundStyle(
                                    theme.colors.text2)
                            }
                        }
                    }
                    // Diyanet places appear immediately; Apple Maps follows below.
                    if searching { ProgressView() }
                }
            }
            .alwaysSearchable($search, prompt: localized("konum.sehir_ara"))
            .onSubmit(of: .search) { Task { await runSearch() } }
            .task(id: search) {
                try? await Task.sleep(for: .milliseconds(450))
                if !Task.isCancelled { await runSearch() }
            }
            .pageBackground()
            .navigationTitle(localized("konum.baslik"))
            .smallTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("genel.kapat")) { close() }
                }
            }
        }
    }

    private func runSearch() async {
        guard search.trimmingCharacters(in: .whitespaces).count >= 2 else {
            results = []
            searched = false
            return
        }
        let local = model.locationService.localSearch(search)
        results = local
        searching = true
        let online = await model.locationService.search(search, server: model.server(settings))
        guard !Task.isCancelled else { return }
        results = LocationService.merge(local: local, online: online)
        searching = false
        searched = true
    }
}

/// „Kerahat nedir?“: one text, the same everywhere.
struct KarahatScreen: View {
    @Environment(\.dismiss) private var close
    @Environment(\.theme) private var theme
    @Environment(AppSettings.self) private var settings

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(app: "kerahat.aciklama").typography(.body)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(app: "kerahat.pencere.dogus \(settings.karahatMinutes)")
                        Text(app: "kerahat.pencere.zeval \(DayTimeline.zawalMinutes)")
                        Text(app: "kerahat.pencere.batis \(DayTimeline.maghribKarahatMinutes)")
                    }
                    .typography(.body)
                    Text(app: "kerahat.not").typography(.footnote).foregroundStyle(theme.colors.text2)
                }
                .padding(20)
            }
            .pageBackground()
            .navigationTitle(localized("kerahat.nedir"))
            .smallTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(localized("genel.kapat")) { close() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
