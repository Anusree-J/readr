import Foundation

/// A parsed book, independent of its source format (EPUB, PDF, ...).
public struct Book: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var metadata: BookMetadata
    public var chapters: [Chapter]
    /// Approximate token count of the full text, computed once at import and
    /// used by `ContextStrategy` to choose whole-book vs. retrieval.
    public var estimatedTokenCount: Int

    public init(
        id: UUID = UUID(),
        metadata: BookMetadata,
        chapters: [Chapter],
        estimatedTokenCount: Int
    ) {
        self.id = id
        self.metadata = metadata
        self.chapters = chapters
        self.estimatedTokenCount = estimatedTokenCount
    }

    /// Full plain text, chapters joined in reading order.
    public var fullText: String {
        chapters.map(\.text).joined(separator: "\n\n")
    }
}

public struct BookMetadata: Hashable, Sendable {
    public var title: String
    public var authors: [String]
    public var language: String?
    public var publisher: String?
    /// Table of contents, always injected as part of the query anchor.
    public var tableOfContents: [TOCEntry]

    public init(
        title: String,
        authors: [String] = [],
        language: String? = nil,
        publisher: String? = nil,
        tableOfContents: [TOCEntry] = []
    ) {
        self.title = title
        self.authors = authors
        self.language = language
        self.publisher = publisher
        self.tableOfContents = tableOfContents
    }
}

public struct TOCEntry: Hashable, Sendable {
    public var title: String
    public var chapterIndex: Int
    public var children: [TOCEntry]

    public init(title: String, chapterIndex: Int, children: [TOCEntry] = []) {
        self.title = title
        self.chapterIndex = chapterIndex
        self.children = children
    }
}

public struct Chapter: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var title: String?
    public var order: Int
    public var text: String

    public init(id: UUID = UUID(), title: String?, order: Int, text: String) {
        self.id = id
        self.title = title
        self.order = order
        self.text = text
    }
}

/// A reader's highlight, anchored to a text range.
public struct Highlight: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var bookID: UUID
    public var chapterID: UUID
    /// Character range within the chapter text.
    public var range: Range<Int>
    public var quotedText: String
    public var note: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        bookID: UUID,
        chapterID: UUID,
        range: Range<Int>,
        quotedText: String,
        note: String? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.bookID = bookID
        self.chapterID = chapterID
        self.range = range
        self.quotedText = quotedText
        self.note = note
        self.createdAt = createdAt
    }
}
