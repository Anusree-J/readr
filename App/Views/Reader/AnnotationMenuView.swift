import SwiftUI
import ReadrKit

/// The annotation popover content, Apple-Books style: five color dots that
/// highlight in ONE click, plus Note / Ask / Copy (and Remove when editing an
/// existing highlight). Shared by the text reader (NSPopover/iOS bar) and the
/// native PDF reader — keep it presentation-agnostic: no dismissal logic here,
/// hosts dismiss in the callbacks.
struct AnnotationMenuView: View {
    enum Mode: Equatable {
        /// A fresh selection: color click creates the highlight.
        case create
        /// An existing highlight: color click recolors it.
        case edit(currentColor: HighlightColor, hasNote: Bool)
    }

    let mode: Mode
    /// Create (or recolor) the highlight with this color.
    var onHighlight: (HighlightColor) -> Void
    /// Open the note editor (creates the highlight first when in create mode).
    var onNote: () -> Void
    /// Ask the book about this selection.
    var onAsk: () -> Void
    var onCopy: () -> Void
    /// Only shown in edit mode.
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            ForEach(HighlightColor.allCases, id: \.self) { color in
                colorDot(color)
            }

            Divider().frame(height: 18)

            actionButton(
                mode.hasNote ? "Edit Note" : "Note",
                systemImage: "note.text",
                identifier: "annotation.note",
                action: onNote
            )
            actionButton(
                "Ask", systemImage: "sparkles",
                identifier: "annotation.ask", action: onAsk
            )
            actionButton(
                "Copy", systemImage: "doc.on.doc",
                identifier: "annotation.copy", action: onCopy
            )
            if case .edit = mode, let onRemove {
                Divider().frame(height: 18)
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove highlight")
                .accessibilityLabel("Remove highlight")
                .accessibilityIdentifier("annotation.remove")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func colorDot(_ color: HighlightColor) -> some View {
        Button {
            onHighlight(color)
        } label: {
            ZStack {
                Circle()
                    .fill(ReadingTheme.markerSwatch(color))
                    .frame(width: 20, height: 20)
                if case let .edit(current, _) = mode, current == color {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.65), lineWidth: 2)
                        .frame(width: 26, height: 26)
                }
            }
            .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .help("Highlight \(color.displayName)")
        .accessibilityLabel("Highlight \(color.displayName)")
        .accessibilityIdentifier("annotation.color.\(color.rawValue)")
    }

    private func actionButton(
        _ title: String, systemImage: String, identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }
}

private extension AnnotationMenuView.Mode {
    var hasNote: Bool {
        if case let .edit(_, hasNote) = self { return hasNote }
        return false
    }
}
