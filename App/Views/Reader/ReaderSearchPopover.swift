import SwiftUI
import ReadrKit

/// One in-book search match, addressable as chapter + character offset so the
/// reader can jump straight to it (the paged anchor lands on the match).
struct BookSearchResult: Identifiable {
    let id: Int
    let chapterIndex: Int
    let chapterTitle: String?
    let characterOffset: Int
    let snippet: String
}

/// Case-insensitive full-book text search. Pure so it stays trivially
/// testable; capped because 100 hits is already more than anyone scans in a
/// popover list.
enum BookSearcher {
    static let resultCap = 100

    static func search(_ query: String, in book: Book, limit: Int = resultCap) -> [BookSearchResult] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        var results: [BookSearchResult] = []
        outer: for (chapterIndex, chapter) in book.chapters.enumerated() {
            let text = chapter.text
            var searchFrom = text.startIndex
            while searchFrom < text.endIndex,
                  let match = text.range(
                      of: needle, options: [.caseInsensitive], range: searchFrom..<text.endIndex
                  ) {
                results.append(BookSearchResult(
                    id: results.count,
                    chapterIndex: chapterIndex,
                    chapterTitle: chapter.title,
                    characterOffset: text.distance(from: text.startIndex, to: match.lowerBound),
                    snippet: snippet(around: match, in: text)
                ))
                if results.count >= limit { break outer }
                searchFrom = match.upperBound
            }
        }
        return results
    }

    /// A single-line excerpt with a little context on both sides of the match.
    private static func snippet(
        around match: Range<String.Index>, in text: String, context: Int = 36
    ) -> String {
        let start = text.index(match.lowerBound, offsetBy: -context, limitedBy: text.startIndex)
            ?? text.startIndex
        let end = text.index(match.upperBound, offsetBy: context, limitedBy: text.endIndex)
            ?? text.endIndex
        let excerpt = String(text[start..<end])
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return (start > text.startIndex ? "…" : "")
            + excerpt
            + (end < text.endIndex ? "…" : "")
    }
}

/// In-book search UI (⌘F popover): a query field and a result list scanning
/// every chapter. ⏎ jumps to the first hit; clicking a row jumps to that hit.
struct ReaderSearchPopover: View {
    let book: Book
    /// Jump to (chapterIndex, characterOffset). The host closes the popover.
    var onJump: (Int, Int) -> Void

    @State private var query = ""
    @State private var results: [BookSearchResult] = []

    var body: some View {
        VStack(spacing: 8) {
            TextField("Find in book", text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("reader.search.field")
                .onSubmit {
                    if let first = results.first {
                        onJump(first.chapterIndex, first.characterOffset)
                    }
                }

            if results.isEmpty {
                Text(query.trimmingCharacters(in: .whitespaces).isEmpty
                    ? "Search every chapter of this book."
                    : "No matches.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(results) { result in
                    Button {
                        onJump(result.chapterIndex, result.characterOffset)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.chapterTitle ?? "Chapter \(result.chapterIndex + 1)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(result.snippet)
                                .font(.callout)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
                if results.count >= BookSearcher.resultCap {
                    Text("Showing the first \(BookSearcher.resultCap) matches.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(minWidth: 320, idealWidth: 360, minHeight: 320, idealHeight: 400)
        .task(id: query) {
            // Debounce keystrokes — every scan walks the whole book.
            try? await Task.sleep(nanoseconds: 200_000_000)
            if Task.isCancelled { return }
            results = BookSearcher.search(query, in: book)
        }
    }
}
