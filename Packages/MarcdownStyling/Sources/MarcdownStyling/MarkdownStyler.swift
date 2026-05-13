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
    /// Exposed so callers (e.g. the editor's layout manager) can read the
    /// same theme the styler used to write attributes — keeps the rounded
    /// code-block container fill in sync with the styler's other colors.
    public let theme: StylingTheme
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
            storage.removeAttribute(.marcdownListMarker, range: fullRange)
            storage.removeAttribute(.marcdownCodeBlock, range: fullRange)
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

        // Single-source-of-truth pass for plain list-marker shape detection
        // (bullet and ordered). Runs after the checkbox pass so checkbox
        // lines are already owned and we skip them here. Also runs after
        // the AST walk so any AST-applied attributes get overwritten.
        applyListScannerPass(storage: storage, source: source)

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

    /// Walks `source` line-by-line. For each line, defers to
    /// `CheckboxLineScanner` first — if that line is any kind of checkbox
    /// (partial or complete), the checkbox pass already owns its attributes
    /// and this pass leaves it alone. Otherwise, classifies via
    /// `ListLineScanner` and applies the glyph-strategy attributes for plain
    /// bullet / ordered markers. This is the only writer of
    /// `.marcdownListMarker` in the entire pipeline.
    private func applyListScannerPass(storage: NSTextStorage, source: String) {
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
                // Checkbox precedence with one exception: a `.complete`
                // list shape (the user has a real `- ` / `1. ` marker)
                // wins over a checkbox `.partial` — without this carve-out
                // the line `- ` (typed but no `[` yet) would stay dimly
                // concealed by the checkbox partial branch and never get
                // its bullet anchor / marker tag. A `.complete` checkbox
                // (`- [ ]` / `- [x]`) is owned by the checkbox pass
                // exclusively.
                let checkboxShape = CheckboxLineScanner.scan(line: line)
                let listShape = ListLineScanner.scan(line: line)
                let listOverrides: Bool
                switch (checkboxShape, listShape) {
                case (.none, _):
                    listOverrides = true
                case (.partial, .complete):
                    listOverrides = true
                default:
                    listOverrides = false
                }
                if listOverrides {
                    applyListAttributes(
                        for: listShape,
                        storage: storage,
                        lineStart: lineStart,
                        lineLength: lineLength
                    )
                }
            }

            // Advance past the `\n` (or stop if past end).
            if lineEnd >= length { break }
            lineStart = lineEnd + 1
        }
    }

    private func applyListAttributes(
        for shape: ListLineShape,
        storage: NSTextStorage,
        lineStart: Int,
        lineLength: Int
    ) {
        switch shape {
        case .none:
            return
        case .partial:
            // No styling on partial markers — let them render as raw text. The user
            // expects to see what they type (`1`, `1.`, `-`, etc.) until the marker
            // is complete. Concealment / clear-paint during the partial state hides
            // the chars and either collapses the line or shows nothing, which makes
            // the cursor appear to misbehave. Once the trailing space lands and the
            // scanner returns `.complete`, the proper marker treatment kicks in.
            applyParagraphSpacing(storage: storage, lineStart: lineStart, lineLength: lineLength)
        case .complete(let indentLength, let markerLength, let kind):
            switch kind {
            case .bullet:
                // Marker layout is `<char><space>` (exactly 2 chars).
                let markerRange = NSRange(
                    location: lineStart + indentLength,
                    length: markerLength
                )
                // Marker chars: paint `.clear` (NOT concealed — they must
                // contribute their advance so the bullet icon has horizontal
                // room without bleeding into the body text). The dash was
                // previously concealed (`.null` glyph, zero advance), which
                // collapsed the marker footprint to just the proportional
                // space's ~4-5px box — the centred circle then overlapped the
                // first body character. Force a monospaced font so the
                // per-char advance is wide and stable. Mirrors the checkbox
                // marker treatment above.
                storage.removeAttribute(.marcdownConcealed, range: markerRange)
                storage.addAttribute(.foregroundColor, value: NSColor.clear, range: markerRange)
                let markerFont = NSFont.monospacedSystemFont(
                    ofSize: baseFont.pointSize,
                    weight: .regular
                )
                storage.addAttribute(.font, value: markerFont, range: markerRange)

                // Tag the 2-char marker range so the layout manager can paint
                // the bullet glyph.
                storage.addAttribute(
                    .marcdownListMarker,
                    value: MarcdownListMarkerKind.bullet,
                    range: markerRange
                )

                applyParagraphSpacing(storage: storage, lineStart: lineStart, lineLength: lineLength)
            case .ordered(let number):
                // Marker layout is `<digits>.<space>` — markerLength = digits + 2.
                let digitCount = markerLength - 2
                guard digitCount > 0 else { return }

                // Marker chars (digits + `.` + space): paint `.clear` (NOT
                // concealed — they must contribute their advance so the overlay
                // `"<N>."` has horizontal room without bleeding into body text).
                // Concealing the `.` and trailing space would shrink the marker
                // footprint to just the digit advances; the overlay (digits + a
                // period) is wider than that and would overlap body text on the
                // right. Mirrors the `.complete .bullet` treatment immediately
                // above — clear-paint over a monospaced font for a stable, wide
                // footprint anchored by `.marcdownListMarker`.
                let markerRange = NSRange(
                    location: lineStart + indentLength,
                    length: markerLength
                )
                storage.removeAttribute(.marcdownConcealed, range: markerRange)
                storage.addAttribute(.foregroundColor, value: NSColor.clear, range: markerRange)
                let monospaced = NSFont.monospacedSystemFont(
                    ofSize: baseFont.pointSize,
                    weight: .regular
                )
                storage.addAttribute(.font, value: monospaced, range: markerRange)

                // Tag the full marker range with the ordered kind.
                storage.addAttribute(
                    .marcdownListMarker,
                    value: MarcdownListMarkerKind.ordered(number: number),
                    range: markerRange
                )

                applyParagraphSpacing(storage: storage, lineStart: lineStart, lineLength: lineLength)
            }
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
