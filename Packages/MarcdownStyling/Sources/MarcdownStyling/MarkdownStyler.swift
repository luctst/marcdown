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
    /// Wrapped in `beginEditing()`/`endEditing()` so layout is updated once and
    /// the cursor / selection is preserved. Only attributes are mutated; the
    /// character contents are never touched.
    public func restyle(
        storage: NSTextStorage,
        source: String
    ) {
        let document = Document(parsing: source)
        let index = LineOffsetIndex(source: source)
        let fullRange = NSRange(location: 0, length: storage.length)

        storage.beginEditing()
        // Reset to a clean baseline before walking the AST so stale attributes
        // from a previous pass don't leak through.
        storage.setAttributes(baseAttributes, range: fullRange)
        // `setAttributes` already clears `.marcdownConcealed` and
        // `.marcdownCheckbox`, but be explicit so that any future reset path
        // that switches to `addAttributes` still strips them.
        if fullRange.length > 0 {
            storage.removeAttribute(.marcdownConcealed, range: fullRange)
            storage.removeAttribute(.marcdownCheckbox, range: fullRange)
        }

        var walker = StyleWalker(
            storage: storage,
            theme: theme,
            baseFont: baseFont,
            index: index
        )
        walker.visit(document)

        // Single-source-of-truth pass for checkbox shape detection. Runs
        // after the AST walk so any attributes the AST tried to set on
        // task-list bullets are overwritten here.
        applyCheckboxScannerPass(storage: storage, source: source)

        storage.endEditing()
    }

    /// Walks `source` line-by-line, classifying each via `CheckboxLineScanner`,
    /// and tags `.marcdownConcealed` / `.marcdownCheckbox` accordingly. This
    /// is the only writer of `.marcdownCheckbox` in the entire pipeline.
    private func applyCheckboxScannerPass(storage: NSTextStorage, source: String) {
        let units = Array(source.utf16)
        let length = units.count
        var lineStart = 0
        while lineStart <= length {
            // Find lineEnd (the next `\n` or end of buffer).
            var lineEnd = lineStart
            while lineEnd < length, units[lineEnd] != 0x0A {
                lineEnd += 1
            }

            let lineLength = lineEnd - lineStart
            if lineLength > 0 {
                let lineSlice = Array(units[lineStart..<lineEnd])
                let line = lineSlice.withUnsafeBufferPointer {
                    String(utf16CodeUnits: $0.baseAddress!, count: $0.count)
                }
                applyCheckboxAttributes(
                    for: CheckboxLineScanner.scan(line: line),
                    storage: storage,
                    lineStart: lineStart,
                    lineLength: lineLength
                )
            }

            // Advance past the `\n` (or stop if past end).
            if lineEnd >= length { break }
            lineStart = lineEnd + 1
        }
    }

    private func applyCheckboxAttributes(
        for shape: CheckboxLineShape,
        storage: NSTextStorage,
        lineStart: Int,
        lineLength: Int
    ) {
        switch shape {
        case .none:
            return
        case .partial(let indentLength, let concealLength):
            guard concealLength > 0 else { return }
            let location = lineStart + indentLength
            let range = NSRange(location: location, length: concealLength)
            applyConceal(storage: storage, range: range)
            applyParagraphSpacing(storage: storage, lineStart: lineStart, lineLength: lineLength)
        case .complete(let indentLength, let bracketLocation, let state):
            // Conceal "- " (bullet + space) at start.
            applyConceal(
                storage: storage,
                range: NSRange(location: lineStart + indentLength, length: 2)
            )
            // Conceal `[` (zero advance — fully suppressed).
            applyConceal(
                storage: storage,
                range: NSRange(location: lineStart + bracketLocation, length: 1)
            )
            // Middle char (the space / x / X): explicitly NOT concealed, but
            // we hide its glyph by painting it clear so the icon painter has
            // a stable advance to anchor on. `.marcdownConcealed` removed
            // defensively in case a previous pass set it.
            let middleRange = NSRange(location: lineStart + bracketLocation + 1, length: 1)
            storage.removeAttribute(.marcdownConcealed, range: middleRange)
            storage.addAttribute(.foregroundColor, value: NSColor.clear, range: middleRange)

            // Close bracket `]`: NOT concealed — rendered `.clear` instead so
            // it contributes ~1 char of advance (visual breathing room
            // between the icon and the trailing cursor) without showing as a
            // glyph.
            let closeRange = NSRange(location: lineStart + bracketLocation + 2, length: 1)
            storage.removeAttribute(.marcdownConcealed, range: closeRange)
            storage.addAttribute(.foregroundColor, value: NSColor.clear, range: closeRange)

            // Tag the 3-char `[X]` range with the checkbox state.
            let markerRange = NSRange(location: lineStart + bracketLocation, length: 3)
            storage.addAttribute(.marcdownCheckbox, value: state, range: markerRange)

            // Force a monospaced font on the 3-char marker range so the
            // middle char's advance is identical for `' '`, `'x'`, and `'X'`.
            // Without this the proportional system font gives different
            // advances per state, shifting the painted icon on toggle.
            let markerFont = NSFont.monospacedSystemFont(
                ofSize: baseFont.pointSize,
                weight: .regular
            )
            storage.addAttribute(.font, value: markerFont, range: markerRange)

            applyParagraphSpacing(storage: storage, lineStart: lineStart, lineLength: lineLength)
        }
    }

    private func applyConceal(storage: NSTextStorage, range: NSRange) {
        let storageLength = storage.length
        let upper = min(range.location + range.length, storageLength)
        let lower = min(range.location, storageLength)
        guard upper > lower else { return }
        let clamped = NSRange(location: lower, length: upper - lower)
        storage.addAttribute(.marcdownConcealed, value: true, range: clamped)
    }

    private func applyParagraphSpacing(
        storage: NSTextStorage,
        lineStart: Int,
        lineLength: Int
    ) {
        let storageLength = storage.length
        let upper = min(lineStart + lineLength, storageLength)
        let lower = min(lineStart, storageLength)
        guard upper > lower else { return }
        let range = NSRange(location: lower, length: upper - lower)
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = 4
        storage.addAttribute(.paragraphStyle, value: style, range: range)
    }

    private var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: baseFont,
            .foregroundColor: theme.body,
        ]
    }
}
