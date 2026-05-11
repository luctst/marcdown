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

    /// Tags the full source range of a fenced code block (opening fence,
    /// body, and closing fence). Value is `Bool`. Written by
    /// `StyleWalker.visitCodeBlock`; read by
    /// `MarkdownStyler.updateFenceVisibility` to locate which block contains
    /// the cursor so its fence markers can be revealed.
    public static let marcdownCodeBlock = NSAttributedString.Key("marcdownCodeBlock")

    /// Tags only the opening and closing fence marker lines of a fenced code
    /// block (the ` ``` ` / ` ```swift ` lines). Value is `Bool`. Written by
    /// `StyleWalker.visitCodeBlock`; read by
    /// `MarkdownStyler.updateFenceVisibility` to know which sub-ranges to
    /// paint clear (hidden) or dim (revealed when the cursor is inside).
    public static let marcdownCodeFence = NSAttributedString.Key("marcdownCodeFence")
}

/// Kind of plain list marker tagged by the list-scanner pass.
///
/// `.bullet` covers any of `-`, `*`, `+` followed by a single space/tab.
/// `.ordered(number:)` carries the parsed integer that the layout manager
/// re-draws as the visible glyph (e.g. `"10."`).
public enum MarcdownListMarkerKind: Sendable, Equatable, Hashable {
    case bullet
    case ordered(number: Int)
}
