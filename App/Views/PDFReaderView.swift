import SwiftUI

#if canImport(PDFKit)
import PDFKit
#endif

/// Native PDF rendering via PDFKit's `PDFView` — continuous vertical scrolling
/// with auto-scaling, like Apple Books' PDF mode. Selection-based Ask and
/// highlights don't apply here; the text reading modes remain for EPUB/text.
struct PDFReaderView: View {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    var body: some View {
        #if canImport(PDFKit)
        PDFKitView(url: url)
        #else
        ContentUnavailableView("PDF rendering unavailable", systemImage: "doc.richtext")
        #endif
    }
}

#if canImport(PDFKit)
private func configure(_ view: PDFView) {
    view.autoScales = true
    view.displayMode = .singlePageContinuous
    view.displayDirection = .vertical
}

#if canImport(UIKit)
private struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        configure(view)
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        // Reload only when the URL actually changed — resetting the document
        // would jump the reader back to page 1 on every body evaluation.
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}
#elseif canImport(AppKit)
private struct PDFKitView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        configure(view)
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}
#endif
#endif
