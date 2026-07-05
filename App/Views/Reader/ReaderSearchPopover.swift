import SwiftUI
import ReadrKit

/// In-book search UI (⌘F popover): a query field and a result list scanning
/// every chapter. ⏎ jumps to the first hit; clicking a row jumps to that hit.
/// The scan itself is `ReadrKit.BookSearcher`, run off the main actor.
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
            let found = await Self.scan(query, in: book)
            // A newer keystroke restarted the task mid-scan; drop the stale
            // (possibly partial) results — the new task owns `results` now.
            if Task.isCancelled { return }
            results = found
        }
    }

    /// Runs the whole-book scan off the main actor: a non-isolated async
    /// function always hops to the global concurrent executor, so typing stays
    /// responsive while `BookSearcher` walks the chapters (checking task
    /// cancellation between them). `.task(id:)` publishes the results back on
    /// the MainActor above.
    private static func scan(_ query: String, in book: Book) async -> [BookSearchResult] {
        BookSearcher.search(query, in: book)
    }
}
