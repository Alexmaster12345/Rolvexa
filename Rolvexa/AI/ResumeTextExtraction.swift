import Foundation
import PDFKit
import Vision
import CoreGraphics

/// Extracts plain text from an uploaded resume file — fully offline, no network access at any
/// point. Handles text-based PDFs directly via `PDFKit`, falls back to on-device OCR (`Vision`)
/// for scanned/image-only PDFs, and reads `.docx` by unzipping its OOXML and stripping markup.
enum ResumeTextExtraction {
    static func extractText(from url: URL, fileExtension: String) -> String? {
        switch fileExtension.lowercased() {
        case "pdf":
            return extractFromPDF(url: url)
        case "docx":
            return extractFromDOCX(url: url)
        default:
            return nil
        }
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

    private static func recognizeText(in image: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("[ResumeTextExtraction] OCR failed: \(error)")
            return nil
        }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
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
