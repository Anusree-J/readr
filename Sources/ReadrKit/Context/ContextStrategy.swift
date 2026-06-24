import Foundation

/// The text the reader has selected and is asking about.
public struct Selection: Sendable, Hashable {
    public var chapterID: UUID
    public var quotedText: String
    /// Surrounding paragraphs for the "where you are" anchor.
    public var surroundingText: String
    public var chapterTitle: String?

    public init(
        chapterID: UUID,
        quotedText: String,
        surroundingText: String,
        chapterTitle: String? = nil
    ) {
        self.chapterID = chapterID
        self.quotedText = quotedText
        self.surroundingText = surroundingText
        self.chapterTitle = chapterTitle
    }
}

/// A ready-to-send payload: which routing tier was chosen and the messages.
public struct AssembledContext: Sendable {
    public enum Tier: String, Sendable { case wholeBook, retrieval }
    public var tier: Tier
    public var request: ChatRequest

    public init(tier: Tier, request: ChatRequest) {
        self.tier = tier
        self.request = request
    }
}

/// Assembles the optimal prompt context for a question about a book.
/// See docs/CONTEXT-STRATEGY.md for the rationale.
public protocol ContextStrategy: Sendable {
    func assembleContext(
        for question: String,
        in book: Book,
        selection: Selection?,
        provider: ProviderInfo
    ) async throws -> AssembledContext
}

/// Default adaptive router:
/// - Tier 1 (whole book) when the book fits the provider budget.
/// - Tier 2 (retrieval) otherwise, or for local/small-context models.
/// Both tiers always inject the selection + chapter + TOC anchor.
public struct AdaptiveContextStrategy: ContextStrategy {
    private let index: RAGIndex
    /// Fraction of the context budget we allow the book to occupy before
    /// switching to retrieval (leaves room for history + answer).
    private let wholeBookBudgetFraction: Double

    public init(index: RAGIndex, wholeBookBudgetFraction: Double = 0.6) {
        self.index = index
        self.wholeBookBudgetFraction = wholeBookBudgetFraction
    }

    public func assembleContext(
        for question: String,
        in book: Book,
        selection: Selection?,
        provider: ProviderInfo
    ) async throws -> AssembledContext {
        let anchor = Self.anchor(for: book, selection: selection)
        let budget = Int(Double(provider.contextBudget) * wholeBookBudgetFraction)
        let fitsWholeBook = !provider.isLocal && book.estimatedTokenCount <= budget

        if fitsWholeBook {
            // Tier 1: full text as a cacheable prefix; question carries the anchor.
            let request = ChatRequest(
                messages: [
                    .init(role: .system, content: Self.systemPrompt),
                    .init(role: .user, content: anchor + "\n\nQuestion: " + question),
                ],
                cacheableSystemPrefix: provider.supportsPromptCaching ? book.fullText : nil,
                maxOutputTokens: 1024
            )
            return AssembledContext(tier: .wholeBook, request: request)
        }

        // Tier 2: hybrid retrieval over the rest of the book.
        let passages = try await index.retrieve(
            query: question,
            bookID: book.id,
            limit: 8
        )
        let retrieved = passages
            .map { "[\($0.locator)] \($0.text)" }
            .joined(separator: "\n\n")
        let request = ChatRequest(
            messages: [
                .init(role: .system, content: Self.systemPrompt),
                .init(
                    role: .user,
                    content: anchor
                        + "\n\nRelevant passages from elsewhere in the book:\n"
                        + retrieved
                        + "\n\nQuestion: " + question
                ),
            ],
            maxOutputTokens: 1024
        )
        return AssembledContext(tier: .retrieval, request: request)
    }

    static let systemPrompt = """
    You are a reading companion embedded in an ebook reader. Answer the reader's \
    question using the provided book context. Be precise, cite the relevant part \
    of the text when useful, and say so if the answer is not in the book.
    """

    /// The always-injected "where you are" anchor (Tier 3).
    static func anchor(for book: Book, selection: Selection?) -> String {
        var parts: [String] = []
        parts.append("Book: \"\(book.metadata.title)\" by \(book.metadata.authors.joined(separator: ", "))")
        if let sel = selection {
            if let ch = sel.chapterTitle { parts.append("Current chapter: \(ch)") }
            parts.append("Selected text: \"\(sel.quotedText)\"")
            parts.append("Surrounding context: \(sel.surroundingText)")
        }
        return parts.joined(separator: "\n")
    }
}
