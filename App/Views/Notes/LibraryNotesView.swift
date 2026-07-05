import SwiftUI
import ReadrKit

/// "Highlights & Notes" — the library-wide review home (docs/DESIGN.md):
/// every annotated book in a picker, its annotations full-window beside it,
/// with the same Create Article + Export header as the in-reader Notes panel.
/// This screen exists so annotations are reviewable without opening a book.
struct LibraryNotesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedBookID: UUID?
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    init() {}

    private var annotatedBooks: [Book] {
        model.books.filter { annotationCount(for: $0) > 0 }
    }

    /// The picked book, falling back to the first annotated one so the detail
    /// pane never sits on a stale selection (e.g. after a delete).
    private var selectedBook: Book? {
        annotatedBooks.first { $0.id == selectedBookID } ?? annotatedBooks.first
    }

    var body: some View {
        Group {
            if annotatedBooks.isEmpty {
                ContentUnavailableView {
                    Label("Nothing highlighted yet", systemImage: "highlighter")
                } description: {
                    Text("Select text in any book and pick a color — your highlights and notes gather here, ready to export or turn into an article.")
                }
            } else {
                #if os(iOS)
                if horizontalSizeClass == .compact {
                    compactLayout
                } else {
                    paneLayout
                }
                #else
                paneLayout
                #endif
            }
        }
        .navigationTitle("Highlights & Notes")
    }

    // MARK: Layouts

    /// Wide: book picker column on the left, annotation review on the right.
    private var paneLayout: some View {
        HStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(annotatedBooks) { book in
                        Button {
                            selectedBookID = book.id
                        } label: {
                            bookRow(book, isSelected: book.id == selectedBook?.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
            .frame(width: 250)
            Divider()
            if let book = selectedBook {
                detail(for: book)
                    // Reset the list's filter/search state per book.
                    .id(book.id)
            }
        }
    }

    /// Compact (iPhone): book picker as a horizontal cover strip on top.
    private var compactLayout: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(annotatedBooks) { book in
                        Button {
                            selectedBookID = book.id
                        } label: {
                            compactBookCard(book, isSelected: book.id == selectedBook?.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            Divider()
            if let book = selectedBook {
                detail(for: book)
                    .id(book.id)
            }
        }
    }

    // MARK: Detail (shared list + actions header)

    private func detail(for book: Book) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(book.metadata.title)
                    .font(.title3.bold())
                    .fontDesign(.serif)
                if !book.metadata.authors.isEmpty {
                    Text(book.metadata.authors.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            NotesHeaderActions(book: book)
            // Review-only surface: no reader window to jump into, so no
            // jump callbacks (per docs/DESIGN.md the in-book panel does that).
            AnnotationListView(book: book)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Picker rows

    private func bookRow(_ book: Book, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            cover(for: book, width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(book.metadata.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(annotationLabel(for: book))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .contentShape(Rectangle())
        .background(
            isSelected ? AppTheme.accent.opacity(0.15) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private func compactBookCard(_ book: Book, isSelected: Bool) -> some View {
        VStack(spacing: 4) {
            cover(for: book, width: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(isSelected ? AppTheme.accent : .clear, lineWidth: 2)
                )
            Text(book.metadata.title)
                .font(.caption2)
                .lineLimit(1)
                .frame(width: 64)
        }
    }

    /// Cover thumbnail: real artwork when available, else the deterministic
    /// gradient placeholder used across the app.
    @ViewBuilder
    private func cover(for book: Book, width: CGFloat) -> some View {
        Group {
            if let image = model.coverImage(for: book) {
                #if canImport(UIKit)
                Image(uiImage: image).resizable()
                #else
                Image(nsImage: image).resizable()
                #endif
            } else {
                LinearGradient(
                    colors: AppTheme.coverGradient(for: book.metadata.title),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .overlay(
                    Text(String(book.metadata.title.prefix(1)))
                        .font(.system(size: width * 0.45, design: .serif))
                        .foregroundStyle(.white.opacity(0.85))
                )
            }
        }
        .aspectRatio(2 / 3, contentMode: .fill)
        .frame(width: width, height: width * 1.5)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    // MARK: Counts

    private func annotationCount(for book: Book) -> Int {
        model.highlights(for: book).count + model.pdfHighlights(for: book).count
    }

    private func annotationLabel(for book: Book) -> String {
        let count = annotationCount(for: book)
        return count == 1 ? "1 annotation" : "\(count) annotations"
    }
}
