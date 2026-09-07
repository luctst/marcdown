import AppKit

/// Every paragraph-style write in the pipeline goes through here so the
/// theme line height (set by the base pass) and any indent an earlier pass
/// wrote (quote → list → heading) survive the later pass instead of being
/// clobbered by a fresh `NSMutableParagraphStyle()`.
enum ParagraphStyling {
    /// Mutates a copy of the style found at `range.location` and applies it
    /// over `range`. The base pass in `MarkdownStyler.restyle` guarantees a
    /// style is present; the fallback is defensive only.
    static func mutate(
        in storage: NSTextStorage,
        range: NSRange,
        _ body: (NSMutableParagraphStyle) -> Void
    ) {
        guard range.length > 0, range.location < storage.length else { return }
        let existing = storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
        let style = (existing?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        body(style)
        storage.addAttribute(.paragraphStyle, value: style, range: range)
    }
}
