import Foundation

/// Display-only attribute marking a character sub-range whose glyphs the
/// editor's `NSLayoutManagerDelegate` should suppress (replace with
/// `.null` glyph property) so the syntax characters disappear from layout
/// while remaining present in the underlying `NSTextStorage`.
///
/// The styler tags ranges; the layout delegate consumes the tag. The
/// attribute is intentionally `Bool` so a single `attribute(at:)` lookup
/// in the layout delegate is enough — we never branch on a payload.
extension NSAttributedString.Key {
    public static let marcdownConcealed = NSAttributedString.Key("marcdownConcealed")

    /// Mirror of `.marcdownConcealed` that survives focus-line reveal.
    /// When the styler reveals the focused line, it strips
    /// `.marcdownConcealed` (so the layout delegate stops suppressing the
    /// glyphs) but leaves `.marcdownConcealedLogical` intact. The editor's
    /// arrow-key handler reads the logical flag to know whether to jump
    /// over a concealed run in one keystroke — even when the user is
    /// currently parked on that line (Thomas §1c).
    public static let marcdownConcealedLogical = NSAttributedString.Key("marcdownConcealedLogical")

    /// Tags the 3-char `[ ]` / `[x]` / `[X]` source range of a complete task
    /// marker. Value is a `MarcdownCheckboxState`. Read by the editor's
    /// custom layout manager to draw the icon and by the click handler to
    /// detect taps. Written exclusively by the line scanner pass in
    /// `MarkdownStyler.restyle`.
    public static let marcdownCheckbox = NSAttributedString.Key("marcdownCheckbox")

    /// Tags the source range of a complete plain list marker — either a
    /// bullet (`- `, `* `, `+ `) or an ordered marker (`1. `, `10. `, …).
    /// Value is a `MarcdownListMarkerKind`. Written exclusively by the
    /// list-scanner pass in `MarkdownStyler.restyle`; read by the editor's
    /// custom layout manager to draw the bullet circle or the ordered
    /// number overlay in place of the raw glyphs.
    public static let marcdownListMarker = NSAttributedString.Key("marcdownListMarker")

    /// Tags every character of a fenced code block (including the opening
    /// and closing fence lines themselves) with `true`. Value is a `Bool`.
    /// Written exclusively by `StyleWalker.visitCodeBlock` and read by the
    /// editor's custom layout manager to paint a single rounded container
    /// behind the block. Inline code spans are NOT tagged.
    public static let marcdownCodeBlock = NSAttributedString.Key("marcdownCodeBlock")

    /// Tags the label-text range of an inline link — the visible characters
    /// between `[` and `]` in `[text](url)`. Value is a `String` carrying
    /// the destination URL (may be empty for `[text]()`). Written
    /// exclusively by `StyleWalker.visitLink`; read by the editor's click
    /// handler in `mouseDown` to open the URL on Cmd+click.
    public static let marcdownLink = NSAttributedString.Key("marcdownLink")

    /// Tags every character of a blockquote (nested quotes share the run).
    /// Value is a `Bool`. Written by `StyleWalker.visitBlockQuote`; read by
    /// the editor's layout manager to draw one vertical bar beside the run.
    public static let marcdownBlockquote = NSAttributedString.Key("marcdownBlockquote")

    /// Tags the characters of a thematic break (`---`, `***`, `___`, spaced
    /// variants). Value is a `Bool`. Written by `StyleWalker.visitThematicBreak`;
    /// read by the layout manager to draw a rule; stripped on the focus line.
    public static let marcdownThematicBreak = NSAttributedString.Key("marcdownThematicBreak")
}

/// Kind of plain list marker tagged by the list-scanner pass.
///
/// `.bullet(depth:)` covers any of `-`, `*`, `+` followed by a single
/// space/tab. `depth` is the 0-indexed nesting depth derived from the
/// leading whitespace on the line (2-space-per-level or 1-tab-per-level
/// — see `ListLineScanner` / `ListIndentation`).
///
/// `.ordered(number:depth:)` carries the parsed integer that the layout
/// manager re-draws as the visible glyph (e.g. `"10."`) plus the same
/// depth value used for bullets.
public enum MarcdownListMarkerKind: Sendable, Equatable, Hashable {
    case bullet(depth: Int)
    case ordered(number: Int, depth: Int)
}

extension MarcdownListMarkerKind {
    /// Backwards-compatible factory for top-level bullets (depth 0).
    public static var bullet: MarcdownListMarkerKind { .bullet(depth: 0) }

    /// Backwards-compatible factory for top-level ordered items (depth 0).
    public static func ordered(number: Int) -> MarcdownListMarkerKind {
        .ordered(number: number, depth: 0)
    }
}
