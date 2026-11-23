import Core
import CoreGraphics
import DesignSystem
import Foundation
import Testing

@testable import Features

struct ShareTests {
    let card = ShareCard.verse(
        arabic: "فَإِنَّ مَعَ ٱلْعُسْرِ يُسْرًا", translation: "Elbette güçlükle beraber bir kolaylık vardır.",
        source: "İnşirâh 94:5 · Diyanet meali", surah: 94, verse: 5)

    @Test @MainActor func renderInStorySize() throws {
        for style in ShareStyle.allCases {
            var s = ShareOptions()
            s.style = style
            let r = try #require(ShareCardView.render(card, selection: s, prayerTimes: .maghrib))
            #expect(r.width == 1080)
            #expect(r.height == 1920)
        }
        let k = try #require(
            ShareCardView.render(.qibla(.sample), selection: ShareOptions(), prayerTimes: .dhuhr))
        #expect(k.width == 1080 && k.height == 1920)
    }

    @Test func selectionsPersistAndPlaceDefaultOff() throws {
        let name = "paylas-test-\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: name))
        defer { d.removePersistentDomain(forName: name) }
        let empty = ShareOptions(defaults: d)
        #expect(empty == ShareOptions())
        #expect(empty.showPlace == false)
        #expect(empty.showMeaning)

        var s = ShareOptions()
        s.style = .sky
        s.color = .cream
        s.showMeaning = false
        s.showPlace = true
        s.save(d)
        #expect(ShareOptions(defaults: d) == s)
        #expect(
            [ShareOptions.styleKey, ShareOptions.colorKey].allSatisfy { !$0.contains(".") })
    }

    @Test func textHonorsPermissions() {
        let withMeaning = card.text(showMeaning: true, showPlace: false)
        let without = card.text(showMeaning: false, showPlace: false)
        #expect(withMeaning.contains("kolaylık"))
        #expect(!without.contains("kolaylık"))
        #expect(without.contains("İnşirâh 94:5"))
        #expect(without.contains("kiblegah://kuran/94:5"))

        let k = ShareCard.qibla(.sample)
        #expect(!k.text(showMeaning: true, showPlace: false).contains("Hamburg"))
        #expect(k.text(showMeaning: true, showPlace: true).contains("Hamburg"))
    }

    @Test func hadithWithoutArabicKeepsTranslation() {
        let h = ShareCard.hadith(
            text: "Kolaylaştırınız", arabic: "", source: "Muttefekun aleyh", identifier: 1)
        #expect(!h.meaningHideable)
        #expect(h.text(showMeaning: false, showPlace: false).contains("Kolaylaştırınız"))
    }
}

struct MemorizationSwipeTests {
    @Test func directions() {
        #expect(MemorizationSwipe.score(CGSize(width: -150, height: 10)) == .zor)
        #expect(MemorizationSwipe.score(CGSize(width: 150, height: -20)) == .kolay)
        #expect(MemorizationSwipe.score(CGSize(width: 10, height: -150)) == .good)
        #expect(MemorizationSwipe.score(CGSize(width: 10, height: 150)) == nil)
        #expect(MemorizationSwipe.score(CGSize(width: 60, height: -40)) == nil)
    }

    @Test func horizontalWinsOnTie() {
        #expect(MemorizationSwipe.score(CGSize(width: 130, height: -130)) == .kolay)
    }

    @Test func portraitBelongsToScrolling() {
        #expect(MemorizationSwipe.score(CGSize(width: 0, height: -200), allowUp: false) == nil)
        #expect(MemorizationSwipe.score(CGSize(width: -200, height: 0), allowUp: false) == .zor)
    }

    @Test func keyWithoutDot() {
        #expect(!MemorizationLayout.key.contains("."))
        #expect(MemorizationLayout(rawValue: "deste") == .deck)
    }
}
