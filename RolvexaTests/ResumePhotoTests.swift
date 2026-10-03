import CoreGraphics
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import Rolvexa

/// Headshot preparation. The orientation cases are checked against UIKit rather than against
/// hand-reasoned expectations — working out which way a 90° rotation moves an edge is exactly
/// the kind of thing that's easy to get backwards and then "confirm".
struct ResumePhotoTests {
    // MARK: - Helpers

    /// Four distinctly coloured quadrants, so any rotation or mirror is distinguishable.
    private static func quadrantImage(side: Int = 400) -> CGImage {
        let size = CGSize(width: side, height: side)
        let half = side / 2
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: half, height: half))
            UIColor.green.setFill()
            context.fill(CGRect(x: half, y: 0, width: half, height: half))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: half, width: half, height: half))
            UIColor.yellow.setFill()
            context.fill(CGRect(x: half, y: half, width: half, height: half))
        }.cgImage!
    }

    private static func jpeg(_ image: CGImage, orientation: CGImagePropertyOrientation) -> Data {
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        )!
        CGImageDestinationAddImage(
            destination, image,
            [kCGImagePropertyOrientation: orientation.rawValue] as CFDictionary
        )
        CGImageDestinationFinalize(destination)
        return output as Data
    }

    /// The colour at a fractional position, named.
    private static func colourName(in image: CGImage, x: CGFloat, y: CGFloat) -> String {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(
            x: -CGFloat(image.width) * x, y: -CGFloat(image.height) * (1 - y),
            width: CGFloat(image.width), height: CGFloat(image.height)
        ))
        let (r, g, b) = (pixel[0], pixel[1], pixel[2])
        if r > 140 && g < 110 && b < 110 { return "red" }
        if b > 140 && r < 110 && g < 110 { return "blue" }
        if g > 140 && r < 110 && b < 110 { return "green" }
        if r > 140 && g > 140 && b < 110 { return "yellow" }
        return "other"
    }

    private static func corners(_ image: CGImage) -> [String] {
        [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)]
            .map { colourName(in: image, x: $0.0, y: $0.1) }
    }

    /// UIKit's own interpretation of the same bytes — the oracle.
    private static func uikitBaked(_ data: Data) -> CGImage? {
        guard let image = UIImage(data: data) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: image.size, format: format)
            .image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
            .cgImage
    }

    // MARK: - Orientation

    @Test("Every EXIF orientation is normalised the same way UIKit would", arguments: [
        CGImagePropertyOrientation.up, .upMirrored,
        .down, .downMirrored,
        .left, .leftMirrored,
        .right, .rightMirrored
    ])
    func orientationsMatchUIKit(orientation: CGImagePropertyOrientation) throws {
        let data = Self.jpeg(Self.quadrantImage(), orientation: orientation)
        let prepared = try #require(ResumePhoto.prepare(from: data).flatMap(ResumePhoto.image(from:)))
        let reference = try #require(Self.uikitBaked(data))
        #expect(Self.corners(prepared) == Self.corners(reference))
    }

    @Test("An upright photo keeps its quadrants where they started")
    func uprightPhotoIsUnchanged() throws {
        let data = Self.jpeg(Self.quadrantImage(), orientation: .up)
        let prepared = try #require(ResumePhoto.prepare(from: data).flatMap(ResumePhoto.image(from:)))
        #expect(Self.corners(prepared) == ["red", "green", "blue", "yellow"])
    }

    // MARK: - Cropping and sizing

    @Test("A portrait photo is centre-cropped square so the circle doesn't squash it")
    func portraitIsCroppedSquare() throws {
        let tall = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 500)).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 500))
        }
        let prepared = try #require(
            ResumePhoto.prepare(from: tall.jpegData(compressionQuality: 0.9)!)
                .flatMap(ResumePhoto.image(from:))
        )
        #expect(prepared.width == prepared.height)
    }

    @Test("Large photos are scaled down, since the docx writer stores entries uncompressed")
    func largePhotosAreDownscaled() throws {
        let large = UIGraphicsImageRenderer(size: CGSize(width: 2000, height: 2000)).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2000, height: 2000))
        }
        let data = large.jpegData(compressionQuality: 0.9)!
        let prepared = try #require(ResumePhoto.prepare(from: data).flatMap(ResumePhoto.image(from:)))
        #expect(prepared.width <= 512)
        #expect(prepared.height <= 512)
    }

    @Test("A small photo isn't upscaled")
    func smallPhotosAreNotUpscaled() throws {
        let small = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        let prepared = try #require(
            ResumePhoto.prepare(from: small.jpegData(compressionQuality: 0.9)!)
                .flatMap(ResumePhoto.image(from:))
        )
        #expect(prepared.width <= 192, "a 64pt render shouldn't come back larger than its own pixels")
    }

    // MARK: - Bad input

    @Test("Bytes that aren't an image return nil rather than crashing")
    func rejectsNonImageData() {
        #expect(ResumePhoto.prepare(from: Data("not an image".utf8)) == nil)
        #expect(ResumePhoto.image(from: Data()) == nil)
    }
}
