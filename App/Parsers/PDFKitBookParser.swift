#if canImport(PDFKit)
import Foundation
import PDFKit
import ReadrKit

/// PDF import via Apple's PDFKit — no third-party dependency. Extracts text one
/// chapter per page (a coarse but real first cut; the Readium-backed parser will
/// add proper outline/TOC-aware chaptering). Encrypted/locked PDFs are rejected.
struct PDFKitBookParser: BookParser {
    func canParse(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "pdf"
    }

    func parse(_ url: URL) async throws -> Book {
        guard let document = PDFDocument(url: url) else {
            throw BookParserError.corrupted("could not open PDF")
        }
        if document.isEncrypted && document.isLocked {
            throw BookParserError.drmProtected
        }

        var chapters: [Chapter] = []
        var fullText = ""
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index), let text = page.string else { continue }
            fullText += text + "\n"
            chapters.append(Chapter(title: "Page \(index + 1)", order: chapters.count, text: text))
        }
        guard !chapters.isEmpty else {
            throw BookParserError.corrupted("no extractable text — this may be a scanned PDF")
        }

        let title = (document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? url.deletingPathExtension().lastPathComponent
        let author = document.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String
        let toc = chapters.compactMap { chapter in
            chapter.title.map { TOCEntry(title: $0, chapterIndex: chapter.order) }
        }
        let metadata = BookMetadata(
            title: title,
            authors: author.map { [$0] } ?? [],
            tableOfContents: toc
        )
        return Book(
            metadata: metadata,
            chapters: chapters,
            estimatedTokenCount: estimateTokens(fullText)
        )
    }
}
#endif
