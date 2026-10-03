import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Preparation and decoding for the optional resume headshot.
///
/// Uses ImageIO/CoreGraphics rather than UIKit so the same code serves the SwiftUI preview and
/// the PDF/Word exporters, which are deliberately UIKit-free (see `PDFDocumentRenderer`).
enum ResumePhoto {
    /// Longest edge of the stored image. The photo prints at about one inch, so anything larger
    /// is wasted bytes in every exported file — and the `.docx` writer stores entries
    /// uncompressed, which makes an unresized camera image especially expensive.
    private static let maximumEdge = 512

    /// Centre-crops to a square and re-encodes as JPEG.
    ///
    /// Cropping up front matters because every renderer clips the result to a circle: a portrait
    /// photo drawn into a round frame without a square crop first gets squashed, because the
    /// drawing rect is square but the source aspect ratio isn't.
    static func prepare(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let original = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }

        let upright = applyingOrientation(to: original, from: source)
        guard let square = centreCropped(upright) else { return nil }
        let edge = min(square.width, maximumEdge)
        guard let scaled = resized(square, to: edge) else { return nil }
        return jpegData(from: scaled)
    }

    /// Decodes stored photo bytes for drawing.
    static func image(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    // MARK: - Steps

    /// Bakes an EXIF orientation tag into the pixels.
    ///
    /// A photo taken in portrait is usually stored as landscape pixels plus a rotation tag.
    /// `CGImage` carries no orientation of its own, so without this the headshot would export
    /// lying on its side — the same trap `ResumeTextExtraction.uprightImage` handles for OCR.
    private static func applyingOrientation(to image: CGImage, from source: CGImageSource) -> CGImage {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let raw = properties[kCGImagePropertyOrientation] as? UInt32,
              let orientation = CGImagePropertyOrientation(rawValue: raw),
              orientation != .up else { return image }

        let swapsAxes = [.left, .right, .leftMirrored, .rightMirrored].contains(orientation)
        let width = swapsAxes ? image.height : image.width
        let height = swapsAxes ? image.width : image.height

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return image }

        // Quartz is y-up, so each transform is expressed in that space. Rotation first, then the
        // mirror for the four flipped variants (a front-camera selfie is commonly `.upMirrored`
        // or `.leftMirrored`) — without the second step those orientations came out reversed.
        switch orientation {
        case .down, .downMirrored:
            context.translateBy(x: CGFloat(width), y: CGFloat(height))
            context.rotate(by: .pi)
        case .left, .leftMirrored:
            context.translateBy(x: CGFloat(width), y: 0)
            context.rotate(by: .pi / 2)
        case .right, .rightMirrored:
            context.translateBy(x: 0, y: CGFloat(height))
            context.rotate(by: -.pi / 2)
        default:
            break
        }

        switch orientation {
        case .upMirrored, .downMirrored, .leftMirrored, .rightMirrored:
            context.translateBy(x: CGFloat(image.width), y: 0)
            context.scaleBy(x: -1, y: 1)
        default:
            break
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage() ?? image
    }

    private static func centreCropped(_ image: CGImage) -> CGImage? {
        let edge = min(image.width, image.height)
        guard image.width != image.height else { return image }
        let rect = CGRect(
            x: (image.width - edge) / 2,
            y: (image.height - edge) / 2,
            width: edge,
            height: edge
        )
        return image.cropping(to: rect)
    }

    private static func resized(_ image: CGImage, to edge: Int) -> CGImage? {
        guard image.width != edge else { return image }
        guard let context = CGContext(
            data: nil,
            width: edge,
            height: edge,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: edge, height: edge))
        return context.makeImage()
    }

    private static func jpegData(from image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
