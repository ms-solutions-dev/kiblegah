#if os(iOS)
    import AVFoundation
    import UIKit

    /// The tall (3:4) lock screen cover: the surah name on slowly drifting light, as a seamless loop.
    /// Created once per surah and kept in the cache; the verse is in the title below anyway.
    public actor NowPlayingVideo {
        public static let shared = NowPlayingVideo()

        private static let width = 720
        private static let height = 960
        private static let framesPerSecond: Int32 = 15
        private static let frameCount = 120
        private static let version = 1

        private var running: [Int: Task<URL?, Never>] = [:]

        /// The finished file, or `nil` if it could not be created (for example because iOS refuses the
        /// encoder in the background). The normal cover stays in that case.
        public func url(surah: Int, arabicName: String) async -> URL? {
            let target = Self.file(surah: surah)
            if FileManager.default.fileExists(atPath: target.path) { return target }
            if let t = running[surah] { return await t.value }
            let t = Task<URL?, Never>.detached {
                do {
                    try Self.write(arabicName: arabicName, target: target)
                    return target
                } catch {
                    return nil
                }
            }
            running[surah] = t
            let result = await t.value
            running[surah] = nil
            return result
        }

        /// The first frame of the video, as a preview while the video loads.
        public nonisolated static func preview(arabicName: String) -> UIImage? {
            guard let name = nameImage(arabicName),
                let c = makeContext(data: nil, bytesPerRow: 0)
            else { return nil }
            draw(c, name: name, phase: 0)
            return c.makeImage().map { UIImage(cgImage: $0) }
        }

        private static func file(surah: Int) -> URL {
            let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appending(path: "lockscreen-video", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder.appending(path: "v\(version)-surah-\(surah).mp4")
        }

        private enum Failure: Error { case setup, writing }

        private static func write(arabicName: String, target: URL) throws {
            guard let name = nameImage(arabicName) else { throw Failure.setup }
            let temporary = target.deletingLastPathComponent().appending(path: UUID().uuidString + ".mp4")
            defer { try? FileManager.default.removeItem(at: temporary) }

            let writer = try AVAssetWriter(outputURL: temporary, fileType: .mp4)
            let input = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: width,
                    AVVideoHeightKey: height,
                    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 1_500_000],
                ])
            input.expectsMediaDataInRealTime = false
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: width,
                    kCVPixelBufferHeightKey as String: height,
                ])
            writer.add(input)
            guard writer.startWriting() else { throw writer.error ?? Failure.setup }
            writer.startSession(atSourceTime: .zero)

            for i in 0..<frameCount {
                while !input.isReadyForMoreMediaData {
                    guard writer.status == .writing else { throw writer.error ?? Failure.writing }
                    Thread.sleep(forTimeInterval: 0.005)
                }
                guard let pool = adaptor.pixelBufferPool else { throw Failure.setup }
                var buffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
                guard let buffer else { throw Failure.writing }
                CVPixelBufferLockBaseAddress(buffer, [])
                if let c = makeContext(
                    data: CVPixelBufferGetBaseAddress(buffer),
                    bytesPerRow: CVPixelBufferGetBytesPerRow(buffer))
                {
                    draw(c, name: name, phase: Double(i) / Double(frameCount))
                }
                CVPixelBufferUnlockBaseAddress(buffer, [])
                let time = CMTime(value: CMTimeValue(i), timescale: framesPerSecond)
                guard adaptor.append(buffer, withPresentationTime: time) else {
                    throw writer.error ?? Failure.writing
                }
            }
            input.markAsFinished()
            let finished = DispatchSemaphore(value: 0)
            nonisolated(unsafe) let y = writer
            y.finishWriting { finished.signal() }
            finished.wait()
            guard y.status == .completed else { throw y.error ?? Failure.writing }
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: temporary, to: target)
        }

        private static func makeContext(data: UnsafeMutableRawPointer?, bytesPerRow: Int) -> CGContext? {
            CGContext(
                data: data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue)
        }

        /// One frame of the loop; `phase` runs from 0 to below 1, sine and cosine close it seamlessly.
        private static func draw(_ c: CGContext, name: CGImage, phase: Double) {
            let w = CGFloat(Self.width)
            let h = CGFloat(Self.height)
            let angle = 2 * Double.pi * phase
            c.setFillColor(red: 0x10 / 255, green: 0x2E / 255, blue: 0x24 / 255, alpha: 1)
            c.fill(CGRect(x: 0, y: 0, width: w, height: h))
            let center = CGPoint(
                x: w * (0.5 + 0.10 * sin(angle)), y: h * (0.56 + 0.04 * cos(angle)))
            let brightness = 0.75 + 0.15 * sin(angle)
            let colors =
                [
                    CGColor(srgbRed: 0x35 / 255, green: 0x7A / 255, blue: 0x60 / 255, alpha: brightness),
                    CGColor(srgbRed: 0x35 / 255, green: 0x7A / 255, blue: 0x60 / 255, alpha: 0),
                ] as CFArray
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])
            {
                c.drawRadialGradient(
                    gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: h * 0.6,
                    options: [])
            }
            // Above the lock screen controls, below the clock.
            let size = CGSize(width: name.width, height: name.height)
            c.draw(
                name,
                in: CGRect(
                    x: (w - size.width) / 2, y: h * 0.56 - size.height / 2, width: size.width,
                    height: size.height))
        }

        private static func nameImage(_ text: String) -> CGImage? {
            var size: CGFloat = 230
            var attributed = NSAttributedString()
            while size > 60 {
                let f =
                    UIFont(name: Typography.arabicFontName + "-Bold", size: size)
                    ?? .boldSystemFont(ofSize: size)
                attributed = NSAttributedString(
                    string: text,
                    attributes: [
                        .font: f,
                        .foregroundColor: UIColor(
                            red: 0xF4 / 255, green: 0xEA / 255, blue: 0xDB / 255, alpha: 1),
                    ])
                if attributed.size().width <= CGFloat(width) * 0.84 { break }
                size -= 6
            }
            let measured = attributed.size()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = false
            let s = attributed
            return UIGraphicsImageRenderer(size: measured, format: format).image { _ in
                s.draw(at: .zero)
            }.cgImage
        }
    }
#endif
