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

    /// The lines set in the largest type on the page, which on a resume is essentially always
    /// the candidate's name. Position can't identify it: a two-column layout is read sidebar
    /// first, so the name often lands well down the extracted text, behind whole sections.
    /// Size is the signal a person actually uses.
    static var lastProminentLines: [String] = []

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

    /// Of the observations, the ones whose glyph height is close to the tallest on the page.
    /// Short, digit-free lines only, so a large section heading or a stray wide box doesn't
    /// masquerade as the name.
    private static func prominentLines(
        from observations: [VNRecognizedTextObservation]
    ) -> [String] {
        let candidates = observations.compactMap { observation -> (String, CGFloat)? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.count <= 24,
                  !trimmed.contains(where: \.isNumber),
                  !trimmed.contains("@"),
                  trimmed.split(separator: " ").count <= 3 else { return nil }
            return (trimmed, observation.boundingBox.height)
        }
        guard let tallest = candidates.map(\.1).max(), tallest > 0 else { return [] }
        // A name split across two lines ("ELLIOT" above "ALDERSON") is set at the same size, so
        // a band rather than a single maximum is needed. Headings are markedly smaller.
        return candidates.filter { $0.1 >= tallest * 0.82 }.map(\.0)
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
        let observations = request.results ?? []
        lastProminentLines = prominentLines(from: observations)
        let lines = readingOrder(observations).compactMap { $0.topCandidates(1).first?.string }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// Vision returns observations in no guaranteed order, so they're sorted into the order a
    /// human reads them. Everything downstream — section detection, the header/contact parser,
    /// the templated export — assumes visual order.
    ///
    /// Resumes very often use a narrow sidebar beside a wide main column. Sorting those purely
    /// top-to-bottom interleaves the two ("CONTACT / ELLIOT ALDERSON / elliot@… / Highly skilled
    /// Linux Administrator…"), which scrambles every section. So a vertical gutter is detected
    /// first and each column is read out whole, left to right.
    ///
    /// Applied recursively, because columns nest: an Experience section commonly sets the
    /// employer, location and dates in a narrow strip beside the achievement bullets. Splitting
    /// the page only once left that inner pair interleaved — "ALLSAFE / Senior Linux
    /// Administrator / CYBERSECURITY / • Managed… / New York / • Implemented… / Jan 2015 - Dec
    /// 2019" — which tore employer names in half and scattered the dates through the bullets.
    /// A recursive XY-cut: at each step the page is divided along whichever whitespace gap is
    /// wider — a vertical gutter between columns, or a horizontal band between blocks — and each
    /// piece is then cut again.
    ///
    /// Choosing the larger gap is what keeps a job's heading with its own bullets. Cutting
    /// vertically first would read every employer, then every bullet; cutting horizontally first
    /// would slice straight through the page's sidebar. Taking the more confident cut at each
    /// step gives: page → sidebar | main, then main → one band per job, then each band →
    /// employer strip | its bullets.
    private static func readingOrder(
        _ observations: [VNRecognizedTextObservation],
        depth: Int = 0
    ) -> [VNRecognizedTextObservation] {
        guard observations.count > 1, depth < 5 else { return sortedTopToBottom(observations) }

        func splitVertically(_ vertical: (position: CGFloat, width: CGFloat)) -> [VNRecognizedTextObservation] {
            let left = observations.filter { $0.boundingBox.midX < vertical.position }
            let right = observations.filter { $0.boundingBox.midX >= vertical.position }
            return readingOrder(left, depth: depth + 1) + readingOrder(right, depth: depth + 1)
        }
        func splitHorizontally(_ horizontal: (position: CGFloat, width: CGFloat)) -> [VNRecognizedTextObservation] {
            // Vision's origin is bottom-left, so the *upper* band is the one above the split.
            let upper = observations.filter { $0.boundingBox.midY >= horizontal.position }
            let lower = observations.filter { $0.boundingBox.midY < horizontal.position }
            return readingOrder(upper, depth: depth + 1) + readingOrder(lower, depth: depth + 1)
        }

        // The page itself is cut into columns first: a sidebar runs the whole height, so banding
        // the page horizontally would slice through it and interleave its sections with the main
        // column's.
        //
        // Inside a column the preference flips to horizontal. An Experience section repeats the
        // same shape for every job — employer strip beside bullets — so its inner gutter runs the
        // column's full height and looks exactly like a real column. Cutting vertically there
        // yields every employer followed by every bullet. Cutting into one band per job first,
        // then splitting each band, keeps each heading with its own bullets.
        if depth == 0, let vertical = columnSplit(in: observations) {
            return splitVertically(vertical)
        }
        if let horizontal = rowSplit(in: observations) {
            return splitHorizontally(horizontal)
        }
        // A single job band holds only a handful of lines, far fewer than a page column, so the
        // page-level minimum would reject it and leave the employer strip interleaved with its
        // own bullets. The balance checks inside still guard against splitting on noise.
        if let vertical = columnSplit(in: observations, minimumObservations: 4) {
            return splitVertically(vertical)
        }
        return sortedTopToBottom(observations)
    }

    /// The widest horizontal band of whitespace running the full width of `observations`, used
    /// to separate stacked blocks (one job from the next) before looking for columns inside them.
    private static func rowSplit(in observations: [VNRecognizedTextObservation]) -> (position: CGFloat, width: CGFloat)? {
        guard observations.count >= 4 else { return nil }
        let sorted = observations.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
        // A gap only counts if it clears the tallest line around it, otherwise ordinary line
        // spacing would be mistaken for a block boundary.
        let typicalHeight = sorted.map(\.boundingBox.height).reduce(0, +) / CGFloat(sorted.count)

        var best: (position: CGFloat, width: CGFloat)?
        for index in 0..<(sorted.count - 1) {
            let lowestSoFar = sorted[0...index].map(\.boundingBox.minY).min() ?? 0
            let nextTop = sorted[index + 1].boundingBox.maxY
            let gap = lowestSoFar - nextTop
            guard gap > typicalHeight * 0.9 else { continue }
            if best == nil || gap > best!.width {
                best = (nextTop + gap / 2, gap)
            }
        }
        return best
    }

    private static func sortedTopToBottom(
        _ observations: [VNRecognizedTextObservation]
    ) -> [VNRecognizedTextObservation] {
        observations.sorted { lhs, rhs in
            let lineHeight = max(lhs.boundingBox.height, rhs.boundingBox.height)
            // Observations whose vertical centers are within half a line height of each other are
            // the same visual line, so they read left-to-right rather than by a few stray pixels.
            // Note `boundingBox` uses Vision's bottom-left origin: a *larger* midY is *higher*.
            if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > lineHeight * 0.5 {
                return lhs.boundingBox.midY > rhs.boundingBox.midY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }
    }

    /// Finds the x position of a vertical gutter separating two columns, or nil for a
    /// single-column page.
    ///
    /// Deliberately conservative — a false positive would split a normal single-column resume in
    /// half, which is far worse than leaving a two-column one interleaved. It requires a genuinely
    /// empty vertical band of real width with a substantial share of the text on both sides.
    private static func columnSplit(
        in observations: [VNRecognizedTextObservation],
        minimumObservations: Int = 8
    ) -> (position: CGFloat, width: CGFloat)? {
        guard observations.count >= minimumObservations else { return nil }

        // A handful of boxes may legitimately cross any candidate line (a full-width title, an
        // OCR box that merged across the gutter), so a few crossings are tolerated rather than
        // disqualifying a split outright.
        let crossingBudget = max(1, observations.count / 20)
        let minimumPerColumn = max(2, observations.count / 5)

        // Collect every vertical band that is effectively free of text.
        var gaps: [(start: CGFloat, end: CGFloat)] = []
        var runStart: CGFloat?
        let step: CGFloat = 0.01
        var x: CGFloat = 0.12
        while x <= 0.88 {
            let crossings = observations.filter { $0.boundingBox.minX < x && $0.boundingBox.maxX > x }.count
            if crossings <= crossingBudget {
                if runStart == nil { runStart = x }
            } else if let start = runStart {
                gaps.append((start, x - step))
                runStart = nil
            }
            x += step
        }
        if let start = runStart { gaps.append((start, 0.88)) }

        // Crucially, the *widest* gap is usually not the gutter — it is the ragged right margin
        // past the end of the longest line, which separates nothing. Only gaps that put a real
        // share of the text on both sides are true gutters, so candidates are filtered on that
        // first and the widest is chosen from whatever survives.
        let candidates: [(center: CGFloat, width: CGFloat)] = gaps.compactMap { gap in
            let width = gap.end - gap.start
            guard width >= 0.04 else { return nil }
            let center = (gap.start + gap.end) / 2
            let left = observations.filter { $0.boundingBox.midX < center }.count
            let right = observations.count - left
            guard left >= minimumPerColumn, right >= minimumPerColumn else { return nil }
            return (center, width)
        }
        guard let best = candidates.max(by: { $0.width < $1.width }) else { return nil }
        return (best.center, best.width)
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
