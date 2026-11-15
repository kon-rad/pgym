import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// JPEG in and out for the proof. Everything written here carries no EXIF, no GPS and no maker notes:
/// a gym photo with a location says where someone is at 18:47 every Monday (pgym-architecture.md).
enum ProofImageIO {
    enum IOError: Error, Equatable {
        case unreadable
        case encode
    }

    /// The uploaded photo's long edge (pgym-architecture.md, "S3 layout").
    static let photoLongEdge = 2048
    static let photoQuality: CGFloat = 0.9
    /// Card export (pgym-proof-card-spec.md, "Export").
    static let cardQuality: CGFloat = 0.85
    static let cardRetryQualities: [CGFloat] = [0.80, 0.75]

    /// Size budget in bytes: 500 KB for 4:5, 750 KB for 9:16. A budget, not a hard limit.
    static func cardBudget(_ size: ProofCardSize) -> Int {
        switch size {
        case .feed: 500 * 1024
        case .story: 750 * 1024
        }
    }

    /// The camera's file data to an upright photo at most 2048 px on the long edge, plus its clean JPEG.
    /// The orientation is applied to the pixels, so the clean file needs no orientation tag either.
    static func cleanPhoto(from data: Data) throws -> (image: CGImage, jpeg: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw IOError.unreadable }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: photoLongEdge,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw IOError.unreadable
        }
        return (image, try jpeg(image, quality: photoQuality))
    }

    /// The rendered card as JPEG at 0.85; over budget it is re-encoded at 0.80, then 0.75.
    static func cardJPEG(_ card: CGImage, size: ProofCardSize) throws -> Data {
        var data = try jpeg(card, quality: cardQuality)
        for quality in cardRetryQualities where data.count > cardBudget(size) {
            data = try jpeg(card, quality: quality)
        }
        return data
    }

    /// A baseline sRGB JPEG with no metadata dictionaries at all.
    static func jpeg(_ image: CGImage, quality: CGFloat) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw IOError.encode
        }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImageMetadataShouldExcludeGPS: true,
            kCGImageMetadataShouldExcludeXMP: true,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw IOError.encode }
        return output as Data
    }

    /// The metadata dictionaries a JPEG carries, for the tests and a debug check.
    static func metadata(of data: Data) -> [String: Any] {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else { return [:] }
        return properties
    }

    static func hasLocation(_ data: Data) -> Bool {
        metadata(of: data)[kCGImagePropertyGPSDictionary as String] != nil
    }

    static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
