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
}
