import SwiftUI

/// The note editor sheet: the highlighted passage (serif, quoted) above a
/// plain text editor. Creation of the highlight happens before this opens —
/// the editor only writes the note text back via `onSave`.
struct NoteEditor: View {
    /// The highlighted passage shown above the editor for context.
    let quotedText: String
    @Binding var text: String
    var onSave: () -> Void
    /// Runs when Cancel is pressed. Create-mode hosts pass a closure that
    /// removes the highlight they just created for this note — otherwise a
    /// cancelled note strands a highlight the reader never asked to keep.
    /// Nil for plain edits of an existing highlight's note.
    var onCancel: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                if !quotedText.isEmpty {
                    Text("\u{201C}\(quotedText)\u{201D}")
                        .font(.callout)
                        .fontDesign(.serif)
                        .italic()
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
                TextEditor(text: $text)
                    .font(.body)
            }
            .padding()
            .navigationTitle("Note")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(); dismiss() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel?(); dismiss() }
                }
            }
        }
        #if os(macOS)
        // Sheets on macOS collapse to their ideal size without a floor.
        .frame(minWidth: 380, minHeight: 300)
        #endif
    }
}
