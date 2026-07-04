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
    /// Highlight ranges in chapter coordinates.
    let highlightRanges: [Range<Int>]
    /// Selection callback in chapter coordinates.
    let onSelect: (Range<Int>) -> Void

    /// Index of the first visible page.
    @State private var pageStart = 0
    @FocusState private var focused: Bool

    var body: some View {
        GeometryReader { geo in
            let pages = paginate(for: geo.size)
            let start = clampedStart(in: pages)
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
            .onChange(of: chapter.id) { _, _ in pageStart = 0 }
            .onChange(of: layout) { _, _ in
                pageStart = Paginator.spreadStart(for: pageStart, layout: layout)
            }
        }
    }

    // MARK: - Pages

    private func paginate(for size: CGSize) -> [Page] {
        Paginator(capacity: Self.capacity(for: size, layout: layout))
            .paginate(chapter.text)
    }

    /// Conservative characters-per-page estimate from geometry + body font.
    static func capacity(for size: CGSize, layout: PageLayout) -> Int {
        #if canImport(UIKit)
        let pointSize = UIFont.preferredFont(forTextStyle: .body).pointSize
        #else
        let pointSize = NSFont.preferredFont(forTextStyle: .body).pointSize
        #endif
        let columns = layout == .doublePage ? 2.0 : 1.0
        let pageWidth = max(1, (size.width - 48) / columns)
        let pageHeight = max(1, size.height - 72) // page bar + padding
        let charsPerLine = pageWidth / (pointSize * 0.55)
        let lines = pageHeight / (pointSize * 1.45)
        // 0.85 safety factor so a page never overflows its frame.
        return max(80, Int(charsPerLine * lines * 0.85))
    }

    private func clampedStart(in pages: [Page]) -> Int {
        guard !pages.isEmpty else { return 0 }
        let clamped = min(max(0, pageStart), pages.count - 1)
        return Paginator.spreadStart(for: clamped, layout: layout)
    }

    private func visiblePages(from start: Int, in pages: [Page]) -> [Page] {
        guard !pages.isEmpty else { return [] }
        let end = min(start + layout.pagesPerSpread, pages.count)
        return Array(pages[start..<end])
    }

    private func turnPage(_ direction: Int, in pages: [Page]) {
        guard !pages.isEmpty else { return }
        let step = layout.pagesPerSpread
        let next = clampedStart(in: pages) + direction * step
        pageStart = min(max(0, next), max(0, pages.count - 1))
    }

    // MARK: - Subviews

    @ViewBuilder
    private func pageView(_ page: Page) -> some View {
        SelectableTextView(
            text: page.text,
            highlightRanges: highlightRanges.compactMap { range in
                // Intersect chapter-coordinate highlights with this page, then
                // shift into page coordinates.
                let lower = max(range.lowerBound, page.range.lowerBound)
                let upper = min(range.upperBound, page.range.lowerBound + page.text.count)
                guard lower < upper else { return nil }
                return (lower - page.range.lowerBound)..<(upper - page.range.lowerBound)
            },
            onSelect: { pageRange in
                // Shift back into chapter coordinates.
                let offset = page.range.lowerBound
                onSelect((pageRange.lowerBound + offset)..<(pageRange.upperBound + offset))
            }
        )
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func pageBar(start: Int, pages: [Page]) -> some View {
        HStack {
            Button { turnPage(-1, in: pages) } label: {
                Image(systemName: "arrow.left")
            }
            .accessibilityLabel("Previous page")
            .disabled(start == 0)

            Spacer()
            if !pages.isEmpty {
                let last = min(start + layout.pagesPerSpread, pages.count)
                Text(
                    layout == .doublePage && last - start > 1
                        ? "Pages \(start + 1)–\(last) of \(pages.count)"
                        : "Page \(start + 1) of \(pages.count)"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            Spacer()

            Button { turnPage(+1, in: pages) } label: {
                Image(systemName: "arrow.right")
            }
            .accessibilityLabel("Next page")
            .disabled(pages.isEmpty || start + layout.pagesPerSpread >= pages.count)
        }
        .buttonStyle(.bordered)
        .padding(.bottom, 6)
    }
}
