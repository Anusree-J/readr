import SwiftUI
import ReadrKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Layout-accurate pagination for the paged reading surface.
///
/// `ReadrKit.Paginator` splits on an estimated character capacity, so every
/// page holds a different visual amount of text — ragged bottoms, and facing
/// pages whose last lines sit at different heights, nothing like an open
/// book. This paginator instead measures the SAME attributed string the
/// reading surface renders (same font, line/paragraph spacing, image
/// attachment bounds, zero container insets and fragment padding — see
/// `TextRangeConvert.attributedString` and the `SelectableTextView`
/// representables) by filling one fixed-size `NSTextContainer` per page, so
/// breaks land exactly where rendered lines end and every non-final page is
/// visually full.
///
/// Lives in the app target: it needs TextKit, which `ReadrKit` (Linux-clean)
/// can't import. `ReadrKit.Paginator` remains the geometry-free fallback and
/// the host of the shared `Page`/spread index helpers.
struct LayoutPaginator {
    let style: ReaderStyle
    let inlineImages: [Int: PlatformImage]

    /// Split `text` into pages, where page `i`'s text area is
    /// `containerSize(i)` (sizes vary per page: the spread's first page
    /// reserves the kicker band). `Page` semantics mirror
    /// `ReadrKit.Paginator`: ranges are contiguous and cover the whole text,
    /// and whitespace folded at a page boundary is covered by `range` but
    /// excluded from `text`, keeping `textStartOffset` the correct origin
    /// for highlights and selections.
    ///
    /// Returns `[]` when measurement cannot cover the text (degenerate
    /// geometry, or an attachment taller than a page) — the caller falls
    /// back to the estimate-based paginator so reading never breaks.
    func paginate(_ text: String, containerSize: (Int) -> CGSize) -> [Page] {
        let chars = Array(text)
        let n = chars.count
        guard n > 0 else { return [] }

        let attributed = TextRangeConvert.attributedString(
            text, highlights: [], style: style, inlineImages: inlineImages
        )
        let storage = NSTextStorage(attributedString: attributed)
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)

        // Fill one container per page; collect each page's UTF-16 end.
        var utf16Ends: [Int] = []
        var consumed = 0
        while consumed < storage.length {
            let size = containerSize(utf16Ends.count)
            guard size.width > 8, size.height > style.fontSize else {
                return [] // degenerate geometry — caller falls back
            }
            let container = NSTextContainer(size: size)
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)
            layoutManager.ensureLayout(for: container)
            let glyphRange = layoutManager.glyphRange(for: container)
            let charRange = layoutManager.characterRange(
                forGlyphRange: glyphRange, actualGlyphRange: nil
            )
            let end = charRange.location + charRange.length
            guard end > consumed else {
                // The container accepted nothing (an attachment taller than
                // the page, or a measurement anomaly). Bail rather than loop.
                return []
            }
            consumed = end
            utf16Ends.append(end)
        }
        guard !utf16Ends.isEmpty else { return [] }

        // Convert UTF-16 boundaries to character offsets and build pages
        // with the shared boundary-whitespace folding rules.
        var pages: [Page] = []
        var rangeStart = 0
        for (index, utf16End) in utf16Ends.enumerated() {
            let isLast = index == utf16Ends.count - 1
            var end: Int
            if isLast {
                end = n
            } else {
                // Glyph→character mapping lands on character boundaries, so
                // conversion should always succeed; if a boundary ever fell
                // mid-scalar, nudge FORWARD until it converts (the next page
                // then starts on the same valid boundary — nothing is lost).
                var location = utf16End
                var converted = TextRangeConvert.characterOffset(
                    fromUTF16Location: location, in: text
                )
                while converted == nil, location < storage.length {
                    location += 1
                    converted = TextRangeConvert.characterOffset(
                        fromUTF16Location: location, in: text
                    )
                }
                end = converted ?? n
            }
            end = min(max(end, rangeStart), n)
            // Fold boundary whitespace into the range, not the text.
            var textStart = rangeStart
            while textStart < end, chars[textStart].isWhitespace { textStart += 1 }
            guard textStart < end else {
                // Whitespace-only slice: extend the previous page's range
                // over it (mirrors Paginator's trailing-whitespace fold).
                if var last = pages.last {
                    last.range = last.range.lowerBound..<end
                    pages[pages.count - 1] = last
                }
                rangeStart = end
                continue
            }
            pages.append(Page(text: String(chars[textStart..<end]), range: rangeStart..<end))
            rangeStart = end
        }
        return pages
    }
}
