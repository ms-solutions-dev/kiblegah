#if os(iOS)
    import UIKit

    /// The cover on the lock screen: surah name in calligraphy, verse below it.
    /// Core Graphics instead of `ImageRenderer`, because it must also work while the app is in the background.
    public enum NowPlayingArtwork {
        private static let side: CGFloat = 600
        // From the approved mockup and the green of the app icon.
        private static let background = UIColor(
            red: 0x17 / 255, green: 0x3F / 255, blue: 0x31 / 255, alpha: 1)
        private static let nameColor = UIColor(red: 0xF4 / 255, green: 0xEA / 255, blue: 0xDB / 255, alpha: 1)
        private static let accent = UIColor(red: 0xE9 / 255, green: 0x87 / 255, blue: 0x6D / 255, alpha: 1)

        @MainActor public static func image(arabicName: String, label: String) -> UIImage {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let bounds = CGRect(x: 0, y: 0, width: side, height: side)
            return UIGraphicsImageRenderer(bounds: bounds, format: format).image { context in
                background.setFill()
                context.fill(bounds)

                let name = fitted(arabicName, maxWidth: side * 0.86)
                let nameSize = name.size()
                let captionText = NSAttributedString(
                    string: label,
                    attributes: [
                        .font: UIFont.systemFont(ofSize: 36, weight: .semibold),
                        .foregroundColor: accent,
                    ])
                let captionSize = captionText.size()
                let top = (side - nameSize.height - captionSize.height) / 2
                name.draw(at: CGPoint(x: (side - nameSize.width) / 2, y: top))
                captionText.draw(
                    at: CGPoint(x: (side - captionSize.width) / 2, y: top + nameSize.height))
            }
        }

        /// Long surah names get smaller until they fit.
        private static func fitted(_ text: String, maxWidth: CGFloat) -> NSAttributedString {
            var size: CGFloat = 190
            while true {
                let font =
                    UIFont(name: Typography.arabicFontName + "-Bold", size: size)
                    ?? .boldSystemFont(ofSize: size)
                let result = NSAttributedString(
                    string: text,
                    attributes: [.font: font, .foregroundColor: nameColor])
                if result.size().width <= maxWidth || size <= 60 { return result }
                size -= 6
            }
        }
    }
#endif
