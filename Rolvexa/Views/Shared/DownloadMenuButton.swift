import SwiftUI
import UniformTypeIdentifiers

enum ExportFormat: CaseIterable {
    case pdf, word

    var fileExtension: String { self == .pdf ? "pdf" : "docx" }
    var contentType: UTType { self == .pdf ? .pdf : (UTType(filenameExtension: "docx") ?? .data) }
    var label: String { self == .pdf ? "Download as PDF" : "Download as Word" }
    var icon: String { self == .pdf ? "doc.richtext" : "doc.text" }
}

/// Self-contained "download" control: shows a menu offering PDF or Word, renders the chosen
/// format on demand, and presents the system save sheet — usable as a drop-in button anywhere
/// in the app that needs to let someone export a piece of generated text.
struct DownloadMenuButton: View {
    let documentTitle: String
    let baseFilename: String
    let textProvider: () -> String
    var label: AnyView = AnyView(
        Image(systemName: "arrow.down.circle.fill").foregroundStyle(Color.indigo)
    )
    /// When set and its extension matches the requested export format, these exact bytes are
    /// used instead of regenerating the file from text — preserves a real uploaded file's
    /// actual layout instead of re-flowing a plain-text reconstruction of it.
    var originalFileData: Data? = nil
    var originalFileExtension: String? = nil
    /// When set, skips the PDF/Word choice menu and exports directly in this format.
    var fixedFormat: ExportFormat? = nil
    /// The selected `ResumeTemplateStyle`, so a regenerated (non-original) export actually
    /// resembles whichever template was picked (font, name emphasis, alignment, accent color)
    /// instead of every template producing an identical document.
    var style: ResumeTemplateStyle = .modernEdge

    @State private var isExporting = false
    @State private var exportFilename = "Export.pdf"
    @State private var exportContentType: UTType = .pdf
    @State private var exportData = Data()

    var body: some View {
        Group {
            if let fixedFormat {
                Button {
                    export(format: fixedFormat)
                } label: {
                    label
                }
            } else {
                Menu {
                    ForEach(ExportFormat.allCases, id: \.fileExtension) { format in
                        Button {
                            export(format: format)
                        } label: {
                            Label(format.label, systemImage: format.icon)
                        }
                    }
                } label: {
                    label
                }
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: BinaryFileDocument(data: exportData),
            contentType: exportContentType,
            defaultFilename: exportFilename
        ) { _ in }
    }

    private func export(format: ExportFormat) {
        if let originalFileData, originalFileExtension == format.fileExtension {
            exportData = originalFileData
        } else {
            let text = textProvider()
            exportData = format == .pdf
                ? PDFDocumentRenderer.render(title: documentTitle, body: text, style: style)
                : WordDocumentRenderer.render(title: documentTitle, body: text, style: style)
        }
        exportFilename = "\(baseFilename).\(format.fileExtension)"
        exportContentType = format.contentType
        isExporting = true
    }
}
