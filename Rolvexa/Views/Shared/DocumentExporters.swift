import CoreGraphics
import CoreText
import Foundation

private extension CGColor {
    /// Parses a 6-digit hex string (e.g. "4B39EF") into an sRGB CGColor.
    static func fromHex(_ hex: String) -> CGColor {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >> 8) & 0xFF) / 255
        let b = CGFloat(value & 0xFF) / 255
        return CGColor(red: r, green: g, blue: b, alpha: 1)
    }
}

/// The pieces of an assembled resume's text (see `AppState+ExportText.swift`) that a sidebar or
/// banner layout needs to place separately from the flowing body — name/role/contact go in the
/// colored region, the SKILLS section is pulled out to render there too (as a bulleted list
/// rather than a plain comma-separated line), and everything else stays in reading order.
private struct ParsedResumeBody {
    var name: String
    var role: String
    var contactLine: String
    var skills: [String]
    var remainingLines: [String]
}

/// Shared by both renderers: `resumeExportText()` always shapes upload/write-from-scratch text
/// the same way (name, then role, then contact, blank line, then SUMMARY/SKILLS/EXPERIENCE...),
/// so this parses that shape back out rather than requiring the renderers' call sites to pass
/// structured fields through separately.
private func parseResumeBody(_ body: String) -> ParsedResumeBody {
    let lines = body.components(separatedBy: "\n")
    var index = 0

    func nextNonEmptyBeforeHeader() -> String? {
        while index < lines.count, !ResumeSectionKit.isSectionHeader(lines[index]) {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            index += 1
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    let name = nextNonEmptyBeforeHeader() ?? ""
    let role = nextNonEmptyBeforeHeader() ?? ""
    let contactLine = nextNonEmptyBeforeHeader() ?? ""
    // Skip past any further header-block lines (shouldn't normally be any) up to the first
    // real section header.
    while index < lines.count, !ResumeSectionKit.isSectionHeader(lines[index]) { index += 1 }

    var skills: [String] = []
    var remaining: [String] = []
    while index < lines.count {
        let line = lines[index]
        if ResumeSectionKit.isSectionHeader(line), line.trimmingCharacters(in: .whitespaces).uppercased().contains("SKILL") {
            index += 1
            while index < lines.count, !ResumeSectionKit.isSectionHeader(lines[index]) {
                for piece in lines[index].components(separatedBy: ",") {
                    let trimmed = piece.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { skills.append(trimmed) }
                }
                index += 1
            }
        } else {
            remaining.append(line)
            index += 1
        }
    }
    return ParsedResumeBody(name: name, role: role, contactLine: contactLine, skills: skills, remainingLines: remaining)
}

/// Renders plain text into a real multi-page PDF using CoreText/CoreGraphics directly, so it
/// works identically on iOS and macOS without any UIKit-only APIs (e.g. UIGraphicsPDFRenderer).
enum PDFDocumentRenderer {
    private static let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter, 72pt/in
    private static let margin: CGFloat = 40
    private static let fontAttributeKey = NSAttributedString.Key(kCTFontAttributeName as String)
    private static let colorAttributeKey = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
    private static let paragraphAttributeKey = NSAttributedString.Key(kCTParagraphStyleAttributeName as String)
    private static let whiteColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    private static let grayColor = CGColor.fromHex("808080")
    private static let darkColor = CGColor.fromHex("1A1A1A")

    private static func centeredParagraphStyle() -> CTParagraphStyle {
        var alignment = CTTextAlignment.center
        // `&alignment` inline in the array literal would only be valid for the duration of that
        // expression — the pointer stored in `settings` could already dangle by the time
        // CTParagraphStyleCreate reads it. Holding the pointer open across the call makes the
        // lifetime explicit instead of relying on stack layout happening to keep it alive.
        return withUnsafeMutablePointer(to: &alignment) { alignmentPointer in
            let settings = [
                CTParagraphStyleSetting(
                    spec: .alignment,
                    valueSize: MemoryLayout<CTTextAlignment>.size,
                    value: alignmentPointer
                )
            ]
            return CTParagraphStyleCreate(settings, settings.count)
        }
    }

    /// - Parameter style: the selected `ResumeTemplateStyle` — drives which structural layout is
    ///   used (sidebar / banner / flowing single column), not just the accent color, so the
    ///   export actually resembles the on-screen `ResumeTemplateCard` for that template.
    static func render(title: String, body: String, style: ResumeTemplateStyle = .modernEdge) -> Data {
        switch style.exportLayout {
        case .sidebar:
            return renderSidebarLayout(body: body, style: style)
        case .banner:
            return renderBannerLayout(body: body, style: style)
        case .flowing:
            return renderFlowingLayout(title: title, body: body, style: style)
        }
    }

    // MARK: - Flowing layout (Minimal Pro, Executive Suite)

    private static func renderFlowingLayout(title: String, body: String, style: ResumeTemplateStyle) -> Data {
        let accentColor = CGColor.fromHex(style.accentColorHex)
        let regularFontName = style.usesSerifFont ? "Times New Roman" : "Helvetica"
        let boldFontName = style.usesSerifFont ? "Times New Roman Bold" : "Helvetica-Bold"
        let textRect = pageRect.insetBy(dx: margin, dy: margin)

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return Data() }
        var mediaBox = pageRect
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }

        let attributed = NSMutableAttributedString()
        // `title` is a generic document-type label ("Resume", "Cover Letter"), not the
        // candidate's name — kept small/gray so it doesn't upstage the person's real name and
        // content.
        attributed.append(NSAttributedString(
            string: title + "\n\n",
            attributes: [fontAttributeKey: CTFontCreateWithName("Helvetica" as CFString, 9, nil), colorAttributeKey: grayColor]
        ))

        var reachedFirstHeader = false
        var isNameLine = true
        for line in body.components(separatedBy: "\n") {
            if ResumeSectionKit.isSectionHeader(line) {
                reachedFirstHeader = true
                attributed.append(NSAttributedString(
                    string: line + "\n",
                    attributes: [fontAttributeKey: CTFontCreateWithName(boldFontName as CFString, 13, nil), colorAttributeKey: accentColor]
                ))
            } else if !reachedFirstHeader, !line.trimmingCharacters(in: .whitespaces).isEmpty {
                var attributes: [NSAttributedString.Key: Any] = [:]
                if isNameLine {
                    attributes[fontAttributeKey] = CTFontCreateWithName(boldFontName as CFString, 20, nil)
                    attributes[colorAttributeKey] = darkColor
                    isNameLine = false
                } else {
                    attributes[fontAttributeKey] = CTFontCreateWithName(regularFontName as CFString, 12, nil)
                    attributes[colorAttributeKey] = grayColor
                }
                if style.centersHeaderBlock {
                    attributes[paragraphAttributeKey] = centeredParagraphStyle()
                }
                attributed.append(NSAttributedString(string: line + "\n", attributes: attributes))
            } else {
                attributed.append(NSAttributedString(
                    string: line + "\n",
                    attributes: [fontAttributeKey: CTFontCreateWithName(regularFontName as CFString, 11, nil)]
                ))
            }
        }

        drawFlowingPages(attributed, in: context, region: CGRect(origin: .zero, size: textRect.size), regionOrigin: CGPoint(x: margin, y: margin))
        context.closePDF()
        return data as Data
    }

    // MARK: - Sidebar layout (Modern Edge)

    private static func renderSidebarLayout(body: String, style: ResumeTemplateStyle) -> Data {
        let accentColor = CGColor.fromHex(style.accentColorHex)
        let parsed = parseResumeBody(body)
        let sidebarWidth: CGFloat = 190

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return Data() }
        var mediaBox = pageRect
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }

        let sidebarAttributed = NSMutableAttributedString()
        sidebarAttributed.append(NSAttributedString(
            string: "CONTACT\n",
            attributes: [fontAttributeKey: CTFontCreateWithName("Helvetica-Bold" as CFString, 11, nil), colorAttributeKey: whiteColor]
        ))
        for part in parsed.contactLine.components(separatedBy: "|") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            sidebarAttributed.append(NSAttributedString(
                string: trimmed + "\n",
                attributes: [fontAttributeKey: CTFontCreateWithName("Helvetica" as CFString, 10, nil), colorAttributeKey: whiteColor]
            ))
        }
        if !parsed.skills.isEmpty {
            sidebarAttributed.append(NSAttributedString(
                string: "\nTECHNICAL SKILLS\n",
                attributes: [fontAttributeKey: CTFontCreateWithName("Helvetica-Bold" as CFString, 11, nil), colorAttributeKey: whiteColor]
            ))
            for skill in parsed.skills {
                sidebarAttributed.append(NSAttributedString(
                    string: "• \(skill)\n",
                    attributes: [fontAttributeKey: CTFontCreateWithName("Helvetica" as CFString, 10, nil), colorAttributeKey: whiteColor]
                ))
            }
        }
        let sidebarFramesetter = CTFramesetterCreateWithAttributedString(sidebarAttributed)
        let sidebarPath = CGPath(rect: CGRect(x: 0, y: 0, width: sidebarWidth - 40, height: pageRect.height - margin * 2), transform: nil)

        let mainAttributed = NSMutableAttributedString()
        mainAttributed.append(NSAttributedString(
            string: parsed.name + "\n",
            attributes: [fontAttributeKey: CTFontCreateWithName("Helvetica-Bold" as CFString, 20, nil), colorAttributeKey: darkColor]
        ))
        if !parsed.role.isEmpty {
            mainAttributed.append(NSAttributedString(
                string: parsed.role + "\n\n",
                attributes: [fontAttributeKey: CTFontCreateWithName("Helvetica" as CFString, 12, nil), colorAttributeKey: grayColor]
            ))
        }
        appendBodyLines(parsed.remainingLines, to: mainAttributed, accentColor: accentColor, regularFontName: "Helvetica", boldFontName: "Helvetica-Bold")
        let mainFramesetter = CTFramesetterCreateWithAttributedString(mainAttributed)

        let mainX = sidebarWidth + 30
        let mainRegionSize = CGSize(width: pageRect.width - mainX - margin, height: pageRect.height - margin * 2)
        var currentIndex = 0
        let totalLength = mainAttributed.length

        // The colored sidebar (with the same Contact/Skills content) repeats on every page —
        // not just the first — so a resume long enough to overflow doesn't suddenly lose its
        // template identity on page 2 and beyond.
        repeat {
            context.beginPDFPage(nil)

            context.saveGState()
            context.setFillColor(accentColor)
            context.fill(CGRect(x: 0, y: 0, width: sidebarWidth, height: pageRect.height))
            context.restoreGState()

            context.saveGState()
            context.translateBy(x: 20, y: margin)
            let sidebarFrame = CTFramesetterCreateFrame(sidebarFramesetter, CFRange(location: 0, length: 0), sidebarPath, nil)
            CTFrameDraw(sidebarFrame, context)
            context.restoreGState()

            context.saveGState()
            context.translateBy(x: mainX, y: margin)
            let mainPath = CGPath(rect: CGRect(origin: .zero, size: mainRegionSize), transform: nil)
            let mainFrame = CTFramesetterCreateFrame(mainFramesetter, CFRange(location: currentIndex, length: 0), mainPath, nil)
            CTFrameDraw(mainFrame, context)
            let visibleRange = CTFrameGetVisibleStringRange(mainFrame)
            context.restoreGState()

            context.endPDFPage()
            currentIndex += max(visibleRange.length, 1)
        } while currentIndex < totalLength

        context.closePDF()
        return data as Data
    }

    // MARK: - Banner layout (Creative Bold)

    private static func renderBannerLayout(body: String, style: ResumeTemplateStyle) -> Data {
        let accentColor = CGColor.fromHex(style.accentColorHex)
        let parsed = parseResumeBody(body)
        let bannerHeight: CGFloat = parsed.role.isEmpty && parsed.contactLine.isEmpty ? 60 : 95

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return Data() }
        var mediaBox = pageRect
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }

        let bannerAttributed = NSMutableAttributedString()
        bannerAttributed.append(NSAttributedString(
            string: parsed.name + "\n",
            attributes: [fontAttributeKey: CTFontCreateWithName("Helvetica-Bold" as CFString, 22, nil), colorAttributeKey: whiteColor]
        ))
        if !parsed.role.isEmpty {
            bannerAttributed.append(NSAttributedString(
                string: parsed.role + "\n",
                attributes: [fontAttributeKey: CTFontCreateWithName("Helvetica" as CFString, 13, nil), colorAttributeKey: whiteColor]
            ))
        }
        if !parsed.contactLine.isEmpty {
            bannerAttributed.append(NSAttributedString(
                string: parsed.contactLine + "\n",
                attributes: [fontAttributeKey: CTFontCreateWithName("Helvetica" as CFString, 11, nil), colorAttributeKey: whiteColor]
            ))
        }
        let bannerFramesetter = CTFramesetterCreateWithAttributedString(bannerAttributed)
        let bannerPath = CGPath(rect: CGRect(x: 0, y: 0, width: pageRect.width - margin * 2, height: bannerHeight), transform: nil)

        let mainAttributed = NSMutableAttributedString()
        if !parsed.skills.isEmpty {
            mainAttributed.append(NSAttributedString(
                string: parsed.skills.joined(separator: "   •   ") + "\n\n",
                attributes: [fontAttributeKey: CTFontCreateWithName("Helvetica-Bold" as CFString, 11, nil), colorAttributeKey: accentColor]
            ))
        }
        appendBodyLines(parsed.remainingLines, to: mainAttributed, accentColor: accentColor, regularFontName: "Helvetica", boldFontName: "Helvetica-Bold")
        let mainFramesetter = CTFramesetterCreateWithAttributedString(mainAttributed)

        let mainRegionSize = CGSize(width: pageRect.width - margin * 2, height: pageRect.height - bannerHeight - margin * 2)
        var currentIndex = 0
        let totalLength = mainAttributed.length

        // The colored banner (with the same name/role/contact content) repeats on every page —
        // not just the first — so a resume long enough to overflow doesn't suddenly lose its
        // template identity on page 2 and beyond, matching the sidebar layout's behavior.
        repeat {
            context.beginPDFPage(nil)

            context.saveGState()
            context.setFillColor(accentColor)
            context.fill(CGRect(x: 0, y: pageRect.height - bannerHeight, width: pageRect.width, height: bannerHeight))
            context.restoreGState()

            context.saveGState()
            context.translateBy(x: margin, y: pageRect.height - bannerHeight)
            let bannerFrame = CTFramesetterCreateFrame(bannerFramesetter, CFRange(location: 0, length: 0), bannerPath, nil)
            CTFrameDraw(bannerFrame, context)
            context.restoreGState()

            context.saveGState()
            context.translateBy(x: margin, y: margin)
            let mainPath = CGPath(rect: CGRect(origin: .zero, size: mainRegionSize), transform: nil)
            let mainFrame = CTFramesetterCreateFrame(mainFramesetter, CFRange(location: currentIndex, length: 0), mainPath, nil)
            CTFrameDraw(mainFrame, context)
            let visibleRange = CTFrameGetVisibleStringRange(mainFrame)
            context.restoreGState()

            context.endPDFPage()
            currentIndex += max(visibleRange.length, 1)
        } while currentIndex < totalLength

        context.closePDF()
        return data as Data
    }

    // MARK: - Shared helpers

    private static func appendBodyLines(_ lines: [String], to attributed: NSMutableAttributedString, accentColor: CGColor, regularFontName: String, boldFontName: String) {
        for line in lines {
            if ResumeSectionKit.isSectionHeader(line) {
                attributed.append(NSAttributedString(
                    string: line + "\n",
                    attributes: [fontAttributeKey: CTFontCreateWithName(boldFontName as CFString, 13, nil), colorAttributeKey: accentColor]
                ))
            } else {
                attributed.append(NSAttributedString(
                    string: line + "\n",
                    attributes: [fontAttributeKey: CTFontCreateWithName(regularFontName as CFString, 11, nil)]
                ))
            }
        }
    }

    /// Draws `attributed` across as many pages as needed, using the same `region`/`regionOrigin`
    /// on every page. Used only by the flowing (single-column) layout — the sidebar and banner
    /// layouts draw their own colored region fresh on every page, so they loop independently.
    private static func drawFlowingPages(_ attributed: NSAttributedString, in context: CGContext, region: CGRect, regionOrigin: CGPoint) {
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        var currentIndex = 0
        let totalLength = attributed.length

        repeat {
            context.beginPDFPage(nil)
            context.saveGState()
            context.translateBy(x: regionOrigin.x, y: regionOrigin.y)
            let path = CGPath(rect: CGRect(origin: .zero, size: region.size), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: currentIndex, length: 0), path, nil)
            CTFrameDraw(frame, context)
            let visibleRange = CTFrameGetVisibleStringRange(frame)
            context.restoreGState()
            context.endPDFPage()

            currentIndex += max(visibleRange.length, 1)
        } while currentIndex < totalLength
    }
}

/// Builds a minimal but valid .docx (OOXML) file — a ZIP archive containing just the parts Word
/// requires (content types, root relationship, and the document body). No third-party libraries
/// are available for this on Apple platforms, so the ZIP container itself is hand-rolled below
/// using the "stored" (uncompressed) method, which keeps things simple while remaining spec-valid.
enum WordDocumentRenderer {
    private static func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func paragraph(_ text: String, font: String, sizeHalfPoints: Int, bold: Bool = false, color: String? = nil, centered: Bool = false) -> String {
        var rProps = "<w:rFonts w:ascii=\"\(font)\" w:hAnsi=\"\(font)\"/><w:sz w:val=\"\(sizeHalfPoints)\"/>"
        if bold { rProps += "<w:b/>" }
        if let color { rProps += "<w:color w:val=\"\(color)\"/>" }
        let pProps = centered ? "<w:pPr><w:jc w:val=\"center\"/></w:pPr>" : ""
        let run = "<w:r><w:rPr>\(rProps)</w:rPr><w:t xml:space=\"preserve\">\(escapeXML(text))</w:t></w:r>"
        return "<w:p>\(pProps)\(run)</w:p>"
    }

    private static func bodyParagraphs(_ lines: [String], font: String, accentColorHex: String) -> String {
        var result = ""
        for line in lines {
            if ResumeSectionKit.isSectionHeader(line) {
                result += paragraph(line, font: font, sizeHalfPoints: 26, bold: true, color: accentColorHex)
            } else {
                result += paragraph(line, font: font, sizeHalfPoints: 22)
            }
        }
        return result
    }

    /// - Parameter style: the selected `ResumeTemplateStyle` — drives which structural layout is
    ///   used (a shaded sidebar table, a shaded banner table, or a single flowing column), not
    ///   just the accent color, mirroring `ResumeTemplateCard`'s on-screen layout instead of
    ///   producing the same flat document for every template.
    static func render(title: String, body: String, style: ResumeTemplateStyle = .modernEdge) -> Data {
        let documentXML: String
        switch style.exportLayout {
        case .sidebar:
            documentXML = sidebarDocumentXML(title: title, body: body, style: style)
        case .banner:
            documentXML = bannerDocumentXML(title: title, body: body, style: style)
        case .flowing:
            documentXML = flowingDocumentXML(title: title, body: body, style: style)
        }

        let contentTypesXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        </Types>
        """

        let rootRelsXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """

        let entries: [(name: String, data: Data)] = [
            ("[Content_Types].xml", Data(contentTypesXML.utf8)),
            ("_rels/.rels", Data(rootRelsXML.utf8)),
            ("word/document.xml", Data(documentXML.utf8))
        ]
        return MinimalZipWriter.makeArchive(entries: entries)
    }

    // MARK: - Flowing layout (Minimal Pro, Executive Suite)

    /// Explicit US Letter page size with 1" margins.
    ///
    /// An empty `<w:sectPr/>` makes Word fall back to whatever its own default template says,
    /// which is A4 in most of the world. The layout tables below are hardcoded to 9360 twips —
    /// exactly Letter's 12240 minus two 1" margins — so on an A4 default (content width ~9026
    /// twips) the table overflows the right margin and the resume renders off the page. Stating
    /// the geometry makes the output identical everywhere, and matches `PDFDocumentRenderer`,
    /// which already hardcodes 612×792pt (Letter).
    private static let sectionProperties = """
    <w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" \
    w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>
    """

    private static func flowingDocumentXML(title: String, body: String, style: ResumeTemplateStyle) -> String {
        let font = style.usesSerifFont ? "Times New Roman" : "Calibri"
        // `title` is a generic document-type label ("Resume", "Cover Letter"), not the
        // candidate's name — kept small/gray so it doesn't upstage the person's real name.
        var paragraphs = paragraph(title, font: font, sizeHalfPoints: 18, color: "808080")

        var reachedFirstHeader = false
        var isNameLine = true
        for line in body.components(separatedBy: "\n") {
            if ResumeSectionKit.isSectionHeader(line) {
                reachedFirstHeader = true
                paragraphs += paragraph(line, font: font, sizeHalfPoints: 26, bold: true, color: style.accentColorHex)
            } else if !reachedFirstHeader, !line.trimmingCharacters(in: .whitespaces).isEmpty {
                if isNameLine {
                    paragraphs += paragraph(line, font: font, sizeHalfPoints: 40, bold: true, color: "1A1A1A", centered: style.centersHeaderBlock)
                    isNameLine = false
                } else {
                    paragraphs += paragraph(line, font: font, sizeHalfPoints: 24, color: "808080", centered: style.centersHeaderBlock)
                }
            } else {
                paragraphs += paragraph(line, font: font, sizeHalfPoints: 22)
            }
        }

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:body>\(paragraphs)\(sectionProperties)</w:body>
        </w:document>
        """
    }

    // MARK: - Sidebar layout (Modern Edge) — a borderless 2-column table

    private static func sidebarDocumentXML(title: String, body: String, style: ResumeTemplateStyle) -> String {
        let parsed = parseResumeBody(body)
        let font = "Calibri"

        var sidebarContent = paragraph("CONTACT", font: font, sizeHalfPoints: 20, bold: true, color: "FFFFFF")
        for part in parsed.contactLine.components(separatedBy: "|") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            sidebarContent += paragraph(trimmed, font: font, sizeHalfPoints: 18, color: "FFFFFF")
        }
        if !parsed.skills.isEmpty {
            sidebarContent += paragraph("", font: font, sizeHalfPoints: 18, color: "FFFFFF")
            sidebarContent += paragraph("TECHNICAL SKILLS", font: font, sizeHalfPoints: 20, bold: true, color: "FFFFFF")
            for skill in parsed.skills {
                sidebarContent += paragraph("• \(skill)", font: font, sizeHalfPoints: 18, color: "FFFFFF")
            }
        }

        var mainContent = paragraph(title, font: font, sizeHalfPoints: 18, color: "808080")
        mainContent += paragraph(parsed.name, font: font, sizeHalfPoints: 40, bold: true, color: "1A1A1A")
        if !parsed.role.isEmpty {
            mainContent += paragraph(parsed.role, font: font, sizeHalfPoints: 24, color: "808080")
        }
        mainContent += bodyParagraphs(parsed.remainingLines, font: font, accentColorHex: style.accentColorHex)

        // A single-row, two-column table with no borders and a shaded left cell is the standard
        // OOXML way to get a colored "sidebar" column — Word grows both cells to match whichever
        // is taller, so the shading naturally spans the full content height.
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:body>
        <w:tbl>
        <w:tblPr><w:tblW w:w="0" w:type="auto"/><w:tblBorders><w:top w:val="none"/><w:left w:val="none"/><w:bottom w:val="none"/><w:right w:val="none"/><w:insideH w:val="none"/><w:insideV w:val="none"/></w:tblBorders></w:tblPr>
        <w:tblGrid><w:gridCol w:w="2800"/><w:gridCol w:w="6560"/></w:tblGrid>
        <w:tr>
        <w:tc><w:tcPr><w:tcW w:w="2800" w:type="dxa"/><w:shd w:val="clear" w:color="auto" w:fill="\(style.accentColorHex)"/><w:tcMar><w:top w:w="200" w:type="dxa"/><w:left w:w="200" w:type="dxa"/><w:bottom w:w="200" w:type="dxa"/><w:right w:w="200" w:type="dxa"/></w:tcMar></w:tcPr>\(sidebarContent)</w:tc>
        <w:tc><w:tcPr><w:tcW w:w="6560" w:type="dxa"/><w:tcMar><w:top w:w="200" w:type="dxa"/><w:left w:w="200" w:type="dxa"/><w:bottom w:w="200" w:type="dxa"/><w:right w:w="200" w:type="dxa"/></w:tcMar></w:tcPr>\(mainContent)</w:tc>
        </w:tr>
        </w:tbl>
        <w:p/>
        \(sectionProperties)
        </w:body>
        </w:document>
        """
    }

    // MARK: - Banner layout (Creative Bold) — a shaded single-row, single-column table on top

    private static func bannerDocumentXML(title: String, body: String, style: ResumeTemplateStyle) -> String {
        let parsed = parseResumeBody(body)
        let font = "Calibri"

        var bannerContent = paragraph(parsed.name, font: font, sizeHalfPoints: 44, bold: true, color: "FFFFFF")
        if !parsed.role.isEmpty {
            bannerContent += paragraph(parsed.role, font: font, sizeHalfPoints: 26, color: "FFFFFF")
        }
        if !parsed.contactLine.isEmpty {
            bannerContent += paragraph(parsed.contactLine, font: font, sizeHalfPoints: 20, color: "FFFFFF")
        }

        var mainContent = paragraph(title, font: font, sizeHalfPoints: 18, color: "808080")
        if !parsed.skills.isEmpty {
            mainContent += paragraph(parsed.skills.joined(separator: "   •   "), font: font, sizeHalfPoints: 22, bold: true, color: style.accentColorHex)
        }
        mainContent += bodyParagraphs(parsed.remainingLines, font: font, accentColorHex: style.accentColorHex)

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:body>
        <w:tbl>
        <w:tblPr><w:tblW w:w="0" w:type="auto"/><w:tblBorders><w:top w:val="none"/><w:left w:val="none"/><w:bottom w:val="none"/><w:right w:val="none"/></w:tblBorders></w:tblPr>
        <w:tblGrid><w:gridCol w:w="9360"/></w:tblGrid>
        <w:tr>
        <w:tc><w:tcPr><w:tcW w:w="9360" w:type="dxa"/><w:shd w:val="clear" w:color="auto" w:fill="\(style.accentColorHex)"/><w:tcMar><w:top w:w="200" w:type="dxa"/><w:left w:w="200" w:type="dxa"/><w:bottom w:w="200" w:type="dxa"/><w:right w:w="200" w:type="dxa"/></w:tcMar></w:tcPr>\(bannerContent)</w:tc>
        </w:tr>
        </w:tbl>
        <w:p/>
        \(mainContent)
        \(sectionProperties)
        </w:body>
        </w:document>
        """
    }
}

/// A tiny ZIP writer supporting only the "stored" (uncompressed) method — sufficient for the
/// handful of small XML parts a minimal .docx needs, without depending on a compression library.
private enum MinimalZipWriter {
    static func makeArchive(entries: [(name: String, data: Data)]) -> Data {
        var body = Data()
        var centralDirectory = Data()
        var offset: UInt32 = 0

        for entry in entries {
            let nameBytes = Data(entry.name.utf8)
            let crc = crc32(entry.data)
            let size = UInt32(entry.data.count)

            var localHeader = Data()
            localHeader.appendLE(UInt32(0x0403_4b50))
            localHeader.appendLE(UInt16(20))
            localHeader.appendLE(UInt16(0))
            localHeader.appendLE(UInt16(0))
            localHeader.appendLE(UInt16(0))
            localHeader.appendLE(UInt16(0))
            localHeader.appendLE(crc)
            localHeader.appendLE(size)
            localHeader.appendLE(size)
            localHeader.appendLE(UInt16(nameBytes.count))
            localHeader.appendLE(UInt16(0))
            localHeader.append(nameBytes)

            body.append(localHeader)
            body.append(entry.data)

            var centralEntry = Data()
            centralEntry.appendLE(UInt32(0x0201_4b50))
            centralEntry.appendLE(UInt16(20))
            centralEntry.appendLE(UInt16(20))
            centralEntry.appendLE(UInt16(0))
            centralEntry.appendLE(UInt16(0))
            centralEntry.appendLE(UInt16(0))
            centralEntry.appendLE(UInt16(0))
            centralEntry.appendLE(crc)
            centralEntry.appendLE(size)
            centralEntry.appendLE(size)
            centralEntry.appendLE(UInt16(nameBytes.count))
            centralEntry.appendLE(UInt16(0))
            centralEntry.appendLE(UInt16(0))
            centralEntry.appendLE(UInt16(0))
            centralEntry.appendLE(UInt16(0))
            centralEntry.appendLE(UInt32(0))
            centralEntry.appendLE(offset)
            centralEntry.append(nameBytes)

            centralDirectory.append(centralEntry)
            offset += UInt32(localHeader.count + entry.data.count)
        }

        var end = Data()
        end.appendLE(UInt32(0x0605_4b50))
        end.appendLE(UInt16(0))
        end.appendLE(UInt16(0))
        end.appendLE(UInt16(entries.count))
        end.appendLE(UInt16(entries.count))
        end.appendLE(UInt32(centralDirectory.count))
        end.appendLE(offset)
        end.appendLE(UInt16(0))

        return body + centralDirectory + end
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1 != 0) ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return ~crc
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendLE(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
