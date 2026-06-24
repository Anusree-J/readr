import Foundation
import ReadrKit

/// Composes an article from a book's highlights via the active LLM provider, and
/// holds the editable Markdown result.
@MainActor
final class ArticleViewModel: ObservableObject {
    @Published var markdown = ""
    @Published var title = "Article"
    @Published var isComposing = false
    @Published var errorMessage: String?

    let hasHighlights: Bool
    let hasProvider: Bool

    private let book: Book
    private let highlights: [Highlight]
    private let provider: LLMProvider?
    private let composer = LLMArticleComposer()

    init(book: Book, highlights: [Highlight], provider: LLMProvider?) {
        self.book = book
        self.highlights = highlights
        self.provider = provider
        self.hasHighlights = !highlights.isEmpty
        self.hasProvider = provider != nil
    }

    func compose() async {
        guard markdown.isEmpty, !isComposing else { return }
        guard hasHighlights else {
            errorMessage = "Highlight something first to compose an article."
            return
        }
        guard let provider else {
            errorMessage = "Connect an AI provider in settings to compose articles."
            return
        }
        isComposing = true
        errorMessage = nil
        defer { isComposing = false }
        do {
            let article = try await composer.compose(from: highlights, in: book, provider: provider)
            title = article.title
            markdown = article.markdown
        } catch ArticleComposerError.noHighlights {
            errorMessage = "Highlight something first to compose an article."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
