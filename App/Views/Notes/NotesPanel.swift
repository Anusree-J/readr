import SwiftUI
import ReadrKit

/// Right-hand reader inspector (⌘⇧N): this book's annotations in reading
/// order, with one-click Markdown export and the Article studio a tap away.
/// This panel is the heart of the wedge over Apple Books — highlights stream
/// in as you make them and are never trapped (docs/DESIGN.md, "Notes panel").
struct NotesPanel: View {
    @EnvironmentObject private var model: AppModel
    let book: Book
    var onJumpHighlight: ((Highlight) -> Void)? = nil
    var onJumpPDF: ((PDFHighlight) -> Void)? = nil

    private var annotationCount: Int {
        model.highlights(for: book).count + model.pdfHighlights(for: book).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Notes")
                    .font(.title3.bold())
                if annotationCount > 0 {
                    Text("\(annotationCount)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            NotesHeaderActions(book: book)
            AnnotationListView(
                book: book,
                onJumpHighlight: onJumpHighlight,
                onJumpPDF: onJumpPDF
            )
        }
        .padding([.horizontal, .top], 12)
    }
}

/// The "Create Article" CTA + Markdown export menu, shared by the Notes panel
/// and the library "Highlights & Notes" review so both surfaces offer the same
/// two exits for annotations.
struct NotesHeaderActions: View {
    @EnvironmentObject private var model: AppModel
    let book: Book

    @State private var showStudio = false

    /// Nil when the book has no annotations (nothing to export).
    private var markdown: String? {
        model.annotationsMarkdown(for: book)
    }

    private var hasAnnotations: Bool {
        !model.highlights(for: book).isEmpty || !model.pdfHighlights(for: book).isEmpty
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                showStudio = true
            } label: {
                Label("Create Article", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
            .disabled(!hasAnnotations)
            .accessibilityIdentifier("notes.createArticle")
            .help("Compose an article from these highlights with AI")

            Menu {
                Button {
                    Pasteboard.copy(markdown ?? "")
                } label: {
                    Label("Copy Markdown", systemImage: "doc.on.doc")
                }
                ShareLink(item: markdown ?? "") {
                    Label("Share…", systemImage: "square.and.arrow.up")
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(markdown == nil)
            .accessibilityIdentifier("notes.exportMarkdown")
            .help("Export these highlights and notes as Markdown")
        }
        .sheet(isPresented: $showStudio) {
            ArticleStudioView(book: book)
                .environmentObject(model)
        }
    }
}
