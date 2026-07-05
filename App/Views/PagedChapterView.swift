import SwiftUI
import ReadrKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Renders a chapter as fixed pages — one page, or two facing pages like an
/// open book. Pagination is done by `ReadrKit.Paginator` from a character
/// capacity derived from the view's geometry and the body font, so pages
/// reflow on window resize. Text selection still reports **chapter**
/// coordinates, so highlights and Ask work identically to scroll mode.
struct PagedChapterView: View {
    let chapter: Chapter
    let layout: PageLayout
    /// Theme + typography used to render pages; also drives the
    /// characters-per-page capacity estimate.
    var style: ReaderStyle = ReaderStyle()
    /// Highlights in chapter coordinates.
    let highlights: [HighlightSpan]
    /// Inline images keyed by character offset in **chapter** coordinates.
    var inlineImages: [Int: PlatformImage] = [:]
    /// Reading position as a **character offset** into the chapter, so it
    /// survives re-pagination (layout switches, window resizes) without
    /// jumping — the page index is derived from it at render time. Owned by
    /// the parent so it can persist the position, anchor bookmarks, and jump
    /// programmatically (TOC / bookmarks / search / notes panel).
    @Binding var anchorOffset: Int
    /// Annotation-menu actions, reported in chapter coordinates.
    var onAnnotate: (AnnotationTarget, AnnotationAction) -> Void = { _, _ in }

    @State private var cache = PaginationCache()
    @FocusState private var focused: Bool

    /// Memoizes the last pagination so page turns/selection don't re-scan the
    /// whole chapter on every body evaluation. Reference type on purpose:
    /// mutating it during render doesn't invalidate the view.
    private final class PaginationCache {
        var chapterID: UUID?
        var capacity = 0
        var pages: [Page] = []
        /// Words from the start of each page to the chapter's end (index-
        /// aligned with `pages`). Computed once per pagination so the page
        /// bar's "min left" never re-scans the chapter text in body.
        var remainingWords: [Int] = []
    }

    var body: some View {
        GeometryReader { geo in
            let pages = paginate(for: geo.size)
            let start = startIndex(in: pages)
            let visible = visiblePages(from: start, in: pages)

            VStack(spacing: 8) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.offset) { item in
                        pageView(item.element)
                        if layout == .doublePage, item.offset == 0, visible.count > 1 {
                            Divider().padding(.vertical)
                        }
                    }
                    // Keep the book "spine" centered when the last spread has
                    // a single page.
                    if layout == .doublePage, visible.count == 1 {
                        Divider().padding(.vertical)
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
                .frame(maxHeight: .infinity)

                pageBar(start: start, pages: pages)
            }
            .padding(.horizontal)
            .contentShape(Rectangle())
            .focusable()
            .focused($focused)
            .onKeyPress(.rightArrow) { turnPage(+1, in: pages); return .handled }
            .onKeyPress(.leftArrow) { turnPage(-1, in: pages); return .handled }
            .onAppear { focused = true }
        }
    }

    // MARK: - Pages

    private func paginate(for size: CGSize) -> [Page] {
        let capacity = Self.capacity(for: size, layout: layout, style: style)
        if cache.chapterID == chapter.id, cache.capacity == capacity {
            return cache.pages
        }
        let pages = Paginator(capacity: capacity).paginate(chapter.text)
        cache.chapterID = chapter.id
        cache.capacity = capacity
        cache.pages = pages
        // Suffix-sum per-page word counts (pages break on whitespace, so the
        // sum matches counting the chapter once). One O(chapter) pass here
        // instead of one per render in the page bar.
        var remaining = [Int](repeating: 0, count: pages.count)
        var total = 0
        for index in pages.indices.reversed() {
            total += ReadingTimeEstimator.wordCount(in: pages[index].text)
            remaining[index] = total
        }
        cache.remainingWords = remaining
        return pages
    }

    /// "min left" from the top of the visible spread, derived from the cached
    /// word counts. Mirrors `ReadingTimeEstimator.minutes(for:)`: round up,
    /// minimum 1 while words remain.
    private func minutesLeft(fromPage start: Int) -> Int {
        guard cache.remainingWords.indices.contains(start) else { return 0 }
        let words = cache.remainingWords[start]
        guard words > 0 else { return 0 }
        return max(
            1, Int((Double(words) / ReadingTimeEstimator.defaultWordsPerMinute).rounded(.up))
        )
    }

    /// Conservative characters-per-page estimate from geometry + the reader
    /// style's font size, so pages reflow when the user changes text size.
    static func capacity(for size: CGSize, layout: PageLayout, style: ReaderStyle) -> Int {
        let pointSize = style.fontSize
        let columns = layout == .doublePage ? 2.0 : 1.0
        let pageWidth = max(1, (size.width - 48) / columns)
        let pageHeight = max(1, size.height - 72) // page bar + padding
        let charsPerLine = pageWidth / (pointSize * 0.55)
        let lines = pageHeight / (pointSize * 1.45)
        // 0.85 safety factor so a page never overflows its frame.
        return max(30, Int(charsPerLine * lines * 0.85))
    }

    /// First visible page index, derived from the character-offset anchor.
    private func startIndex(in pages: [Page]) -> Int {
        guard !pages.isEmpty else { return 0 }
        let index = Paginator.pageIndex(containing: anchorOffset, in: pages)
        return Paginator.spreadStart(for: index, layout: layout)
    }

    private func visiblePages(from start: Int, in pages: [Page]) -> [Page] {
        guard !pages.isEmpty else { return [] }
        let end = min(start + layout.pagesPerSpread, pages.count)
        return Array(pages[start..<end])
    }

    private func turnPage(_ direction: Int, in pages: [Page]) {
        guard !pages.isEmpty else { return }
        let next = startIndex(in: pages) + direction * layout.pagesPerSpread
        let clamped = min(max(0, next), pages.count - 1)
        anchorOffset = pages[clamped].range.lowerBound
    }

    // MARK: - Subviews

    @ViewBuilder
    private func pageView(_ page: Page) -> some View {
        // Images whose placeholder falls on this page, shifted into page
        // coordinates (same textStartOffset origin as highlights below).
        let origin = page.textStartOffset
        let pageImages = Dictionary(uniqueKeysWithValues: inlineImages.compactMap { offset, image in
            (offset >= origin && offset < origin + page.text.count) ? (offset - origin, image) : nil
        })
        SelectableTextView(
            text: page.text,
            highlights: highlights.compactMap { span in
                // Intersect chapter-coordinate highlights with this page, then
                // shift into page coordinates. The origin is textStartOffset,
                // NOT range.lowerBound — folded boundary whitespace is inside
                // the range but not the text.
                let lower = max(span.range.lowerBound, origin)
                let upper = min(span.range.upperBound, origin + page.text.count)
                guard lower < upper else { return nil }
                return HighlightSpan(
                    id: span.id,
                    range: (lower - origin)..<(upper - origin),
                    color: span.color,
                    hasNote: span.hasNote
                )
            },
            style: style,
            inlineImages: pageImages,
            onAnnotate: { target, action in
                onAnnotate(chapterTarget(from: target, origin: origin), action)
            }
        )
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Shift a page-coordinate target back into chapter coordinates (text
    /// origin — see pageView). Spans are restored from the chapter-coordinate
    /// source list by id, so a highlight clipped at a page boundary still
    /// reports its full range.
    private func chapterTarget(from target: AnnotationTarget, origin: Int) -> AnnotationTarget {
        switch target {
        case let .selection(range):
            return .selection((range.lowerBound + origin)..<(range.upperBound + origin))
        case let .span(span):
            if let full = highlights.first(where: { $0.id == span.id }) {
                return .span(full)
            }
            var shifted = span
            shifted.range = (span.range.lowerBound + origin)..<(span.range.upperBound + origin)
            return .span(shifted)
        }
    }

    @ViewBuilder
    private func pageBar(start: Int, pages: [Page]) -> some View {
        HStack(spacing: 16) {
            Button { turnPage(-1, in: pages) } label: {
                Image(systemName: "arrow.left")
            }
            .help("Previous page (←)")
            .accessibilityLabel("Previous page")
            .disabled(start == 0)

            Spacer()
            if !pages.isEmpty {
                let last = min(start + layout.pagesPerSpread, pages.count)
                let pageText = layout == .doublePage && last - start > 1
                    ? "Pages \(start + 1)–\(last) of \(pages.count)"
                    : "Page \(start + 1) of \(pages.count)"
                // "min left" from the top of the visible spread — the same
                // anchor the parent persists. Cached per pagination; scanning
                // chapter.text here would run on every body evaluation.
                let minutes = minutesLeft(fromPage: start)
                Text(minutes > 0 ? "\(pageText) · ~\(minutes) min left in chapter" : pageText)
                    .font(.footnote)
                    .foregroundStyle(style.theme.inkColor.opacity(0.55))
                    .monospacedDigit()
            }
            Spacer()

            Button { turnPage(+1, in: pages) } label: {
                Image(systemName: "arrow.right")
            }
            .help("Next page (→)")
            .accessibilityLabel("Next page")
            .disabled(pages.isEmpty || start + layout.pagesPerSpread >= pages.count)
        }
        .buttonStyle(.borderless)
        .tint(AppTheme.accent)
        .padding(.bottom, 6)
    }
}
