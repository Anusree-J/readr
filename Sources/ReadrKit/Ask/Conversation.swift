import Foundation

/// A pointer back into the book that grounds part of an answer.
public struct Citation: Sendable, Hashable, Codable {
    /// Human-readable position, e.g. "Ch. 4 ¶12".
    public var locator: String
    public var quotedText: String

    public init(locator: String, quotedText: String) {
        self.locator = locator
        self.quotedText = quotedText
    }
}

/// A completed answer to a reader's question, with its routing tier and citations.
public struct Answer: Sendable, Hashable {
    public var text: String
    public var tier: AssembledContext.Tier
    public var citations: [Citation]

    public init(
        text: String,
        tier: AssembledContext.Tier,
        citations: [Citation] = []
    ) {
        self.text = text
        self.tier = tier
        self.citations = citations
    }
}

/// One question/answer exchange. The answer is filled in once streaming completes.
public struct ConversationTurn: Identifiable, Sendable, Hashable {
    public let id: UUID
    public var question: String
    public var answer: Answer?

    public init(id: UUID = UUID(), question: String, answer: Answer? = nil) {
        self.id = id
        self.question = question
        self.answer = answer
    }
}

/// An ordered transcript of turns for a single book.
public struct Conversation: Sendable, Hashable {
    public var bookID: UUID
    public private(set) var turns: [ConversationTurn]

    public init(bookID: UUID) {
        self.bookID = bookID
        self.turns = []
    }

    /// Append a pending turn for `question` and return its identifier.
    @discardableResult
    public mutating func startTurn(question: String) -> UUID {
        let turn = ConversationTurn(question: question)
        turns.append(turn)
        return turn.id
    }

    /// Attach `answer` to the turn identified by `turnID`, if it exists.
    public mutating func complete(turnID: UUID, answer: Answer) {
        guard let index = turns.firstIndex(where: { $0.id == turnID }) else { return }
        turns[index].answer = answer
    }
}
