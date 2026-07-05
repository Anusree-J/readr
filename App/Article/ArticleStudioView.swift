import SwiftUI
import ReadrKit

/// The Article studio (docs/DESIGN.md): pick highlights (all pre-checked,
/// color-filterable) → optional guidance → Compose (streams) → editable
/// Markdown → Copy / Share / Export `.md`. Entry points: the Notes panel CTA,
/// the library "Highlights & Notes" section, and the book context menu.
struct ArticleStudioView: View {
    @EnvironmentObject private var model: AppModel
    let book: Book

    @StateObject private var article: ArticleViewModel
    @Environment(\.dismiss) private var dismiss

    /// Picker state. Selection is per annotation id; the color chips narrow
    /// both what's LISTED and what COMPOSES, so the article never quietly
    /// includes items the reader filtered out of sight.
    @State private var selectedIDs: Set<UUID> = []
    @State private var activeColors = Set(HighlightColor.allCases)
    @State private var didPreselect = false
    @State private var guidance = ""
    @State private var showExporter = false
    @State private var showProviders = false

    init(book: Book) {
        self.book = book
        _article = StateObject(wrappedValue: ArticleViewModel(book: book))
    }

    private var allItems: [AnnotationItem] {
        AnnotationItem.readingOrder(
            book: book,
            highlights: model.highlights(for: book),
            pdfHighlights: model.pdfHighlights(for: book)
        )
    }

    private var visibleItems: [AnnotationItem] {
        allItems.filter { activeColors.contains($0.color) }
    }

    private var composeSelection: [AnnotationItem] {
        visibleItems.filter { selectedIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(article.markdown.isEmpty ? "Article Studio" : article.title)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { toolbarContent }
                .fileExporter(
                    isPresented: $showExporter,
                    document: MarkdownDocument(text: article.markdown),
                    contentType: MarkdownDocument.markdownType,
                    defaultFilename: exportFilename
                ) { result in
                    if case .failure(let error) = result {
                        article.errorMessage = error.localizedDescription
                    }
                }
        }
        .onAppear {
            // Pre-check everything exactly once; later model changes (deletes,
            // recolors) must not silently re-check what the reader unchecked.
            guard !didPreselect else { return }
            didPreselect = true
            selectedIDs = Set(allItems.map(\.id))
        }
        .onDisappear { article.cancelComposing() }
        #if os(macOS)
        .frame(minWidth: 620, idealWidth: 700, minHeight: 540, idealHeight: 640)
        #endif
    }

    // MARK: Phases

    @ViewBuilder
    private var content: some View {
        if article.isComposing {
            // While streaming, the text stays read-only so user edits can't
            // interleave with (or be wiped by) incoming deltas.
            ScrollView {
                Text(article.markdown.isEmpty ? "Composing your article…" : article.markdown)
                    .font(.body)
                    .foregroundStyle(article.markdown.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        } else if !article.markdown.isEmpty {
            editor
        } else if model.activeProvider() == nil {
            noProvider
        } else if allItems.isEmpty {
            ContentUnavailableView {
                Label("No highlights yet", systemImage: "highlighter")
            } description: {
                Text("Highlight passages in the book first — the studio turns them into an article.")
            }
        } else {
            picker
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
        }
        if !article.isComposing && !article.markdown.isEmpty {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    startCompose()
                } label: {
                    Label("Recompose", systemImage: "arrow.clockwise")
                }
                .help("Compose again from the same highlights (replaces this text)")
                Button {
                    Pasteboard.copy(article.markdown)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .help("Copy the article as Markdown")
                ShareLink(item: article.markdown)
                Button {
                    showExporter = true
                } label: {
                    Label("Export .md", systemImage: "square.and.arrow.down")
                }
                .help("Save the article as a Markdown file")
            }
        }
    }

    // MARK: Picker

    private var picker: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Create an article from your notes")
                    .font(.title3.bold())
                    .fontDesign(.serif)
                Text(book.metadata.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                HighlightColorChips(active: $activeColors)
                Spacer()
                Text("\(composeSelection.count) of \(visibleItems.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("All") { selectedIDs.formUnion(visibleItems.map(\.id)) }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(AppTheme.accent)
                Button("None") { selectedIDs.subtract(visibleItems.map(\.id)) }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(AppTheme.accent)
            }

            List {
                ForEach(visibleItems) { item in
                    pickerRow(item)
                }
            }
            .listStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            TextField("What should the article emphasize? (optional)", text: $guidance, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)

            if let error = article.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button(action: startCompose) {
                Label("Compose", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
            .controlSize(.large)
            .disabled(composeSelection.isEmpty)
            .accessibilityIdentifier("article.compose")
        }
        .padding()
    }

    private func pickerRow(_ item: AnnotationItem) -> some View {
        let isSelected = selectedIDs.contains(item.id)
        return Button {
            if isSelected {
                selectedIDs.remove(item.id)
            } else {
                selectedIDs.insert(item.id)
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AppTheme.accent : Color.secondary)
                    .padding(.top, 1)
                Circle()
                    .fill(ReadingTheme.markerSwatch(item.color))
                    .frame(width: 9, height: 9)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.quotedText)
                        .font(.callout)
                        .fontDesign(.serif)
                        .italic()
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    if let note = item.note, !note.isEmpty {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Text(item.locator(in: book))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Editor

    private var editor: some View {
        VStack(spacing: 0) {
            TextEditor(text: $article.markdown)
                .font(.body)
                .padding()
            if let error = article.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding([.horizontal, .bottom])
            }
        }
    }

    // MARK: Provider empty state

    private var noProvider: some View {
        ContentUnavailableView {
            Label("No AI provider connected", systemImage: "sparkles")
        } description: {
            Text("Add an API key, sign in, or pick a local model to compose articles from your highlights.")
        } actions: {
            Button("Open AI Providers") { showProviders = true }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
        }
        .sheet(isPresented: $showProviders) {
            ProviderSettingsView(app: model)
                .environmentObject(model)
        }
    }

    // MARK: Compose

    private func startCompose() {
        article.startComposing(
            highlights: composeSelection.map(Self.composerHighlight(for:)),
            guidance: guidance,
            provider: model.activeProvider()
        )
    }

    /// The composer only understands text `Highlight`s, so PDF annotations are
    /// bridged into synthetic ones: an unknown chapterID sorts them after the
    /// text highlights and `range.lowerBound = pageIndex` keeps them in page
    /// order — matching the reading order shown in the picker (see
    /// `LLMArticleComposer.orderedHighlights`).
    private static func composerHighlight(for item: AnnotationItem) -> Highlight {
        switch item {
        case .text(let highlight):
            return highlight
        case .pdf(let highlight):
            return Highlight(
                id: highlight.id,
                bookID: highlight.bookID,
                chapterID: highlight.id, // deliberately not a real chapter
                range: highlight.pageIndex..<(highlight.pageIndex + 1),
                quotedText: highlight.quotedText,
                note: highlight.note,
                createdAt: highlight.createdAt,
                color: highlight.color
            )
        }
    }

    // MARK: Export

    /// "/" and ":" break save panels/Finder; anything else in a title is fine.
    private var exportFilename: String {
        let safeTitle = book.metadata.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: " -")
        return "Notes on \(safeTitle)"
    }
}
