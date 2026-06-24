import Foundation

/// Creates and edits highlights from a selected character range within a
/// chapter. Pure logic so the selection-capture UI stays thin and this is fully
/// unit-tested. Ranges are **character** offsets into `Chapter.text`; the UI
/// converts a platform `NSRange` (UTF-16) into character offsets before calling.
public struct HighlightService: Sendable {
    public init() {}

    /// Build a highlight for `range` in `chapter`. The range is clamped to the
    /// chapter bounds; an empty selection throws.
    public func makeHighlight(
        in book: Book,
        chapter: Chapter,
        range: Range<Int>,
        note: String? = nil,
        createdAt: Date
    ) throws -> Highlight {
        let characters = Array(chapter.text)
        let lower = max(0, range.lowerBound)
        let upper = min(characters.count, range.upperBound)
        guard lower < upper else { throw HighlightError.emptySelection }

        let clamped = lower..<upper
        let quoted = String(characters[clamped])
        return Highlight(
            bookID: book.id,
            chapterID: chapter.id,
            range: clamped,
            quotedText: quoted,
            note: note,
            createdAt: createdAt
        )
    }

    /// Return a copy of `highlight` with its note updated.
    public func setNote(_ note: String?, on highlight: Highlight) -> Highlight {
        var copy = highlight
        copy.note = (note?.isEmpty == true) ? nil : note
        return copy
    }
}

public enum HighlightError: Error, Sendable, Equatable {
    case emptySelection
}
