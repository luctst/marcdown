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
    }

    // MARK: - Blocks

    mutating func visitHeading(_ heading: Heading) {
        guard let range = index.nsRange(heading.range), range.length > 0 else {
            descendInto(heading)
            return
        }
        let size = headingSize(for: heading.level)
        let font = NSFontManager.shared
            .convert(.systemFont(ofSize: size, weight: .bold), toHaveTrait: .boldFontMask)
        addAttributes([.font: font], range: range)

        // ATX heading marker concealment — only for ATX (`# `, `## ` …).
        // Setext headings (`====` / `----` underlines) report a multi-line
        // range whose first character is not `#`; the prefix scan below will
        // simply find no `#` and skip.
        if let markerRange = atxHeadingMarkerRange(in: range) {
            if markerRange.length < range.length {
                // Non-empty heading: body text follows the marker, the line has
                // a visible width so concealment is safe.
                applyConceal(to: markerRange)
            } else {
                // Empty heading (`#` / `# ` with no body). Concealment via .null
                // glyphs would collapse the line to zero width — the visible cursor
                // would snap up to the previous line while the user is typing the
                // marker. Clear-paint + monospaced keeps the marker invisible but
                // gives the line a real advance so the cursor stays put. Same
                // treatment as the bullet / ordered complete markers in
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

    /// Scans the leading characters of a heading's storage range for an ATX
    /// marker: 1-6 `#` characters optionally followed by one space/tab (or
    /// end-of-line/end-of-storage for an empty heading like `#\n`).
    ///
    /// Returns `nil` if no valid ATX marker is present (e.g. setext heading
    /// or somehow malformed input).
    private func atxHeadingMarkerRange(in headingRange: NSRange) -> NSRange? {
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
        // of line — otherwise it's not a heading marker. swift-markdown's
        // parser already enforced "this is a heading", so end-of-storage and
        // newline are valid terminators here too.
        var markerLength = hashCount
        if probe < upper {
            let trailing = storageString.character(at: probe)
            // 0x20 space, 0x09 tab, 0x0A newline, 0x0D CR
            if trailing == 0x20 || trailing == 0x09 {
                markerLength += 1
            } else if trailing == 0x0A || trailing == 0x0D {
                // Empty heading: marker is just the hashes.
            } else {
                // Not a valid ATX marker — bail. Shouldn't happen given the
                // parser said "heading", but be defensive.
                return nil
            }
        }

        return NSRange(location: headingRange.location, length: markerLength)
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        guard let range = index.nsRange(blockQuote.range), range.length > 0 else {
            descendInto(blockQuote)
            return
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.firstLineHeadIndent = 12
        paragraph.headIndent = 12
        addAttributes(
            [
                .foregroundColor: theme.dim,
                .paragraphStyle: paragraph,
            ],
            range: range
        )
        descendInto(blockQuote)
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        guard let range = index.nsRange(codeBlock.range), range.length > 0 else { return }
        let clampedFull = clampedToStorage(range)
        guard clampedFull.length > 0 else { return }

        // a/b. Monospaced font + tag whole block as a code block. The custom
        // background painter in `FocusOnAttachTextView.drawBackground(in:)`
        // reads `.marcdownCodeBlock` to draw a full-width rounded container
        // wrapping the entire block (fences are zero-width via
        // `.marcdownConcealed`, so they collapse and provide natural top /
        // bottom padding inside the box).
        addAttributes(
            [
                .font: monospacedFont(),
            ],
            range: clampedFull
        )
        storage.addAttribute(.marcdownCodeBlock, value: true, range: clampedFull)

        // c/d. Compute the opening and closing fence line ranges by scanning
        // the raw storage string. `swift-markdown` reports the block range
        // including the fence lines themselves; the body sits between the
        // first and last `\n` inside that range.
        let storageString = storage.string as NSString
        let blockStart = clampedFull.location
        let blockEnd = clampedFull.location + clampedFull.length

        // Opening fence: from blockStart to (and including) the first `\n`.
        var openingEnd = blockStart
        while openingEnd < blockEnd,
            storageString.character(at: openingEnd) != 0x0A
        {
            openingEnd += 1
        }
        // NOTE: Do NOT include the trailing `\n` in the opening fence range.
        // If it's concealed, AppKit's `typingAttributes` at the start of the
        // body line (cursor-1 = this `\n`) inherit `.marcdownConcealed`, and
        // every char the user types is invisible until the cursor moves past
        // a non-concealed neighbor. The `\n` still functions as the line
        // terminator regardless of glyph concealment — line layout is driven
        // by the character, not the glyph property.
        let openingFenceRange = NSRange(
            location: blockStart,
            length: openingEnd - blockStart
        )

        // Closing fence: walk backwards from blockEnd, skipping any trailing
        // `\n` (cmark may or may not include a final newline depending on the
        // input), then back to the start of that final line.
        var closingScan = blockEnd
        // Skip trailing newline(s) — there's typically one at most.
        while closingScan > blockStart,
            storageString.character(at: closingScan - 1) == 0x0A
        {
            closingScan -= 1
        }
        // Walk to the start of the line containing closingScan - 1.
        var closingStart = closingScan
        while closingStart > blockStart,
            storageString.character(at: closingStart - 1) != 0x0A
        {
            closingStart -= 1
        }
        let closingFenceRange = NSRange(
            location: closingStart,
            length: blockEnd - closingStart
        )

        // e/f. Apply fence treatment. For malformed / single-line blocks the
        // closing range may overlap the opening range — in that case skip the
        // closing pass to avoid double work. Also guard against unclosed fenced
        // blocks: if the "closing" line is not actually a fence marker (3
        // backticks or tildes), it's user content and must not be concealed.
        if isFenceMarkerLine(at: openingFenceRange.location, storageString: storageString, blockEnd: blockEnd) {
            applyFenceTreatment(to: openingFenceRange)
        }
        if closingFenceRange.location > openingFenceRange.location,
           closingFenceRange.length > 0,
           isFenceMarkerLine(at: closingFenceRange.location, storageString: storageString, blockEnd: blockEnd) {
            applyFenceTreatment(to: closingFenceRange)
        }
    }

    /// Returns true if the line starting at `loc` begins with three consecutive
    /// backticks (0x60) or three consecutive tildes (0x7E) — the only valid
    /// CommonMark fence openers/closers.
    private func isFenceMarkerLine(at loc: Int, storageString: NSString, blockEnd: Int) -> Bool {
        guard loc + 2 < blockEnd else { return false }
        let first = storageString.character(at: loc)
        guard first == 0x60 || first == 0x7E else { return false }
        return storageString.character(at: loc + 1) == first
            && storageString.character(at: loc + 2) == first
    }

    /// Marks `range` as a fence marker line: tags both `.marcdownCodeFence`
    /// and `.marcdownConcealed` so the concealment layout delegate suppresses
    /// the fence glyphs entirely (zero-width via `.null` glyph properties).
    /// The collapsed line heights serve as natural top/bottom padding inside
    /// the surrounding rounded container.
    private func applyFenceTreatment(to range: NSRange) {
        let clamped = clampedToStorage(range)
        guard clamped.length > 0 else { return }
        storage.addAttribute(.marcdownCodeFence, value: true, range: clamped)
        storage.addAttribute(.marcdownConcealed, value: true, range: clamped)
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        guard let range = index.nsRange(thematicBreak.range), range.length > 0 else { return }
        addAttributes([.foregroundColor: theme.dim], range: range)
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
        guard let range = index.nsRange(link.range), range.length > 0 else {
            descendInto(link)
            return
        }
        addAttributes(
            [
                .foregroundColor: theme.accent,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ],
            range: range
        )
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
    /// layout delegate will suppress the corresponding glyphs.
    private func applyConceal(to subrange: NSRange) {
        let clamped = clampedToStorage(subrange)
        guard clamped.length > 0 else { return }
        storage.addAttribute(.marcdownConcealed, value: true, range: clamped)
    }

    private func clampedToStorage(_ range: NSRange) -> NSRange {
        let upper = min(range.location + range.length, storage.length)
        let lower = min(range.location, storage.length)
        return NSRange(location: lower, length: max(0, upper - lower))
    }
}
