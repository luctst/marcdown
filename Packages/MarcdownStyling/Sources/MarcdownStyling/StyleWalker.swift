import AppKit
import Markdown

/// Walks a `swift-markdown` AST and applies AppKit attributes to a shared
/// `NSTextStorage`. Never replaces characters — only mutates attributes.
///
/// The raw markdown syntax (fences, asterisks, hashes, etc.) is intentionally
/// preserved in the buffer and dimmed, mirroring the Typora / Obsidian
/// Live-Preview editing model.
@MainActor
struct StyleWalker: @preconcurrency MarkupWalker {
    // The walker is a struct because `MarkupVisitor` declares its visit methods
    // `mutating`. None of our state actually mutates — it's all references —
    // but the protocol requirement forces this shape.
    private let storage: NSTextStorage
    private let theme: StylingTheme
    private let baseFont: NSFont
    private let index: LineOffsetIndex
    private let monoCellWidth: CGFloat

    init(
        storage: NSTextStorage,
        theme: StylingTheme,
        baseFont: NSFont,
        index: LineOffsetIndex
    ) {
        self.storage = storage
        self.theme = theme
        self.baseFont = baseFont
        self.index = index
        let mono = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
        self.monoCellWidth = ("0" as NSString).size(withAttributes: [.font: mono]).width
    }

    // MARK: - Blocks

    mutating func visitHeading(_ heading: Heading) {
        guard let range = index.nsRange(heading.range), range.length > 0 else {
            descendInto(heading)
            return
        }

        // Bare hashes with no trailing space (e.g. just `#`) are not visually
        // a heading yet — keep them plain so the user sees the character they
        // just typed. The parser still classifies them as an empty H1, but we
        // refuse to style until a trailing space confirms heading intent.
        let atxMarker = atxHeadingMarker(in: range)
        if let marker = atxMarker, !marker.hasTrailingSpace {
            descendInto(heading)
            return
        }

        addAttributes([.font: headingFont(for: heading.level)], range: range)
        ParagraphStyling.mutate(in: storage, range: clampedToStorage(range)) { style in
            style.paragraphSpacingBefore = headingSpacingBefore(for: heading.level)
            style.paragraphSpacing = 4
        }

        // ATX heading marker concealment — only for ATX (`# `, `## ` …).
        // Setext headings (`====` / `----` underlines) report a multi-line
        // range whose first character is not `#`; the prefix scan above will
        // simply find no `#` and return nil.
        if let marker = atxMarker {
            let markerRange = marker.range
            if markerRange.length < range.length {
                // Non-empty heading: body text follows the marker, the line has
                // a visible width so concealment is safe.
                applyConceal(to: markerRange)
            } else {
                // Empty heading with trailing space (`# ` with no body).
                // Concealment via .null glyphs would collapse the line to zero
                // width — the visible cursor would snap up to the previous
                // line while the user is typing the marker. Clear-paint +
                // monospaced keeps the marker invisible but gives the line a
                // real advance so the cursor stays put. Same treatment as the
                // bullet / ordered complete markers in
                // `MarkdownStyler.applyListAttributes`.
                let monospaced = NSFont.monospacedSystemFont(
                    ofSize: baseFont.pointSize,
                    weight: .regular
                )
                let clamped = clampedToStorage(markerRange)
                if clamped.length > 0 {
                    storage.removeAttribute(.marcdownConcealed, range: clamped)
                    storage.addAttribute(.foregroundColor, value: NSColor.clear, range: clamped)
                    storage.addAttribute(.font, value: monospaced, range: clamped)
                }
            }
        }

        descendInto(heading)
    }

    /// Result of scanning a heading range for its ATX marker.
    private struct AtxMarker {
        /// Range covering the `#`s plus the trailing space/tab if present.
        let range: NSRange
        /// True if a space or tab follows the hashes (heading intent
        /// confirmed). False for bare `###` with no trailing whitespace or
        /// end-of-line yet — still a parser-classified heading, but visually
        /// indistinguishable from plain text until the user commits.
        let hasTrailingSpace: Bool
    }

    /// Scans the leading characters of a heading's storage range for an ATX
    /// marker: 1-6 `#` characters optionally followed by one space/tab.
    ///
    /// Returns `nil` if no valid ATX marker is present (e.g. setext heading
    /// or somehow malformed input).
    private func atxHeadingMarker(in headingRange: NSRange) -> AtxMarker? {
        let storageString = storage.string as NSString
        let upper = headingRange.location + headingRange.length
        guard upper <= storageString.length else { return nil }

        var hashCount = 0
        var probe = headingRange.location
        while probe < upper, hashCount < 6 {
            let unit = storageString.character(at: probe)
            // 0x23 == '#'
            guard unit == 0x23 else { break }
            hashCount += 1
            probe += 1
        }
        guard hashCount >= 1 else { return nil }

        // Per CommonMark, ATX hashes must be followed by a space, tab, or end
        // of line. swift-markdown's parser already enforced "this is a
        // heading", so end-of-storage and newline are valid terminators — but
        // those cases are "bare hashes, no trailing space" which the caller
        // treats as visually plain.
        var markerLength = hashCount
        var hasTrailingSpace = false
        if probe < upper {
            let trailing = storageString.character(at: probe)
            // 0x20 space, 0x09 tab, 0x0A newline, 0x0D CR
            if trailing == 0x20 || trailing == 0x09 {
                markerLength += 1
                hasTrailingSpace = true
            } else if trailing == 0x0A || trailing == 0x0D {
                // Empty heading, no trailing space yet.
            } else {
                // Not a valid ATX marker — bail. Shouldn't happen given the
                // parser said "heading", but be defensive.
                return nil
            }
        }

        return AtxMarker(
            range: NSRange(location: headingRange.location, length: markerLength),
            hasTrailingSpace: hasTrailingSpace
        )
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        guard let range = index.nsRange(blockQuote.range), range.length > 0 else {
            descendInto(blockQuote)
            return
        }
        let clamped = clampedToStorage(range)
        guard clamped.length > 0 else {
            descendInto(blockQuote)
            return
        }
        storage.addAttribute(.marcdownBlockquote, value: true, range: clamped)
        styleBlockquoteLines(in: clamped)
        descendInto(blockQuote)
    }

    /// Per line of the quote: clear-paint the leading `>` run (monospaced so
    /// it keeps a stable advance — the same treatment as list markers) and
    /// hang the body under the first visible character. Lazy-continuation
    /// lines with no marker get the same head indent so they align. Lines
    /// are walked from their true start so a nested quote's visit (whose
    /// node range begins mid-line) recomputes the same full-line prefix.
    private func styleBlockquoteLines(in blockRange: NSRange) {
        let storageString = storage.string as NSString
        let upper = blockRange.location + blockRange.length
        var lineStart = blockRange.location
        while lineStart > 0, storageString.character(at: lineStart - 1) != 0x0A {
            lineStart -= 1
        }
        let mono = monospacedFont()
        var lastMarkerLength = 0
        while lineStart < upper {
            var lineEnd = lineStart
            while lineEnd < upper, storageString.character(at: lineEnd) != 0x0A {
                lineEnd += 1
            }
            let lineRange = NSRange(location: lineStart, length: lineEnd - lineStart)
            if lineRange.length > 0 {
                let markerLength = blockquoteMarkerLength(at: lineRange, in: storageString)
                if markerLength > 0 {
                    let markerRange = NSRange(location: lineStart, length: markerLength)
                    storage.removeAttribute(.marcdownConcealed, range: markerRange)
                    storage.addAttributes([.foregroundColor: NSColor.clear, .font: mono], range: markerRange)
                    lastMarkerLength = markerLength
                }
                let hang = CGFloat(lastMarkerLength) * monoCellWidth
                ParagraphStyling.mutate(in: storage, range: lineRange) { style in
                    style.headIndent = hang
                    style.firstLineHeadIndent = markerLength > 0 ? 0 : hang
                }
            }
            if lineEnd >= upper { break }
            lineStart = lineEnd + 1
        }
    }

    /// UTF-16 length of the leading quote prefix: up to 3 spaces, then one
    /// or more `>` each optionally followed by a space (`> `, `>> `, `> > `).
    /// 0 when the line carries no marker.
    private func blockquoteMarkerLength(at lineRange: NSRange, in storageString: NSString) -> Int {
        let upper = lineRange.location + lineRange.length
        var probe = lineRange.location
        var leading = 0
        while probe < upper, leading < 3, storageString.character(at: probe) == 0x20 {
            probe += 1
            leading += 1
        }
        var sawMarker = false
        // 0x3E == '>'
        while probe < upper, storageString.character(at: probe) == 0x3E {
            sawMarker = true
            probe += 1
            if probe < upper, storageString.character(at: probe) == 0x20 {
                probe += 1
            }
        }
        return sawMarker ? probe - lineRange.location : 0
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        guard let range = index.nsRange(codeBlock.range), range.length > 0 else { return }

        // Monospace the whole block (fences + body). The rounded container
        // is painted by the layout manager from `.marcdownCodeBlock`; setting
        // `.backgroundColor` here would render per-glyph rectangles under
        // the rounded fill and bleed past its edges. The container alone
        // owns the background.
        addAttributes([.font: monospacedFont()], range: range)
        // 14pt of horizontal text inset on each side so the code text and
        // fence lines sit comfortably inside the rounded container the
        // layout manager paints from `.marcdownCodeBlock`. `tailIndent`
        // is negative per AppKit convention (offset from the trailing
        // edge of the text container).
        ParagraphStyling.mutate(in: storage, range: clampedToStorage(range)) { style in
            style.paragraphSpacingBefore = 8
            style.paragraphSpacing = 8
            style.firstLineHeadIndent = 14
            style.headIndent = 14
            style.tailIndent = -14
        }

        // Tag the entire block (including fence lines) so the layout
        // manager can locate the run and draw a single rounded container.
        let clamped = clampedToStorage(range)
        if clamped.length > 0 {
            storage.addAttribute(.marcdownCodeBlock, value: true, range: clamped)
        }

        // Conceal the fence lines. Walk line-by-line through the block; a
        // fence is a line whose first non-whitespace run is ``` or ~~~
        // followed by an optional info string. The AST guarantees we have a
        // fenced block, so the first and last lines of the range are fences.
        concealFenceLines(in: clamped, language: codeBlock.language)
    }

    /// Fence lines are clear-painted (monospaced already, so they keep an
    /// advance and the caret can land on them) and the first one carries the
    /// language tag. Focus-line reveal flips them to dim so the user still
    /// sees ```` ``` ```` while editing that line.
    ///
    /// Only the first and last lines of the block are candidates: body lines
    /// may legitimately look like fences (```` ``` ```` inside a four-backtick
    /// block, `~~~` inside a backtick block) and must stay visible. Each
    /// candidate still has to pass `isFenceLine`, because an unterminated
    /// block at EOF ends on a body line.
    private func concealFenceLines(in blockRange: NSRange, language: String?) {
        guard blockRange.length > 0 else { return }
        let storageString = storage.string as NSString
        let lower = blockRange.location
        var upper = lower + blockRange.length
        // A trailing newline terminates the closing fence line; it is not an
        // empty last line.
        if storageString.character(at: upper - 1) == 0x0A {
            upper -= 1
        }

        var firstEnd = lower
        while firstEnd < upper, storageString.character(at: firstEnd) != 0x0A {
            firstEnd += 1
        }
        let firstLine = NSRange(location: lower, length: firstEnd - lower)
        if isFenceLine(at: firstLine, in: storageString) {
            storage.removeAttribute(.marcdownConcealed, range: firstLine)
            storage.addAttribute(.foregroundColor, value: NSColor.clear, range: firstLine)
            if let language, !language.isEmpty {
                storage.addAttribute(.marcdownCodeLanguage, value: language, range: firstLine)
            }
        }

        var lastStart = upper
        while lastStart > lower, storageString.character(at: lastStart - 1) != 0x0A {
            lastStart -= 1
        }
        let lastLine = NSRange(location: lastStart, length: upper - lastStart)
        if lastLine.location > firstLine.location, isFenceLine(at: lastLine, in: storageString) {
            storage.removeAttribute(.marcdownConcealed, range: lastLine)
            storage.addAttribute(.foregroundColor, value: NSColor.clear, range: lastLine)
        }
    }

    /// Returns true if the storage characters in `lineRange` form a CommonMark
    /// fence: up to 3 leading spaces, then a run of 3+ backticks or tildes,
    /// then optional info-string text. Trailing whitespace is ignored.
    private func isFenceLine(at lineRange: NSRange, in storageString: NSString) -> Bool {
        let upper = lineRange.location + lineRange.length
        var probe = lineRange.location

        // Up to 3 leading spaces.
        var leadingSpaces = 0
        while probe < upper, leadingSpaces < 4,
            storageString.character(at: probe) == 0x20
        {
            probe += 1
            leadingSpaces += 1
        }
        guard leadingSpaces < 4, probe < upper else { return false }

        let fenceChar = storageString.character(at: probe)
        // 0x60 backtick, 0x7E tilde.
        guard fenceChar == 0x60 || fenceChar == 0x7E else { return false }

        var fenceCount = 0
        while probe < upper, storageString.character(at: probe) == fenceChar {
            fenceCount += 1
            probe += 1
        }
        return fenceCount >= 3
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        guard let range = index.nsRange(thematicBreak.range), range.length > 0 else { return }
        let clamped = clampedToStorage(range)
        guard clamped.length > 0 else { return }
        // Clear-paint (never `.null`-conceal): the rule is the whole line, so
        // it must keep an advance for the caret to land on. The layout
        // manager draws the rule in its place.
        storage.removeAttribute(.marcdownConcealed, range: clamped)
        storage.addAttributes(
            [
                .foregroundColor: NSColor.clear,
                .font: monospacedFont(),
                .marcdownThematicBreak: true,
            ],
            range: clamped
        )
        ParagraphStyling.mutate(in: storage, range: clamped) { style in
            style.paragraphSpacingBefore = 8
            style.paragraphSpacing = 8
        }
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
        descendInto(unorderedList)
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) {
        descendInto(orderedList)
    }

    mutating func visitListItem(_ listItem: ListItem) {
        // List markers — both checkbox (`- [ ]` / `- [x]`) and plain
        // (`- foo` / `1. foo`) — are owned by the scanner passes in
        // `MarkdownStyler.restyle`, run after this AST walk. The AST is no
        // longer the source of truth for list-marker concealment. We still
        // descend so inline styling of body text (bold, italic, links, …)
        // continues to apply.
        descendInto(listItem)
    }

    mutating func visitTable(_ table: Table) {
        // Tables are not styled in this slice. Fall back to a monospaced font
        // over the whole block so the pipes remain readable. Do not descend —
        // per-cell styling would fight with the coarse monospace treatment.
        guard let range = index.nsRange(table.range), range.length > 0 else { return }
        addAttributes([.font: monospacedFont()], range: range)
    }

    // MARK: - Inlines

    mutating func visitStrong(_ strong: Strong) {
        applyTraitOverInlineRange(strong, trait: .boldFontMask)
        if let range = index.nsRange(strong.range) {
            concealFixedDelimiters(in: range, length: 2)
        }
        descendInto(strong)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        applyTraitOverInlineRange(emphasis, trait: .italicFontMask)
        if let range = index.nsRange(emphasis.range) {
            concealFixedDelimiters(in: range, length: 1)
        }
        descendInto(emphasis)
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
        guard let range = index.nsRange(strikethrough.range), range.length > 0 else {
            descendInto(strikethrough)
            return
        }
        addAttributes(
            [
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: theme.body,
            ],
            range: range
        )
        concealFixedDelimiters(in: range, length: 2)
        descendInto(strikethrough)
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        guard let range = index.nsRange(inlineCode.range), range.length > 0 else { return }
        addAttributes(
            [
                .font: monospacedFont(),
                .backgroundColor: theme.codeBackground,
            ],
            range: range
        )
        concealInlineCodeDelimiters(in: range)
    }

    /// Conceals leading and trailing delimiter sub-ranges of fixed length
    /// (2 for `**`/`__`/`~~`, 1 for `*`/`_`).
    private func concealFixedDelimiters(in nodeRange: NSRange, length: Int) {
        guard nodeRange.length >= length * 2 else { return }
        let opening = NSRange(location: nodeRange.location, length: length)
        let closing = NSRange(
            location: nodeRange.location + nodeRange.length - length,
            length: length
        )
        applyConceal(to: opening)
        applyConceal(to: closing)
    }

    /// Conceals the leading and trailing backtick runs of an inline code
    /// span. cmark guarantees the closing run matches the opening run length.
    private func concealInlineCodeDelimiters(in nodeRange: NSRange) {
        let storageString = storage.string as NSString
        guard nodeRange.length > 0 else { return }
        let upper = nodeRange.location + nodeRange.length
        guard upper <= storageString.length else { return }

        // Count leading backticks.
        var openingLength = 0
        while nodeRange.location + openingLength < upper,
            storageString.character(at: nodeRange.location + openingLength) == 0x60  // '`'
        {
            openingLength += 1
        }
        guard openingLength > 0, nodeRange.length >= openingLength * 2 else { return }

        let opening = NSRange(location: nodeRange.location, length: openingLength)
        let closing = NSRange(
            location: nodeRange.location + nodeRange.length - openingLength,
            length: openingLength
        )
        applyConceal(to: opening)
        applyConceal(to: closing)
    }

    mutating func visitLink(_ link: Link) {
        guard let nodeRange = index.nsRange(link.range), nodeRange.length > 0 else {
            descendInto(link)
            return
        }

        // A well-formed inline link is `[label](destination)`. Locate the
        // `](` that separates label from destination so we can style the
        // label and conceal the surrounding syntax independently. Reference
        // / autolink / malformed shapes fall through to the legacy
        // accent+underline treatment over the full range.
        let storageString = storage.string as NSString
        let upper = min(nodeRange.location + nodeRange.length, storageString.length)
        let labelStart = nodeRange.location + 1
        var bracketIndex: Int? = nil
        if labelStart <= upper {
            var probe = labelStart
            // Need room for both `]` and `(` so stop one short of upper.
            while probe < upper - 1 {
                // 0x5D == ']', 0x28 == '('
                if storageString.character(at: probe) == 0x5D,
                    storageString.character(at: probe + 1) == 0x28
                {
                    bracketIndex = probe
                    break
                }
                probe += 1
            }
        }

        guard let bracket = bracketIndex else {
            // Fallback: malformed shape (reference link, autolink, etc.).
            addAttributes(
                [
                    .foregroundColor: theme.accent,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ],
                range: nodeRange
            )
            descendInto(link)
            return
        }

        // Label spans `[` (exclusive) up to `]` (exclusive). May be empty
        // for `[](url)`.
        let labelRange = NSRange(location: labelStart, length: bracket - labelStart)
        if labelRange.length > 0 {
            addAttributes(
                [
                    .foregroundColor: theme.accent,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .marcdownLink: link.destination ?? "",
                ],
                range: labelRange
            )
        }

        // Opening `[`.
        applyConceal(to: NSRange(location: nodeRange.location, length: 1))

        // Trailing `](destination)` runs from `]` to the end of the node.
        let tailLocation = bracket
        let tailLength = (nodeRange.location + nodeRange.length) - tailLocation
        if tailLength > 0 {
            applyConceal(to: NSRange(location: tailLocation, length: tailLength))
        }

        descendInto(link)
    }

    mutating func visitImage(_ image: Image) {
        guard let range = index.nsRange(image.range), range.length > 0 else { return }
        addAttributes([.foregroundColor: theme.accent], range: range)
    }

    // MARK: - Helpers

    private func headingSize(for level: Int) -> CGFloat {
        // Scale anchored on baseFont.pointSize so callers can inject any base
        // size and the heading hierarchy tracks it.
        let base = baseFont.pointSize
        switch level {
        case 1: return base + 10
        case 2: return base + 7
        case 3: return base + 4
        case 4: return base + 2
        case 5: return base + 1
        default: return base
        }
    }

    /// Headings share the body font family (Avenir Next by default) at the
    /// theme scale, bolded. Falling back to the system font here is what made
    /// headings look pasted in from another app.
    private func headingFont(for level: Int) -> NSFont {
        let manager = NSFontManager.shared
        let sized = manager.convert(baseFont, toSize: headingSize(for: level))
        return manager.convert(sized, toHaveTrait: .boldFontMask)
    }

    private func headingSpacingBefore(for level: Int) -> CGFloat {
        switch level {
        case 1: return 16
        case 2: return 12
        case 3: return 8
        default: return 6
        }
    }

    private func monospacedFont() -> NSFont {
        .monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
    }

    private func applyTraitOverInlineRange(_ markup: some Markup, trait: NSFontTraitMask) {
        guard let range = index.nsRange(markup.range), range.length > 0 else { return }
        let manager = NSFontManager.shared
        // Walk the range enumerating the current font (which may already have
        // bold applied by an outer node, so we compose traits instead of
        // clobbering them).
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let current = (value as? NSFont) ?? baseFont
            let combined = manager.convert(current, toHaveTrait: trait)
            storage.addAttribute(.font, value: combined, range: subrange)
        }
    }

    private func addAttributes(_ attrs: [NSAttributedString.Key: Any], range: NSRange) {
        guard range.length > 0 else { return }
        let clamped = clampedToStorage(range)
        guard clamped.length > 0 else { return }
        storage.addAttributes(attrs, range: clamped)
    }

    /// Tags `subrange` with `.marcdownConcealed = true` so the editor's
    /// layout delegate will suppress the corresponding glyphs. Also tags
    /// `.marcdownConcealedLogical` for the arrow-jump helper (see
    /// `NSAttributedString.Key.marcdownConcealedLogical`).
    private func applyConceal(to subrange: NSRange) {
        let clamped = clampedToStorage(subrange)
        guard clamped.length > 0 else { return }
        storage.addAttribute(.marcdownConcealed, value: true, range: clamped)
        storage.addAttribute(.marcdownConcealedLogical, value: true, range: clamped)
    }

    private func clampedToStorage(_ range: NSRange) -> NSRange {
        let upper = min(range.location + range.length, storage.length)
        let lower = min(range.location, storage.length)
        return NSRange(location: lower, length: max(0, upper - lower))
    }
}
