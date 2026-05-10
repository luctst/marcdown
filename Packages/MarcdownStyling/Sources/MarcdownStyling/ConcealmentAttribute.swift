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
}
