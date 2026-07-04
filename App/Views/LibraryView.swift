import SwiftUI
import ReadrKit
import UniformTypeIdentifiers

/// The library shelf (J1): an Apple-Books-style grid of book covers with
/// drag-and-drop import alongside the file importer.
struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isImporting = false
    @State private var showSettings = false

    /// Formats Readr can currently import. EPUB/PDF are accepted here and will be
    /// handled by the Readium parser once that M1 increment lands.
    private var importTypes: [UTType] {
        [.plainText, .epub, .pdf, UTType("net.daringfireball.markdown") ?? .plainText]
    }

    private static let gridColumns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 24)
    ]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Library")
                .toolbar {
                    // Both directly visible: .secondaryAction collapses into an
                    // overflow menu on iOS, hiding the settings gear.
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            showSettings = true
                        } label: {
                            Label("AI Providers", systemImage: "gearshape")
                        }
                        .accessibilityLabel("AI providers")
                        Button {
                            isImporting = true
                        } label: {
                            Label("Import", systemImage: "plus")
                        }
                        .accessibilityLabel("Import book")
                    }
                }
                .sheet(isPresented: $showSettings) {
                    ProviderSettingsView(app: model)
                }
                .fileImporter(
                    isPresented: $isImporting,
                    allowedContentTypes: importTypes,
                    allowsMultipleSelection: false
                ) { result in
                    if case let .success(urls) = result, let url = urls.first {
                        Task { await model.importBook(at: url) }
                    }
                }
                .alert(
                    "Import failed",
                    isPresented: Binding(
                        get: { model.importError != nil },
                        set: { if !$0 { model.importError = nil } }
                    )
                ) {
                    Button("OK", role: .cancel) { model.importError = nil }
                } message: {
                    Text(model.importError ?? "")
                }
        }
        .tint(AppTheme.accent)
    }

    /// The shelf or the empty state, either way a drop target for book files
    /// dragged in from Finder/Files.
    private var content: some View {
        Group {
            if model.books.isEmpty {
                ContentUnavailableView(
                    "Your library is empty",
                    systemImage: "books.vertical",
                    description: Text("Drag a book here, or tap Import — EPUB, PDF, or text.")
                )
            } else {
                bookshelf
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dropDestination(for: URL.self) { urls, _ in
            Task {
                for url in urls {
                    await model.importBook(at: url)
                }
            }
            return true
        }
    }

    private var bookshelf: some View {
        ScrollView {
            LazyVGrid(columns: Self.gridColumns, spacing: 28) {
                ForEach(model.books) { book in
                    bookCell(for: book)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private func bookCell(for book: Book) -> some View {
        NavigationLink {
            ReaderView(book: book)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                BookCoverView(book: book)
                Text(book.metadata.title)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                if !book.metadata.authors.isEmpty {
                    Text(book.metadata.authors.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let progress = readingProgress(for: book) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(AppTheme.accent)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(book.metadata.title)
    }

    /// Fraction of the book read, based on the saved position's chapter index
    /// (chapter granularity is all the shelf needs). Nil when the book hasn't
    /// been opened yet, which hides the progress bar.
    private func readingProgress(for book: Book) -> Double? {
        guard let position = model.position(for: book) else { return nil }
        let chapterCount = max(book.chapters.count, 1)
        let fraction = Double(position.chapterIndex + 1) / Double(chapterCount)
        return min(max(fraction, 0), 1)
    }
}
