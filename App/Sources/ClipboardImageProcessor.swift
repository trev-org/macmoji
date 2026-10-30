#if os(macOS)
import Foundation
import ImageIO
import MacmojiCore

/// Performs image decoding and thumbnail encoding away from the main run loop.
enum ClipboardImageProcessor {
    static let maximumImageBytes = 50 * 1_024 * 1_024
    private static let thumbnailPixelSize = 256

    static func prepare(_ captured: ClipboardCaptureContent) -> ClipboardCaptureContent? {
        guard case .image(let data, _, let format, _, _) = captured else { return captured }
        guard !data.isEmpty, data.count <= maximumImageBytes else { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return captured
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
            as? [CFString: Any]
        let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
        let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailPixelSize,
        ]
        let thumbnailData = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ).flatMap(pngData)

        return .image(
            data: data,
            thumbnailData: thumbnailData,
            format: format,
            pixelWidth: width,
            pixelHeight: height
        )
    }

    private static func pngData(_ image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            "public.png" as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
#endif
