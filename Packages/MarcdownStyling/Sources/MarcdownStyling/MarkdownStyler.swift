import AppKit
import Markdown

/// Styles markdown source into an `NSAttributedString` (or restyles an existing
/// `NSTextStorage` in place) for Live-Preview-style rendering.
///
/// The styler never edits characters — only attributes. The raw markdown
/// syntax (`#`, `*`, `_`, `~~`, etc.) stays in the buffer and is dimmed via
/// the theme so the user can keep editing in plain markdown.
@MainActor
public final class MarkdownStyler {
    private let theme: StylingTheme
    private let baseFont: NSFont

    public init(theme: StylingTheme = .system, baseFont: NSFont = .systemFont(ofSize: 14)) {
        self.theme = theme
        self.baseFont = baseFont
    }

    /// Returns a freshly-styled attributed string for `source`.
    public func attributedString(for source: String) -> NSAttributedString {
        let storage = NSTextStorage(string: source)
        restyle(storage: storage, source: source)
        return NSAttributedString(attributedString: storage)
    }

    /// Re-applies styling attributes to `storage` in place.
    ///
    /// `source` should equal `storage.string`. We accept it as a parameter so
    /// the caller can avoid an extra `String` materialization on every
    /// keystroke when they already have the source on hand.
    ///
    /// `revealedLineRange`, when non-nil, identifies a single line (typically
    /// the line containing the user's caret) whose syntax markers must NOT be
    /// concealed even if they would otherwise qualify. This is what powers the
    /// Bear/Typora reveal-on-cursor behavior. `nil` means "conceal everywhere".
    ///
    /// Wrapped in `beginEditing()`/`endEditing()` so layout is updated once and
    /// the cursor / selection is preserved. Only attributes are mutated; the
    /// character contents are never touched.
    public func restyle(
        storage: NSTextStorage,
        source: String,
        revealedLineRange: NSRange? = nil
    ) {
        let document = Document(parsing: source)
        let index = LineOffsetIndex(source: source)
        let fullRange = NSRange(location: 0, length: storage.length)

        storage.beginEditing()
        // Reset to a clean baseline before walking the AST so stale attributes
        // from a previous pass don't leak through.
        storage.setAttributes(baseAttributes, range: fullRange)
        // `setAttributes` already clears `.marcdownConcealed`, but be explicit
        // — if a future change adds another reset path that uses `addAttributes`
        // instead, we want the conceal flag explicitly stripped here.
        if fullRange.length > 0 {
            storage.removeAttribute(.marcdownConcealed, range: fullRange)
        }

        var walker = StyleWalker(
            storage: storage,
            theme: theme,
            baseFont: baseFont,
            index: index,
            revealedLineRange: revealedLineRange
        )
        walker.visit(document)
        storage.endEditing()
    }

    private var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: baseFont,
            .foregroundColor: theme.body,
        ]
    }
}
