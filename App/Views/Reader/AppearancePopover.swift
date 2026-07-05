import SwiftUI
import ReadrKit

/// The Appearance popover (a popover, not a menu, so themes preview live):
/// theme tiles, text size stepper, layout picker, and — for PDFs — the
/// original-pages ↔ reading-view switch.
struct AppearancePopover: View {
    @Binding var themeRaw: String
    @Binding var layoutRaw: String
    @Binding var fontSize: Double
    var isPDF: Bool = false
    @Binding var pdfShowsOriginal: Bool

    private var theme: ReadingTheme { ReadingTheme(rawValue: themeRaw) ?? .paper }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ForEach(ReadingTheme.allCases) { option in
                    themeTile(option)
                }
            }

            HStack {
                Button { adjust(-1) } label: {
                    Image(systemName: "textformat.size.smaller").frame(minWidth: 44)
                }
                .disabled(fontSize <= Double(ReaderStyle.fontSizeRange.lowerBound))
                .help("Smaller text (⌘−)")
                .accessibilityLabel("Smaller text")
                .accessibilityIdentifier("appearance.textSmaller")

                Text("\(Int(fontSize)) pt")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)

                Button { adjust(+1) } label: {
                    Image(systemName: "textformat.size.larger").frame(minWidth: 44)
                }
                .disabled(fontSize >= Double(ReaderStyle.fontSizeRange.upperBound))
                .help("Larger text (⌘+)")
                .accessibilityLabel("Larger text")
                .accessibilityIdentifier("appearance.textLarger")
            }
            .buttonStyle(.bordered)

            Picker("Layout", selection: $layoutRaw) {
                Text("Scroll").tag(PageLayout.scroll.rawValue)
                Text("Single page").tag(PageLayout.singlePage.rawValue)
                Text("Two pages").tag(PageLayout.doublePage.rawValue)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Reading layout")

            if isPDF {
                Divider()
                Picker("PDF display", selection: $pdfShowsOriginal) {
                    Text("Original pages").tag(true)
                    Text("Reading view").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Show the PDF's original pages, or its extracted text with highlights")
            }
        }
        .padding(16)
        .frame(width: 288)
    }

    private func adjust(_ delta: Double) {
        fontSize = min(
            max(fontSize + delta, Double(ReaderStyle.fontSizeRange.lowerBound)),
            Double(ReaderStyle.fontSizeRange.upperBound)
        )
    }

    /// A live-preview swatch: the theme's own paper with serif "Aa" in its ink.
    private func themeTile(_ option: ReadingTheme) -> some View {
        Button { themeRaw = option.rawValue } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(option.background)
                    .overlay(
                        Text("Aa")
                            .font(.system(size: 17, design: .serif))
                            .foregroundStyle(option.inkColor)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                option == theme ? AppTheme.accent : Color.primary.opacity(0.15),
                                lineWidth: option == theme ? 2 : 1
                            )
                    )
                    .frame(height: 48)
                Text(option.displayName)
                    .font(.caption)
                    .foregroundStyle(option == theme ? AppTheme.accent : .secondary)
            }
        }
        .buttonStyle(.plain)
        .help("\(option.displayName) theme")
        .accessibilityLabel(option.displayName)
        .accessibilityIdentifier("appearance.theme.\(option.rawValue)")
        .accessibilityAddTraits(option == theme ? .isSelected : [])
    }
}
