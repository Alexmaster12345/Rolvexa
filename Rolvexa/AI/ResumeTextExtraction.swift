import Foundation
import PDFKit
import Vision
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
private extension UIImage.Orientation {
    /// `UIImage.Orientation` and `CGImagePropertyOrientation` describe the same eight cases but
    /// use different raw values, so they can't be bridged by `rawValue` alone.
    init?(exif: CGImagePropertyOrientation) {
        switch exif {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: return nil
        }
    }
}
#endif

/// Extracts plain text from an uploaded resume file — fully offline, no network access at any
/// point. Handles text-based PDFs directly via `PDFKit`, falls back to on-device OCR (`Vision`)
/// for scanned/image-only PDFs and for photos or screenshots of a resume, and reads `.docx` by
/// unzipping its OOXML and stripping markup.
enum ResumeTextExtraction {
    /// File extensions accepted as an image upload (a photo or screenshot of a resume), which is
    /// read via OCR rather than by parsing a document format.
    static let imageFileExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "gif", "bmp", "webp"
    ]

    static func isImageFileExtension(_ fileExtension: String) -> Bool {
        imageFileExtensions.contains(fileExtension.lowercased())
    }

    static func extractText(from url: URL, fileExtension: String) -> String? {
        let normalized = fileExtension.lowercased()
        switch normalized {
        case "pdf":
            return extractFromPDF(url: url)
        case "docx":
            return extractFromDOCX(url: url)
        default:
            return isImageFileExtension(normalized) ? extractFromImage(url: url) : nil
        }
    }

    // MARK: - Image (OCR)

    /// Reads a photo or screenshot of a resume. Unlike the PDF path there's no selectable-text
    /// shortcut to try first — OCR is the only option.
    static func extractFromImage(url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return recognizeTextInImage(from: source)
    }

    /// Same as ``extractFromImage(url:)`` but for image bytes already in memory — used by the
    /// photo-library path, where there's no file on disk to point at.
    static func extractFromImageData(_ data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return recognizeTextInImage(from: source)
    }

    private static func recognizeTextInImage(from source: CGImageSource) -> String? {
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let upright = uprightImage(image, orientation: orientation(of: source)) ?? image
        return recognizeText(in: upright)
    }

    /// Bakes a photo's EXIF orientation into its pixels so the bitmap is visually upright.
    ///
    /// Vision recognizes rotated text perfectly well on its own, so this isn't about accuracy —
    /// it's about *ordering*. `VNRecognizedTextObservation.boundingBox` is reported in the
    /// original stored pixel space, not the display-oriented one, so the top-to-bottom sort in
    /// `recognizeText` runs along the wrong axis for a sideways photo and emits the resume's
    /// sections in reverse. Normalizing first keeps the bitmap and the bounding boxes in the
    /// same upright space.
    private static func uprightImage(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation
    ) -> CGImage? {
        guard orientation != .up else { return image }
        #if canImport(UIKit)
        guard let uiOrientation = UIImage.Orientation(exif: orientation) else { return image }
        let oriented = UIImage(cgImage: image, scale: 1, orientation: uiOrientation)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let redrawn = UIGraphicsImageRenderer(size: oriented.size, format: format).image { _ in
            oriented.draw(in: CGRect(origin: .zero, size: oriented.size))
        }
        return redrawn.cgImage
        #else
        // Non-UIKit platforms keep the original bitmap; ordering may differ for rotated photos.
        return image
        #endif
    }

    /// A photo taken with the camera is very often stored rotated, with an EXIF tag describing
    /// how to display it. `CGImage` ignores that tag, so handing Vision the raw bitmap of a
    /// sideways photo yields rotated text and near-zero recognition. Reading the tag and passing
    /// it through lets Vision correct for it.
    private static func orientation(of source: CGImageSource) -> CGImagePropertyOrientation {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let raw = properties[kCGImagePropertyOrientation] as? UInt32,
              let parsed = CGImagePropertyOrientation(rawValue: raw) else {
            return .up
        }
        return parsed
    }

    // MARK: - PDF (+ OCR fallback)

    private static func extractFromPDF(url: URL) -> String? {
        guard let document = PDFDocument(url: url) else { return nil }
        if let text = document.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        // No selectable text at all — almost always a scanned/photographed resume rather than a
        // genuinely empty document. Falling back straight to "we couldn't read this file" would
        // reject a very common real-world resume format, so OCR every page instead.
        return ocrText(from: document)
    }

    private static func ocrText(from document: PDFDocument) -> String? {
        var pageTexts: [String] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            guard let cgImage = renderPageToImage(page) else { continue }
            if let text = recognizeText(in: cgImage) {
                pageTexts.append(text)
            }
        }
        let combined = pageTexts.joined(separator: "\n")
        return combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : combined
    }

    /// Rasterizes a PDF page to an RGB bitmap at 2x its native (72dpi) resolution — sharp enough
    /// for `Vision` to recognize typical resume body-text sizes reliably.
    private static func renderPageToImage(_ page: PDFPage) -> CGImage? {
        let pageRect = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2
        let width = max(1, Int(pageRect.width * scale))
        let height = max(1, Int(pageRect.height * scale))

        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }

    private static func recognizeText(
        in image: CGImage,
        orientation: CGImagePropertyOrientation = .up
    ) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("[ResumeTextExtraction] OCR failed: \(error)")
            return nil
        }
        // Vision returns observations in no guaranteed reading order. Sorting top-to-bottom (and
        // left-to-right within a line) keeps a resume's sections in the order a human sees them,
        // which everything downstream — section detection, the header/contact parser, the
        // templated export — assumes. Note `boundingBox` is in Vision's bottom-left origin space,
        // so a *larger* minY means *higher* on the page.
        let observations = (request.results ?? []).sorted { lhs, rhs in
            let lineHeight = max(lhs.boundingBox.height, rhs.boundingBox.height)
            // Treat observations whose vertical centers are within one line height of each other
            // as the same visual line, so side-by-side columns don't interleave by a few pixels.
            if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > lineHeight * 0.5 {
                return lhs.boundingBox.midY > rhs.boundingBox.midY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    // MARK: - DOCX

    private static func extractFromDOCX(url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let documentXMLData = MinimalZipReader.extract(entryName: "word/document.xml", from: data) else { return nil }
        guard let xml = String(data: documentXMLData, encoding: .utf8) else { return nil }
        let text = plainText(fromWordXML: xml)
        return text.isEmpty ? nil : text
    }

    /// Strips OOXML markup down to plain text, turning paragraph/line/tab tags into their
    /// visible-text equivalents first so the result reads like the original document instead of
    /// one run-on line.
    private static func plainText(fromWordXML xml: String) -> String {
        var text = xml
        text = text.replacingOccurrences(of: "</w:p>", with: "\n")
        text = text.replacingOccurrences(of: "<w:br/>", with: "\n")
        text = text.replacingOccurrences(of: "<w:tab/>", with: "\t")
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&apos;", with: "'")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
