import SwiftUI
import UniformTypeIdentifiers

/// Generic FileDocument for exporting raw bytes (a rendered PDF or .docx) via `.fileExporter`.
struct BinaryFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data, .pdf] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
