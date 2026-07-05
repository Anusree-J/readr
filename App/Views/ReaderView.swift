import SwiftUI
import ReadrKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The reader window (v2): a themed reading surface with TOC / bookmarks /
/// in-book search navigation, an Appearance popover, select-to-annotate (the
/// popover lives in `SelectableTextView`), the Ask panel, and the Notes
/// inspector. PDFs render natively via `PDFReaderView` — which brings its own
/// nav toolbar (TOC/thumbnails/search/bookmark) — unless the reader switches
/// to the extracted-text "Reading view" in Appearance.
struct ReaderView: View {
    @EnvironmentObject private var model: AppModel
    let book: Book

    @State private var chapterIndex = 0
    /// Reading anchor (character offset into the current chapter) in paged
    /// layouts — drives position persistence, bookmark anchors, and
    /// programmatic jumps. Scroll mode anchors to the chapter start.
    @State private var pagedAnchor = 0
    @State private var didRestorePosition = false
    @State private var askSelection: Selection?
    @State private var showAsk = false
    @State private var showNotes = false
    @State private var showTOC = false
    @State private var showSearch = false
    @State private var showAppearance = false
    /// Highlight whose note is being edited; drives the NoteEditor sheet.
    @State private var editingNote: Highlight?
    @State private var noteDraft = ""

    /// Persisted reading layout: continuous scroll, one page, or facing pages.
    @AppStorage("readerLayout") private var layoutRaw = PageLayout.scroll.rawValue
    /// Persisted appearance: reading theme (Paper/Sepia/Night) and text size.
    @AppStorage("readingTheme") private var themeRaw = ReadingTheme.paper.rawValue
    @AppStorage("readingFontSize") private var fontSize = 18.0
    /// PDFs: show the original pages (native PDFKit) or the extracted text
    /// (which keeps text-mode highlights and layouts available).
    @AppStorage("pdfShowsOriginal") private var pdfShowsOriginal = true

    private var layout: PageLayout {
        PageLayout(rawValue: layoutRaw) ?? .scroll
    }

    /// Everything the text renderer needs, derived from the persisted
    /// appearance settings (clamped in case stored values drift out of range).
    private var style: ReaderStyle {
        ReaderStyle(
            theme: ReadingTheme(rawValue: themeRaw) ?? .paper,
            fontSize: min(
                max(CGFloat(fontSize), ReaderStyle.fontSizeRange.lowerBound),
                ReaderStyle.fontSizeRange.upperBound
            )
        )
    }

    /// True while the native PDF view is on screen. It supplies its own
    /// TOC/search/bookmark toolbar, so the text-mode items step aside and the
    /// chapter chevrons disable (PDF pages, not chapters, are the unit there).
    private var isPDFOriginal: Bool {
        pdfShowsOriginal && model.isPDF(book) && model.sourceURL(for: book) != nil
    }

    private var chapter: Chapter? {
        guard book.chapters.indices.contains(chapterIndex) else { return nil }
        return book.chapters[chapterIndex]
    }

    var body: some View {
        content
            .navigationTitle(book.metadata.title)
            #if os(macOS)
            // Toolbar center per spec: book title · chapter title.
            .navigationSubtitle(chapter?.title ?? "")
            #else
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
            .background(hiddenFontShortcuts)
            .sheet(isPresented: $showAsk) {
                AskPanelView(app: model, book: book, selection: askSelection)
                    .environmentObject(model)
            }
            .sheet(item: $editingNote) { highlight in
                NoteEditor(quotedText: highlight.quotedText, text: $noteDraft) {
                    var updated = highlight
                    let trimmed = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    updated.note = trimmed.isEmpty ? nil : trimmed
                    model.updateHighlight(updated)
                }
            }
            .inspector(isPresented: $showNotes) {
                NotesPanel(
                    book: book,
                    onJumpHighlight: { highlight in
                        guard let index = book.chapters.firstIndex(
                            where: { $0.id == highlight.chapterID }
                        ) else { return }
                        jump(toChapter: index, offset: highlight.range.lowerBound)
                    },
                    // Jumping to a PDF page needs a page binding into
                    // PDFReaderView; v2 ships without one.
                    onJumpPDF: nil
                )
                .inspectorColumnWidth(min: 280, ideal: 340, max: 480)
            }
            .onAppear(perform: restoreOnce)
            .onChange(of: chapterIndex) { _, newValue in
                model.savePosition(
                    ReadingPosition(chapterIndex: newValue, characterOffset: pagedAnchor),
                    for: book
                )
            }
            .onChange(of: pagedAnchor) { _, newValue in
                // Persist every page turn — turns are user-paced and the store
                // is cheap JSON, so no debounce is needed (never per-frame).
                model.savePosition(
                    ReadingPosition(chapterIndex: chapterIndex, characterOffset: newValue),
                    for: book
                )
            }
            // Build the retrieval index in the background when the book opens
            // so the first "ask" is fast. Safe to call repeatedly.
            .task(id: book.id) { await model.ensureIndexed(book) }
    }

    // MARK: - Reading surface

    private var content: some View {
        Group {
            if let url = model.sourceURL(for: book), model.isPDF(book), pdfShowsOriginal {
                PDFReaderView(book: book, url: url, onAsk: { selection in
                    askSelection = selection
                    showAsk = true
                })
            } else if let chapter {
                readingSurface(for: chapter)
            } else {
                ContentUnavailableView("No readable content", systemImage: "doc")
            }
        }
    }

    private func readingSurface(for chapter: Chapter) -> some View {
        let images = model.inlineImages(for: book, chapter: chapter)
        let spans = highlightSpans(for: chapter)
        return VStack(spacing: 0) {
            if let title = chapter.title {
                Text(title)
                    .font(.title3.bold())
                    .fontDesign(.serif)
                    .foregroundStyle(style.theme.inkColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top)
            }
            if layout == .scroll {
                SelectableTextView(
                    text: chapter.text,
                    highlights: spans,
                    style: style,
                    inlineImages: images,
                    onAnnotate: { target, action in
                        handleAnnotation(in: chapter, target: target, action: action)
                    }
                )
                .padding()
                scrollFooter(for: chapter)
            } else {
                // Paged modes draw their own footer (page x of y · min left +
                // page arrows) because pagination happens inside the view.
                PagedChapterView(
                    chapter: chapter,
                    layout: layout,
                    style: style,
                    highlights: spans,
                    inlineImages: images,
                    anchorOffset: $pagedAnchor,
                    onAnnotate: { target, action in
                        handleAnnotation(in: chapter, target: target, action: action)
                    }
                )
            }
        }
        // The theme owns the entire surface, footer included.
        .background(style.theme.background.ignoresSafeArea())
    }

    /// Scroll mode has no page anchor, so the estimate covers the whole
    /// chapter (see docs/DESIGN.md — "in scroll mode base it on chapter start").
    private func scrollFooter(for chapter: Chapter) -> some View {
        let minutes = ReadingTimeEstimator().minutesLeft(
            inChapterText: chapter.text, fromCharacterOffset: 0
        )
        return Text(minutes > 0 ? "~\(minutes) min left in chapter" : "")
            .font(.footnote)
            .foregroundStyle(style.theme.inkColor.opacity(0.55))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { jump(toChapter: chapterIndex - 1) } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityIdentifier("prevChapter")
            .accessibilityLabel("Previous chapter")
            .help("Previous chapter")
            .disabled(chapterIndex == 0 || isPDFOriginal)

            Button { jump(toChapter: chapterIndex + 1) } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityIdentifier("nextChapter")
            .accessibilityLabel("Next chapter")
            .help("Next chapter")
            .disabled(chapterIndex >= book.chapters.count - 1 || isPDFOriginal)

            if !isPDFOriginal {
                tocButton
                bookmarksMenu
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if !isPDFOriginal {
                searchButton
            }
            appearanceButton
            askButton
            notesButton
        }
    }

    private var tocButton: some View {
        Button { showTOC = true } label: {
            Label("Contents", systemImage: "list.bullet")
        }
        .accessibilityIdentifier("reader.toc")
        .accessibilityLabel("Table of contents")
        .help("Table of contents")
        .popover(isPresented: $showTOC) {
            List(0..<book.chapters.count, id: \.self) { index in
                Button {
                    showTOC = false
                    jump(toChapter: index)
                } label: {
                    Text(book.chapters[index].title ?? "Chapter \(index + 1)")
                        .fontWeight(index == chapterIndex ? .bold : .regular)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .frame(minWidth: 260, idealWidth: 300, minHeight: 280, idealHeight: 360)
            .padding(.vertical, 8)
        }
    }

    private var bookmarksMenu: some View {
        Menu {
            Button(
                currentBookmark == nil ? "Add Bookmark" : "Remove Bookmark",
                action: toggleBookmark
            )
            .keyboardShortcut("d", modifiers: .command)

            let bookmarks = model.bookmarks(for: book)
            if !bookmarks.isEmpty {
                Divider()
                ForEach(bookmarks) { bookmark in
                    Menu {
                        Button("Go to Bookmark") {
                            jump(
                                toChapter: bookmark.chapterIndex,
                                offset: bookmark.characterOffset
                            )
                        }
                        Button("Remove", role: .destructive) {
                            model.removeBookmark(bookmark)
                        }
                    } label: {
                        Text(bookmarkLabel(for: bookmark))
                    }
                }
            }
        } label: {
            Label(
                "Bookmarks",
                systemImage: currentBookmark == nil ? "bookmark" : "bookmark.fill"
            )
        }
        .accessibilityIdentifier("reader.bookmarks")
        .accessibilityLabel("Bookmarks")
        .help("Bookmarks — ⌘D adds or removes one here")
    }

    private var searchButton: some View {
        Button { showSearch = true } label: {
            Label("Find in Book", systemImage: "magnifyingglass")
        }
        .keyboardShortcut("f", modifiers: .command)
        .accessibilityIdentifier("reader.search")
        .accessibilityLabel("Find in book")
        .help("Find in book (⌘F)")
        .popover(isPresented: $showSearch) {
            ReaderSearchPopover(book: book) { index, offset in
                showSearch = false
                jump(toChapter: index, offset: offset)
            }
        }
    }

    private var appearanceButton: some View {
        Button { showAppearance = true } label: {
            Label("Appearance", systemImage: "textformat.size")
        }
        .accessibilityIdentifier("reader.appearance")
        .accessibilityLabel("Appearance")
        .help("Appearance — theme, text size (⌘+ / ⌘−), layout")
        .popover(isPresented: $showAppearance) {
            AppearancePopover(
                themeRaw: $themeRaw,
                layoutRaw: $layoutRaw,
                fontSize: $fontSize,
                isPDF: model.isPDF(book),
                pdfShowsOriginal: $pdfShowsOriginal
            )
        }
    }

    private var askButton: some View {
        Button {
            askSelection = nil // whole-book question
            showAsk = true
        } label: {
            Label("Ask the Book", systemImage: "sparkles")
        }
        .keyboardShortcut("a", modifiers: [.command, .shift])
        .accessibilityIdentifier("reader.ask")
        .accessibilityLabel("Ask the book")
        .help("Ask the book (⇧⌘A)")
    }

    private var notesButton: some View {
        Button { showNotes.toggle() } label: {
            Label("Highlights", systemImage: "highlighter")
        }
        .keyboardShortcut("n", modifiers: [.command, .shift])
        .accessibilityIdentifier("reader.notes")
        .accessibilityLabel("Highlights")
        .help("Highlights & notes (⇧⌘N)")
    }

    /// Invisible buttons so ⌘+/⌘− resize text without opening the Appearance
    /// popover — a shortcut registered inside a popover is only live while
    /// that popover is on screen.
    private var hiddenFontShortcuts: some View {
        Group {
            Button("Larger text") { adjustFontSize(+1) }
                .keyboardShortcut("+", modifiers: .command)
            // ⌘= is what most keyboards actually produce for "⌘+".
            Button("Larger text") { adjustFontSize(+1) }
                .keyboardShortcut("=", modifiers: .command)
            Button("Smaller text") { adjustFontSize(-1) }
                .keyboardShortcut("-", modifiers: .command)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func adjustFontSize(_ delta: Double) {
        fontSize = min(
            max(fontSize + delta, Double(ReaderStyle.fontSizeRange.lowerBound)),
            Double(ReaderStyle.fontSizeRange.upperBound)
        )
    }

    // MARK: - Navigation & position

    /// All chapter/offset navigation funnels through here so the paged anchor
    /// and persisted position stay in sync (chevrons, TOC, bookmarks, search
    /// hits, notes-panel jumps).
    private func jump(toChapter index: Int, offset: Int = 0) {
        guard book.chapters.indices.contains(index) else { return }
        pagedAnchor = max(0, offset)
        chapterIndex = index
        // Same-chapter jumps don't fire onChange(of: chapterIndex) — persist
        // explicitly (duplicate saves are harmless).
        model.savePosition(
            ReadingPosition(chapterIndex: index, characterOffset: max(0, offset)),
            for: book
        )
    }

    /// Restore once; later re-appears (e.g. after dismissing a sheet) must not
    /// clobber the chapter the reader navigated to.
    private func restoreOnce() {
        guard !didRestorePosition else { return }
        didRestorePosition = true
        model.markOpened(book)
        if let position = model.position(for: book) {
            pagedAnchor = max(0, position.characterOffset)
            chapterIndex = min(max(0, position.chapterIndex), max(0, book.chapters.count - 1))
        }
    }

    // MARK: - Bookmarks

    /// The anchor a bookmark toggles at: the visible page start in paged
    /// modes, the chapter start in scroll mode. Matching on the exact offset
    /// keeps ⌘D a true toggle — it removes exactly the bookmark it added.
    private var currentAnchorOffset: Int {
        layout == .scroll ? 0 : pagedAnchor
    }

    private var currentBookmark: Bookmark? {
        model.bookmarks(for: book).first {
            $0.chapterIndex == chapterIndex && $0.characterOffset == currentAnchorOffset
        }
    }

    private func toggleBookmark() {
        if let existing = currentBookmark {
            model.removeBookmark(existing)
        } else if let chapter {
            model.addBookmark(Bookmark(
                bookID: book.id,
                chapterIndex: chapterIndex,
                characterOffset: currentAnchorOffset,
                snippet: bookmarkSnippet(of: chapter, at: currentAnchorOffset),
                createdAt: Date()
            ))
        }
    }

    private func bookmarkLabel(for bookmark: Bookmark) -> String {
        let title = book.chapters.indices.contains(bookmark.chapterIndex)
            ? (book.chapters[bookmark.chapterIndex].title
                ?? "Chapter \(bookmark.chapterIndex + 1)")
            : "Chapter \(bookmark.chapterIndex + 1)"
        return bookmark.snippet.isEmpty
            ? title
            : "\(title) — \u{201C}\(bookmark.snippet)\u{201D}"
    }

    /// ~60 characters of context starting at the bookmarked position.
    private func bookmarkSnippet(of chapter: Chapter, at offset: Int, length: Int = 60) -> String {
        let characters = Array(chapter.text)
        guard !characters.isEmpty else { return "" }
        let start = min(max(0, offset), characters.count - 1)
        let end = min(characters.count, start + length)
        return String(characters[start..<end])
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Annotation

    private func highlightSpans(for chapter: Chapter) -> [HighlightSpan] {
        model.highlights(for: book)
            .filter { $0.chapterID == chapter.id }
            .map {
                HighlightSpan(
                    id: $0.id,
                    range: $0.range,
                    color: $0.markerColor,
                    hasNote: !($0.note ?? "").isEmpty
                )
            }
    }

    private func highlight(withID id: UUID) -> Highlight? {
        model.highlights(for: book).first { $0.id == id }
    }

    /// Executes an annotation-menu action against the model. Targets arrive in
    /// chapter coordinates (PagedChapterView already shifted page-local ones).
    private func handleAnnotation(
        in chapter: Chapter, target: AnnotationTarget, action: AnnotationAction
    ) {
        switch action {
        case let .highlight(color):
            switch target {
            case let .selection(range):
                model.addHighlight(in: book, chapter: chapter, range: range, color: color)
            case let .span(span):
                if var existing = highlight(withID: span.id) {
                    existing.color = color
                    model.updateHighlight(existing)
                }
            }

        case .note:
            switch target {
            case let .selection(range):
                // The note editor works on a persisted highlight, so create
                // one first (default yellow) — one gesture, per the spec.
                if let created = model.addHighlight(in: book, chapter: chapter, range: range) {
                    noteDraft = ""
                    editingNote = created
                }
            case let .span(span):
                if let existing = highlight(withID: span.id) {
                    noteDraft = existing.note ?? ""
                    editingNote = existing
                }
            }

        case .ask:
            let range: Range<Int>
            switch target {
            case let .selection(selected):
                range = selected
            case let .span(span):
                range = highlight(withID: span.id)?.range ?? span.range
            }
            askSelection = model.makeSelection(in: chapter, range: range)
            showAsk = true

        case .copy:
            switch target {
            case let .selection(range):
                copyToPasteboard(substring(of: chapter, range: range))
            case let .span(span):
                copyToPasteboard(highlight(withID: span.id)?.quotedText ?? "")
            }

        case .remove:
            if case let .span(span) = target, let existing = highlight(withID: span.id) {
                model.removeHighlight(existing, in: book)
            }
        }
    }

    private func substring(of chapter: Chapter, range: Range<Int>) -> String {
        let characters = Array(chapter.text)
        let lower = min(max(0, range.lowerBound), characters.count)
        let upper = min(max(lower, range.upperBound), characters.count)
        return String(characters[lower..<upper])
    }

    private func copyToPasteboard(_ text: String) {
        guard !text.isEmpty else { return }
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
