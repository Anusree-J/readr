import SwiftUI
import ReadrKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Unified annotation

/// One reviewable annotation — a text highlight or a native-PDF highlight —
/// unified so the Notes panel, the library review, and the Article studio can
/// render both kinds in a single reading-order list. Highlights must never be
/// trapped inside a book (docs/DESIGN.md, "the wedge").
enum AnnotationItem: Identifiable, Hashable {
    case text(Highlight)
    case pdf(PDFHighlight)

    var id: UUID {
        switch self {
        case .text(let highlight): return highlight.id
        case .pdf(let highlight): return highlight.id
        }
    }

    var quotedText: String {
        switch self {
        case .text(let highlight): return highlight.quotedText
        case .pdf(let highlight): return highlight.quotedText
        }
    }

    var note: String? {
        switch self {
        case .text(let highlight): return highlight.note
        case .pdf(let highlight): return highlight.note
        }
    }

    var color: HighlightColor {
        switch self {
        case .text(let highlight): return highlight.markerColor
        case .pdf(let highlight): return highlight.color
        }
    }

    /// Row caption naming where the annotation lives ("Chapter title" / "Page N").
    func locator(in book: Book) -> String {
        switch self {
        case .text(let highlight):
            if let chapter = book.chapters.first(where: { $0.id == highlight.chapterID }) {
                return chapter.title ?? "Chapter \(chapter.order + 1)"
            }
            return "Unknown chapter"
        case .pdf(let highlight):
            return "Page \(highlight.pageIndex + 1)"
        }
    }

    /// True when the quoted text or the note matches the search query.
    func matches(_ query: String) -> Bool {
        quotedText.localizedCaseInsensitiveContains(query)
            || (note?.localizedCaseInsensitiveContains(query) ?? false)
    }

    /// All of a book's annotations in reading order: text highlights by chapter
    /// order then position within the chapter, then PDF highlights by page.
    /// Mirrors `AnnotationMarkdownExporter`'s grouping so review and export agree.
    static func readingOrder(
        book: Book,
        highlights: [Highlight],
        pdfHighlights: [PDFHighlight]
    ) -> [AnnotationItem] {
        let chapterOrder = Dictionary(
            book.chapters.map { ($0.id, $0.order) },
            uniquingKeysWith: { first, _ in first }
        )
        let text = highlights.sorted { lhs, rhs in
            let lo = chapterOrder[lhs.chapterID] ?? Int.max
            let ro = chapterOrder[rhs.chapterID] ?? Int.max
            if lo != ro { return lo < ro }
            if lhs.range.lowerBound != rhs.range.lowerBound {
                return lhs.range.lowerBound < rhs.range.lowerBound
            }
            return lhs.createdAt < rhs.createdAt
        }
        let pdf = pdfHighlights.sorted { lhs, rhs in
            if lhs.pageIndex != rhs.pageIndex { return lhs.pageIndex < rhs.pageIndex }
            return lhs.createdAt < rhs.createdAt
        }
        return text.map(AnnotationItem.text) + pdf.map(AnnotationItem.pdf)
    }
}

// MARK: - Small shared pieces

/// Cross-platform clipboard write ("Copy Markdown", article "Copy").
enum Pasteboard {
    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

/// Horizontal row of color-dot toggle chips — "color is meaning", so review
/// filters by it (docs/DESIGN.md). All colors are on by default; tapping a dot
/// toggles that color in/out of the active set.
struct HighlightColorChips: View {
    @Binding var active: Set<HighlightColor>

    var body: some View {
        HStack(spacing: 10) {
            ForEach(HighlightColor.allCases, id: \.rawValue) { color in
                let isOn = active.contains(color)
                Button {
                    if isOn { active.remove(color) } else { active.insert(color) }
                } label: {
                    Circle()
                        .fill(ReadingTheme.markerSwatch(color))
                        .frame(width: 16, height: 16)
                        .opacity(isOn ? 1 : 0.25)
                        .overlay(
                            Circle().strokeBorder(.primary.opacity(isOn ? 0.3 : 0), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help("Show \(color.displayName.lowercased()) highlights")
                .accessibilityLabel("\(color.displayName) highlights")
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

// MARK: - Annotation list

/// Filterable reading-order list of a book's annotations, shared by the Notes
/// panel (reader inspector) and the library "Highlights & Notes" review. Jump
/// callbacks are optional — the library review passes none because there is no
/// open reader to jump into.
struct AnnotationListView: View {
    @EnvironmentObject private var model: AppModel
    let book: Book
    var onJumpHighlight: ((Highlight) -> Void)? = nil
    var onJumpPDF: ((PDFHighlight) -> Void)? = nil

    @State private var activeColors = Set(HighlightColor.allCases)
    @State private var searchText = ""
    @State private var editingItem: AnnotationItem?

    private var allItems: [AnnotationItem] {
        AnnotationItem.readingOrder(
            book: book,
            highlights: model.highlights(for: book),
            pdfHighlights: model.pdfHighlights(for: book)
        )
    }

    private var filteredItems: [AnnotationItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return allItems.filter { item in
            activeColors.contains(item.color) && (query.isEmpty || item.matches(query))
        }
    }

    var body: some View {
        if allItems.isEmpty {
            ContentUnavailableView {
                Label("No highlights yet", systemImage: "highlighter")
            } description: {
                Text("Select any passage while reading and pick a color — it appears here instantly.")
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HighlightColorChips(active: $activeColors)
                searchField
                if filteredItems.isEmpty {
                    // Filters (color chips or search) matched nothing — keep the
                    // controls visible so the reader can widen them again.
                    Text("No matching highlights")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list
                }
            }
            .sheet(item: $editingItem) { item in
                NoteEditSheet(item: item) { text in
                    saveNote(text, for: item)
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Search highlights", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(6)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    private var list: some View {
        List {
            ForEach(filteredItems) { item in
                row(for: item)
                    .contextMenu { contextMenu(for: item) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            delete(item)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            editingItem = item
                        } label: {
                            Label("Edit Note", systemImage: "note.text")
                        }
                        .tint(AppTheme.accent)
                    }
            }
        }
        .listStyle(.plain)
    }

    // MARK: Rows

    @ViewBuilder
    private func row(for item: AnnotationItem) -> some View {
        if canJump(to: item) {
            Button {
                jump(to: item)
            } label: {
                rowContent(item).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Jump to this passage in the book")
        } else {
            rowContent(item)
        }
    }

    private func rowContent(_ item: AnnotationItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(ReadingTheme.markerSwatch(item.color))
                .frame(width: 10, height: 10)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.quotedText)
                    .font(.callout)
                    .fontDesign(.serif)
                    .italic()
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                if let note = item.note, !note.isEmpty {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text(item.locator(in: book))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func canJump(to item: AnnotationItem) -> Bool {
        switch item {
        case .text: return onJumpHighlight != nil
        case .pdf: return onJumpPDF != nil
        }
    }

    private func jump(to item: AnnotationItem) {
        switch item {
        case .text(let highlight): onJumpHighlight?(highlight)
        case .pdf(let highlight): onJumpPDF?(highlight)
        }
    }

    // MARK: Actions

    @ViewBuilder
    private func contextMenu(for item: AnnotationItem) -> some View {
        Button {
            editingItem = item
        } label: {
            Label(item.note?.isEmpty == false ? "Edit Note" : "Add Note", systemImage: "note.text")
        }
        Menu {
            ForEach(HighlightColor.allCases, id: \.rawValue) { color in
                Button {
                    recolor(item, to: color)
                } label: {
                    if color == item.color {
                        Label(color.displayName, systemImage: "checkmark")
                    } else {
                        Text(color.displayName)
                    }
                }
            }
        } label: {
            Label("Color", systemImage: "paintpalette")
        }
        Divider()
        Button(role: .destructive) {
            delete(item)
        } label: {
            Label("Delete Highlight", systemImage: "trash")
        }
    }

    private func recolor(_ item: AnnotationItem, to color: HighlightColor) {
        switch item {
        case .text(var highlight):
            highlight.color = color
            model.updateHighlight(highlight)
        case .pdf(var highlight):
            highlight.color = color
            model.updatePDFHighlight(highlight)
        }
    }

    private func delete(_ item: AnnotationItem) {
        switch item {
        case .text(let highlight): model.removeHighlight(highlight, in: book)
        case .pdf(let highlight): model.removePDFHighlight(highlight)
        }
    }

    private func saveNote(_ text: String, for item: AnnotationItem) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Saving an empty editor clears the note rather than storing "".
        let note = trimmed.isEmpty ? nil : trimmed
        switch item {
        case .text(var highlight):
            highlight.note = note
            model.updateHighlight(highlight)
        case .pdf(var highlight):
            highlight.note = note
            model.updatePDFHighlight(highlight)
        }
    }
}

// MARK: - Note editor

/// Edits (or adds) the note attached to one annotation. The quote stays
/// visible above the editor so the reader remembers what they're annotating.
private struct NoteEditSheet: View {
    let item: AnnotationItem
    var onSave: (String) -> Void

    @State private var text: String
    @Environment(\.dismiss) private var dismiss

    init(item: AnnotationItem, onSave: @escaping (String) -> Void) {
        self.item = item
        self.onSave = onSave
        _text = State(initialValue: item.note ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                Text(item.quotedText)
                    .font(.callout)
                    .fontDesign(.serif)
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                TextEditor(text: $text)
                    .font(.body)
                    .frame(minHeight: 120)
            }
            .padding()
            .navigationTitle("Note")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(text)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 280)
        #endif
    }
}
