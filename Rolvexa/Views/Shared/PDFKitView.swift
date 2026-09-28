import SwiftUI
import PDFKit

/// Renders an actual PDF with full visual fidelity (fonts, columns, images) — used when the
/// user chose to keep their originally uploaded resume as-is, since a plain-text reconstruction
/// can never reproduce the real layout.
#if os(iOS)
struct PDFKitView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document == nil {
            uiView.document = PDFDocument(data: data)
        }
    }
}
#else
struct PDFKitView: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(data: data)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document == nil {
            nsView.document = PDFDocument(data: data)
        }
    }
}
#endif
