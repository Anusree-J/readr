import Foundation
import ReadrKit

/// Drives the Article studio: streams an article composed from the chosen
/// highlights via the active LLM provider, then holds the editable Markdown.
@MainActor
final class ArticleViewModel: ObservableObject {
    @Published var markdown = ""
    @Published var title: String
    @Published var isComposing = false
    @Published var errorMessage: String?

    private let book: Book
    private let composer = LLMArticleComposer()
    private var composeTask: Task<Void, Never>?

    init(book: Book) {
        self.book = book
        self.title = "Notes on \(book.metadata.title)"
    }

    /// Kick off (or re-run) composition. Always starts fresh: "Recompose" is
    /// an explicit studio action, so discarding the previous text is the
    /// intent. The provider is resolved by the caller at compose time so a key
    /// configured while the sheet is open is picked up.
    func startComposing(highlights: [Highlight], guidance: String, provider: LLMProvider?) {
        guard !isComposing else { return }
        composeTask = Task {
            await compose(highlights: highlights, guidance: guidance, provider: provider)
        }
    }

    /// Cancel an in-flight stream (e.g. the sheet was dismissed mid-compose);
    /// cancellation propagates to the provider via the composer's stream.
    func cancelComposing() {
        composeTask?.cancel()
        composeTask = nil
    }

    private func compose(highlights: [Highlight], guidance: String, provider: LLMProvider?) async {
        guard !highlights.isEmpty else {
            errorMessage = "Select at least one highlight to compose an article."
            return
        }
        guard let provider else {
            errorMessage = "Connect an AI provider in settings to compose articles."
            return
        }
        markdown = ""
        errorMessage = nil
        isComposing = true
        defer { isComposing = false }

        var input = highlights
        let trimmedGuidance = guidance.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedGuidance.isEmpty {
            input.append(Self.guidanceHighlight(trimmedGuidance, bookID: book.id))
        }

        do {
            // Append deltas live so the studio fills in as the article streams.
            for try await delta in composer.composeStreaming(
                from: input, in: book, provider: provider
            ) {
                markdown += delta
            }
            guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                // Reset any partial whitespace-only output so the picker shows.
                markdown = ""
                errorMessage = "The model returned an empty article. Try again."
                return
            }
        } catch is CancellationError {
            // The studio went away mid-stream; nothing to surface.
            markdown = ""
        } catch ArticleComposerError.noHighlights {
            markdown = ""
            errorMessage = "Highlight something first to compose an article."
        } catch {
            markdown = ""
            errorMessage = error.localizedDescription
        }
    }

    /// `LLMArticleComposer` has no guidance parameter, so reader guidance rides
    /// along as a trailing synthetic "highlight": the note carries an explicit
    /// instruction (flagged as not-a-quotation), and its unknown chapterID +
    /// maximal range sort it after every real highlight in the composer's
    /// reading-order prompt (see `LLMArticleComposer.orderedHighlights`).
    private static func guidanceHighlight(_ guidance: String, bookID: UUID) -> Highlight {
        Highlight(
            bookID: bookID,
            chapterID: UUID(),
            range: (Int.max - 1)..<Int.max,
            quotedText: "",
            note: "Instruction from the reader about the article itself (not a quotation): \(guidance)",
            createdAt: Date()
        )
    }
}
