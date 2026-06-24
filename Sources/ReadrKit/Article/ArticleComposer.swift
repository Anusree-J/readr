import Foundation

/// A composed article generated from a reader's highlights and notes.
public struct Article: Sendable, Hashable {
    public var title: String
    public var markdown: String

    public init(title: String, markdown: String) {
        self.title = title
        self.markdown = markdown
    }
}

/// Turns a set of highlights + notes into a coherent, editable article,
/// grounded in the book's context.
public protocol ArticleComposer: Sendable {
    func compose(
        from highlights: [Highlight],
        in book: Book,
        provider: LLMProvider
    ) async throws -> Article
}

/// Default LLM-backed composer. Orders highlights by reading position, feeds
/// them with book context, and asks the model for a structured Markdown article.
public struct LLMArticleComposer: ArticleComposer {
    public init() {}

    public func compose(
        from highlights: [Highlight],
        in book: Book,
        provider: LLMProvider
    ) async throws -> Article {
        let ordered = highlights.sorted { $0.createdAt < $1.createdAt }
        let bullets = ordered.map { h -> String in
            var line = "- \"\(h.quotedText)\""
            if let note = h.note, !note.isEmpty { line += " — note: \(note)" }
            return line
        }.joined(separator: "\n")

        let prompt = """
        Compose a coherent, well-structured article in Markdown from the reader's \
        highlights and notes below, taken from "\(book.metadata.title)" by \
        \(book.metadata.authors.joined(separator: ", ")). Preserve the reader's \
        intent, weave the highlights into a narrative with headings, and keep \
        quotations accurate.

        Highlights and notes:
        \(bullets)
        """

        let request = ChatRequest(
            messages: [.init(role: .user, content: prompt)],
            maxOutputTokens: 2048
        )

        var markdown = ""
        for try await chunk in provider.stream(request) {
            markdown += chunk.textDelta
        }
        return Article(title: "Notes on \(book.metadata.title)", markdown: markdown)
    }
}
