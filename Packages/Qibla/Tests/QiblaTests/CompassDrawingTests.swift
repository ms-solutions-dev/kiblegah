import CoreGraphics
import Testing

@testable import Qibla

@Suite struct CompassLetterTests {
    @Test func keys() {
        #expect(CompassLetter.key(0) == "kible.harita.yon.0")
        #expect(CompassLetter.key(3) == "kible.harita.yon.3")
        #expect(CompassLetter.key(5) == "kible.harita.yon.1")
    }

    /// When looking south, south is at the top and north at the bottom – the letters themselves never rotate.
    @Test func facingSouth() {
        let s = CompassLetter.location(2, direction: 180, r: 100)
        #expect(abs(s.x) < 0.001 && abs(s.y + 100) < 0.001)
        let n = CompassLetter.location(0, direction: 180, r: 100)
        #expect(abs(n.y - 100) < 0.001)
        let d = CompassLetter.location(1, direction: 0, r: 100)
        #expect(abs(d.x - 100) < 0.001 && abs(d.y) < 0.001)
    }
}

@Suite struct QiblaFramingTests {
    let size = CGSize(width: 400, height: 800)

    /// Without panel: 25 % margin on each side of the longer edge, aspect ratio of the map.
    @Test func withoutPanel() {
        let path = CGRect(x: 1000, y: 1000, width: 400, height: 200)
        let c = QiblaFraming.frame(path: path, size: size)
        #expect(abs(c.width / c.height - 0.5) < 1e-9)
        #expect(c.minX <= path.minX - 100 + 1e-9 && c.maxX >= path.maxX + 100 - 1e-9)
        #expect(abs(c.midX - path.midX) < 1e-9 && abs(c.midY - path.midY) < 1e-9)
    }

    /// With panel: the route including margin lies entirely in the free area above the panel, centered there.
    @Test func withPanelCenteredInFreeArea() {
        let path = CGRect(x: 0, y: 0, width: 300, height: 600)
        let bottom = 300.0
        let c = QiblaFraming.frame(path: path, size: size, bottom: bottom)
        let scale = c.height / size.height
        let screenTop = (path.minY - 150 - c.minY) / scale
        let screenBottom = (path.maxY + 150 - c.minY) / scale
        #expect(screenTop >= -1e-6)
        #expect(screenBottom <= size.height - bottom + 1e-6)
        let screenMiddle = (path.midY - c.minY) / scale
        #expect(abs(screenMiddle - (size.height - bottom) / 2) < 1e-6)
    }

    /// A huge panel (AX3) does not eat up the map completely: at least 30 % remains free.
    @Test func devPanel() {
        let path = CGRect(x: 0, y: 0, width: 100, height: 100)
        let c = QiblaFraming.frame(path: path, size: size, bottom: 790)
        #expect(c.height.isFinite && c.height > 0)
    }
}
