import Foundation
import PDFKit
import UIKit
import Testing
@testable import Rolvexa

/// PDF and Word generation. These assert the properties that kept regressing by hand: nothing
/// from the resume going missing, nothing appearing twice, and the `.docx` staying a package
/// Word will actually open.
struct DocumentExporterTests {
    // MARK: - Fixtures

    static let allStyles: [ResumeTemplateStyle] = [.modernEdge, .minimalPro, .creativeBold, .executiveSuite]

    static let resumeBody = """
    Priya Singh
    Facility Property Manager
    priya@example.com | (123) 456-7890 | San Jose, CA | linkedin.com/in/priyasingh

    ABOUT ME
    Facility property manager with seven years maintaining corporate campuses.

    PROFESSIONAL EXPERIENCE
    Facility Property Manager | Feb 2017 – Present
    Silicon Valley Tech Park, San Jose, CA
    • Cut unplanned downtime by 30%
    • Lowered maintenance costs by 12%

    Assistant Facilities Manager | Jul 2013 – Jan 2017
    Bay Area Business Center, Oakland, CA
    • Coordinated building services across five office towers

    SKILLS
    Preventive Maintenance, Vendor Negotiation, CAFM Software, OSHA Compliance

    EDUCATION
    Bachelor's Degree in Mechanical Engineering
    San Jose State University, San Jose, CA
    May 2013
    """

    /// Every distinct value a reader must still be able to find in the output.
    static let expectedContent = [
        "Priya Singh", "Facility Property Manager", "priya@example.com", "(123) 456-7890",
        "San Jose, CA", "linkedin.com/in/priyasingh",
        "Preventive Maintenance", "Vendor Negotiation", "CAFM Software", "OSHA Compliance",
        "Feb 2017", "Present", "Silicon Valley Tech Park", "Cut unplanned downtime by 30%",
        "Assistant Facilities Manager", "Bay Area Business Center", "Oakland, CA",
        "five office towers", "Bachelor's Degree in Mechanical Engineering",
        "San Jose State University", "May 2013"
    ]

    /// Collapses whitespace: PDF extraction inserts newlines at line wraps, so a value split
    /// across two lines is still present even though a plain `contains` would miss it.
    private static func flattened(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func pdfText(_ data: Data) -> String {
        guard let document = PDFDocument(data: data) else { return "" }
        return (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
    }

    private static func docxPart(_ name: String, from archive: Data) -> String? {
        MinimalZipReader.extract(entryName: name, from: archive)
            .flatMap { String(data: $0, encoding: .utf8) }
    }

    /// The visible text of a .docx, read out of its `<w:t>` runs.
    private static func docxText(_ archive: Data) -> String {
        guard let xml = docxPart("word/document.xml", from: archive) else { return "" }
        var output = ""
        var remainder = Substring(xml)
        while let open = remainder.range(of: "<w:t"),
              let tagEnd = remainder[open.upperBound...].firstIndex(of: ">") {
            let contentStart = remainder.index(after: tagEnd)
            guard let close = remainder[contentStart...].range(of: "</w:t>") else { break }
            output += remainder[contentStart..<close.lowerBound] + "\n"
            remainder = remainder[close.upperBound...]
        }
        return output
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    // MARK: - Content parity

    @Test("No resume content is lost in the PDF", arguments: allStyles)
    func pdfKeepsEverything(style: ResumeTemplateStyle) {
        let text = Self.flattened(Self.pdfText(
            PDFDocumentRenderer.render(title: "Resume", body: Self.resumeBody, style: style)
        ))
        let missing = Self.expectedContent.filter { !text.contains(Self.flattened($0)) }
        #expect(missing.isEmpty, "\(style) PDF dropped \(missing)")
    }

    @Test("No resume content is lost in the Word file", arguments: allStyles)
    func wordKeepsEverything(style: ResumeTemplateStyle) {
        let text = Self.flattened(Self.docxText(
            WordDocumentRenderer.render(title: "Resume", body: Self.resumeBody, style: style)
        ))
        let missing = Self.expectedContent.filter { !text.contains(Self.flattened($0)) }
        #expect(missing.isEmpty, "\(style) .docx dropped \(missing)")
    }

    @Test("Contact details appear once, not once per page", arguments: allStyles)
    func contactBlockIsNotRepeated(style: ResumeTemplateStyle) {
        // The sidebar and banner layouts redraw their coloured region on every page. Redrawing
        // its *contents* too reprinted the whole contact block on page two.
        let long = Self.resumeBody + "\n\n" + (1...12).map {
            "Senior Analyst \($0) | 2010 – 2011\nAllsafe\n• Hardened production systems and cut response time."
        }.joined(separator: "\n\n")

        let data = PDFDocumentRenderer.render(title: "Resume", body: long, style: style)
        let document = PDFDocument(data: data)
        let text = Self.flattened(Self.pdfText(data))
        #expect((document?.pageCount ?? 0) > 1, "fixture should overflow one page")
        for value in ["priya@example.com", "(123) 456-7890", "linkedin.com/in/priyasingh"] {
            #expect(text.components(separatedBy: value).count - 1 == 1, "\(style) repeated \(value)")
        }
    }

    @Test("Every skill reaches the output, not just the first few", arguments: allStyles)
    func allSkillsAreExported(style: ResumeTemplateStyle) {
        let pdf = Self.flattened(Self.pdfText(
            PDFDocumentRenderer.render(title: "Resume", body: Self.resumeBody, style: style)
        ))
        for skill in ["Preventive Maintenance", "Vendor Negotiation", "CAFM Software", "OSHA Compliance"] {
            #expect(pdf.contains(Self.flattened(skill)), "\(style) dropped \(skill)")
        }
    }

    // MARK: - Word package validity

    @Test("The .docx is a package Word can open", arguments: allStyles)
    func docxPackageIsWellFormed(style: ResumeTemplateStyle) throws {
        let archive = WordDocumentRenderer.render(title: "Resume", body: Self.resumeBody, style: style)
        for part in ["[Content_Types].xml", "_rels/.rels", "word/document.xml"] {
            let contents = try #require(Self.docxPart(part, from: archive), "missing \(part)")
            let parser = XMLParser(data: Data(contents.utf8))
            #expect(parser.parse(), "\(part) is not well-formed XML in \(style)")
        }
    }

    @Test("Letter page size is stated explicitly rather than left to Word's default")
    func docxStatesPageSize() throws {
        // An empty sectPr makes Word fall back to A4 in most of the world, and the layout
        // tables are hardcoded to Letter's content width.
        let xml = try #require(Self.docxPart(
            "word/document.xml",
            from: WordDocumentRenderer.render(title: "Resume", body: Self.resumeBody, style: .modernEdge)
        ))
        #expect(xml.contains("w:w=\"12240\""))
        #expect(xml.contains("w:h=\"15840\""))
    }

    @Test("XML-hostile characters are escaped, not emitted raw")
    func specialCharactersAreEscaped() throws {
        let body = """
        A&B <Smith> "Quoted"
        R&D <Lead>

        SKILLS
        C++ & C#, <scripting>
        """
        let archive = WordDocumentRenderer.render(title: "Resume", body: body, style: .modernEdge)
        let xml = try #require(Self.docxPart("word/document.xml", from: archive))
        #expect(XMLParser(data: Data(xml.utf8)).parse())

        let text = Self.docxText(archive)
        #expect(text.contains("A&B <Smith>"))
        #expect(text.contains("C++ & C#"))
    }

    // MARK: - Photos

    @Test("A photo is embedded as a real image part with a resolvable relationship")
    func photoIsEmbeddedInDocx() throws {
        let photo = try #require(Self.sampleSquarePhoto())
        let archive = WordDocumentRenderer.render(
            title: "Resume", body: Self.resumeBody, style: .modernEdge, photoData: photo
        )
        #expect(MinimalZipReader.extract(entryName: "word/media/photo.jpeg", from: archive) != nil)

        let rels = try #require(Self.docxPart("word/_rels/document.xml.rels", from: archive))
        let xml = try #require(Self.docxPart("word/document.xml", from: archive))
        let types = try #require(Self.docxPart("[Content_Types].xml", from: archive))

        #expect(rels.contains("rIdPhoto"), "relationship part must define the id the drawing uses")
        #expect(xml.contains("r:embed=\"rIdPhoto\""))
        #expect(xml.contains("prst=\"ellipse\""), "the circle comes from the shape preset")
        #expect(types.contains("Extension=\"jpeg\""), "Word rejects undeclared part types")
    }

    @Test("Layouts with no sidebar don't drag the image into the package")
    func photoIsOmittedWhereThereIsNowhereToPutIt() throws {
        let photo = try #require(Self.sampleSquarePhoto())
        for style in [ResumeTemplateStyle.minimalPro, .executiveSuite, .creativeBold] {
            let archive = WordDocumentRenderer.render(
                title: "Resume", body: Self.resumeBody, style: style, photoData: photo
            )
            #expect(
                MinimalZipReader.extract(entryName: "word/media/photo.jpeg", from: archive) == nil,
                "\(style) embedded a photo it has no place to render"
            )
        }
    }

    @Test("Without a photo the package declares no image parts")
    func noPhotoMeansNoImageParts() {
        let archive = WordDocumentRenderer.render(title: "Resume", body: Self.resumeBody, style: .modernEdge)
        #expect(MinimalZipReader.extract(entryName: "word/media/photo.jpeg", from: archive) == nil)
        #expect(MinimalZipReader.extract(entryName: "word/_rels/document.xml.rels", from: archive) == nil)
    }

    // MARK: - Shape

    @Test("A short resume is one page and a long one paginates", arguments: allStyles)
    func paginationFollowsContent(style: ResumeTemplateStyle) {
        let short = PDFDocument(data: PDFDocumentRenderer.render(
            title: "Resume", body: Self.resumeBody, style: style
        ))
        #expect(short?.pageCount == 1)

        let long = Self.resumeBody + "\n\n" + (1...30).map {
            "Role \($0) | 2010\nCompany\n• Did a substantial amount of measurable work here."
        }.joined(separator: "\n\n")
        let paginated = PDFDocument(data: PDFDocumentRenderer.render(
            title: "Resume", body: long, style: style
        ))
        #expect((paginated?.pageCount ?? 0) > 1)
    }

    @Test("An empty body still produces a valid, openable file", arguments: allStyles)
    func emptyBodyDoesNotCrash(style: ResumeTemplateStyle) throws {
        let pdf = PDFDocumentRenderer.render(title: "Resume", body: "", style: style)
        #expect(PDFDocument(data: pdf) != nil)

        let archive = WordDocumentRenderer.render(title: "Resume", body: "", style: style)
        let xml = try #require(Self.docxPart("word/document.xml", from: archive))
        #expect(XMLParser(data: Data(xml.utf8)).parse())
    }

    // MARK: - Helper

    private static func sampleSquarePhoto() -> Data? {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        }
        return image.jpegData(compressionQuality: 0.8).flatMap(ResumePhoto.prepare(from:))
    }
}