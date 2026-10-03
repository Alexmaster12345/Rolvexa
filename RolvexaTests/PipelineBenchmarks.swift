import Foundation
import PDFKit
import Testing
import UIKit
@testable import Rolvexa

/// Timings for each stage of the on-device pipeline.
///
/// Gated behind an environment variable so a normal `xcodebuild test` — and therefore CI —
/// skips it. Benchmarks on a shared runner measure the runner, not the code, and the OCR stage
/// alone takes about a second per page.
///
///     RUN_BENCHMARKS=1 xcodebuild test \
///       -project Rolvexa.xcodeproj -scheme Rolvexa \
///       -only-testing:RolvexaTests/PipelineBenchmarks \
///       -destination 'platform=iOS,name=<your device>'
struct PipelineBenchmarks {
    static var enabled: Bool { ProcessInfo.processInfo.environment["RUN_BENCHMARKS"] != nil }

    // MARK: - Fixture

    /// A two-page resume with eight jobs — longer than typical, so the numbers are an upper
    /// bound rather than a best case.
    static let resumeText: String = {
        let jobs = (1...8).map { n in
            """

            Operations Manager \(n) | 201\(n % 9) – Present
            Acme Corporation \(n), Anytown, USA
            • Cut supplier onboarding time from 14 days to 5 across three regional sites
            • Renegotiated vendor contracts, lowering recurring spend by 18 percent
            • Introduced a shared reporting dashboard used by every department lead
            """
        }.joined()

        return """
        Jane Doe
        Operations Manager
        jane.doe@example.com | (555) 010-0100 | Anytown, USA

        ABOUT ME
        Operations manager with seven years running regional sites.

        PROFESSIONAL EXPERIENCE
        \(jobs)

        SKILLS
        Process Design, Vendor Management, Reporting, Budgeting, Python, SQL, Linux, Excel

        EDUCATION
        BSc Business Administration
        State University, Anytown, USA
        """
    }()

    static let jobPosting = """
    Senior Operations Manager — Initech. Own process design across regional sites, manage vendor
    relationships and compliance, build reporting with SQL and Python. Reporting and compliance
    are central to this operations role. Bachelor degree required. Linux and Excel useful.
    """

    private static func milliseconds(runs: Int = 10, _ block: () -> Void) -> Double {
        // One untimed pass so first-call setup isn't charged to the average.
        block()
        let start = Date()
        for _ in 0..<runs { block() }
        return Date().timeIntervalSince(start) * 1000 / Double(runs)
    }

    /// Collected rather than only printed: `print` from a test running on a physical device goes
    /// to the device console, not to xcodebuild's stdout, so the report is also written into the
    /// host app's container to be pulled off with `devicectl device copy from`.
    nonisolated(unsafe) private static var transcript: [String] = []

    private static func emit(_ line: String) {
        print(line)
        transcript.append(line)
    }

    private static func report(_ stage: String, _ value: Double, unit: String = "ms") {
        let padding = String(repeating: " ", count: max(1, 34 - stage.count))
        emit(String(format: "%@%@%8.2f %@", stage, padding, value, unit))
    }

    private static func writeTranscript() {
        guard let directory = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first else { return }
        let url = directory.appendingPathComponent("benchmarks.txt")
        try? transcript.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        print("[benchmarks] written to \(url.path)")
    }

    /// Physical memory footprint, which is what iOS actually terminates apps over.
    private static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    /// A rasterised page — what a photographed resume looks like to OCR.
    private static func scannedPageJPEG() -> Data {
        let pdf = PDFDocumentRenderer.render(title: "Resume", body: resumeText, style: .modernEdge)
        let page = PDFDocument(data: pdf)!.page(at: 0)!
        let bounds = page.bounds(for: .mediaBox)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(bounds)
            context.cgContext.translateBy(x: 0, y: bounds.height)
            context.cgContext.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
        return image.jpegData(compressionQuality: 0.85)!
    }

    // MARK: - Benchmarks

    @Test("Pipeline stage timings", .enabled(if: enabled))
    func measureEachStage() throws {
        let baseline = Self.footprintMB()
        let temporary = FileManager.default.temporaryDirectory

        let pdf = PDFDocumentRenderer.render(title: "Resume", body: Self.resumeText, style: .modernEdge)
        let pdfURL = temporary.appendingPathComponent("benchmark.pdf")
        try pdf.write(to: pdfURL)

        let docx = WordDocumentRenderer.render(title: "Resume", body: Self.resumeText, style: .modernEdge)
        let docxURL = temporary.appendingPathComponent("benchmark.docx")
        try docx.write(to: docxURL)

        let scan = Self.scannedPageJPEG()
        let pageCount = PDFDocument(data: pdf)?.pageCount ?? 0

        Self.emit("=== Rolvexa pipeline benchmarks ===")
        Self.emit("device: \(UIDevice.current.model), iOS \(UIDevice.current.systemVersion)")
        Self.emit("fixture: \(pageCount)-page resume · pdf \(pdf.count / 1024) KB · docx \(docx.count / 1024) KB · scan \(scan.count / 1024) KB")

        Self.report("PDF text extraction", Self.milliseconds {
            _ = ResumeTextExtraction.extractText(from: pdfURL, fileExtension: "pdf")
        })
        Self.report("DOCX extraction", Self.milliseconds {
            _ = ResumeTextExtraction.extractText(from: docxURL, fileExtension: "docx")
        })
        Self.report("Vision OCR + reading order", Self.milliseconds(runs: 3) {
            _ = ResumeTextExtraction.extractFromImageData(scan)
        })
        Self.report("Section + skill + keyword parse", Self.milliseconds(runs: 20) {
            _ = ResumeSectionKit.detectedSections(in: Self.resumeText)
            _ = ResumeSectionKit.extractSkills(from: Self.resumeText)
            _ = ResumeSectionKit.extractKeywords(from: Self.resumeText, limit: 20)
        })
        Self.report("Job-fit matching", Self.milliseconds(runs: 50) {
            _ = JobFitAnalyzer.analyze(
                jobDescription: Self.jobPosting,
                resumeText: Self.resumeText,
                resumeSkills: ["Python", "SQL"]
            )
        })
        Self.report("PDF rendering", Self.milliseconds(runs: 20) {
            _ = PDFDocumentRenderer.render(title: "Resume", body: Self.resumeText, style: .modernEdge)
        })
        Self.report("DOCX rendering", Self.milliseconds(runs: 20) {
            _ = WordDocumentRenderer.render(title: "Resume", body: Self.resumeText, style: .modernEdge)
        })

        let peak = Self.footprintMB()
        Self.emit(String(format: "memory: %.1f MB baseline -> %.1f MB peak (+%.1f MB)", baseline, peak, peak - baseline))
        Self.emit("model available: \(AppleIntelligenceResumeRewriter.isAvailable)")
        Self.writeTranscript()

        try? FileManager.default.removeItem(at: pdfURL)
        try? FileManager.default.removeItem(at: docxURL)
    }

    @Test("On-device model rewrite latency", .enabled(if: enabled && AppleIntelligenceResumeRewriter.isAvailable))
    func measureModelRewrite() async {
        let bullet = "Responsible for managing the deployment pipeline and helped with reducing release times by 40%."
        var timings: [Double] = []
        for _ in 0..<3 {
            let start = Date()
            _ = try? await AppleIntelligenceResumeRewriter.shared.rewrite(bulletLine: bullet)
            timings.append(Date().timeIntervalSince(start))
        }
        guard let fastest = timings.min() else { return }
        print(String(format: "\nmodel bullet rewrite: fastest %.2f s, median %.2f s (first call includes warm-up)",
                     fastest, timings.sorted()[timings.count / 2]))
    }
}
