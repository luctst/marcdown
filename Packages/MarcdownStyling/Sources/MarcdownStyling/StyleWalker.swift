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
            applyConceal(to: markerRange)
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
        addAttributes(
            [
                .font: monospacedFont(),
                .backgroundColor: theme.codeBackground,
            ],
            range: range
        )
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
        dimListMarker(for: listItem)

        if let checkbox = listItem.checkbox {
            styleCheckbox(for: listItem, checkbox: checkbox)
        }
        descendInto(listItem)
    }

    mutating func visitTable(_ table: Table) {
        // Dim the separator/alignment row (the `| --- | :---: |` line). It is
        // not represented as a node in swift-markdown's AST — the parser
        // consumes it and stores its information as `Table.columnAlignments`.
        // We therefore detect it in the source: any line that lies inside the
        // table's range and whose non-whitespace characters are all `|`, `-`,
        // or `:` is a separator row.
        if let tableRange = index.nsRange(table.range), tableRange.length > 0 {
            dimSeparatorRows(in: tableRange)
        }
        descendInto(table)
    }

    mutating func visitTableHead(_ head: Table.Head) {
        if let range = index.nsRange(head.range), range.length > 0 {
            dimPipes(in: range)
        }
        descendInto(head)
    }

    mutating func visitTableBody(_ body: Table.Body) {
        descendInto(body)
    }

    mutating func visitTableRow(_ row: Table.Row) {
        if let range = index.nsRange(row.range), range.length > 0 {
            dimPipes(in: range)
        }
        descendInto(row)
    }

    mutating func visitTableCell(_ cell: Table.Cell) {
        descendInto(cell)
    }

    /// Applies `theme.dim` to every `|` (U+007C) inside `range`.
    private func dimPipes(in range: NSRange) {
        let storageString = storage.string as NSString
        let upper = min(range.location + range.length, storageString.length)
        var i = max(0, range.location)
        while i < upper {
            if storageString.character(at: i) == 0x7C {
                addAttributes(
                    [.foregroundColor: theme.dim],
                    range: NSRange(location: i, length: 1)
                )
            }
            i += 1
        }
    }

    /// Scans every line that lies inside `tableRange` and applies `theme.dim`
    /// to lines whose non-whitespace content is composed only of `|`, `-`, or
    /// `:`. This is how we dim GFM separator/alignment rows, which are not
    /// surfaced as AST nodes by swift-markdown.
    private func dimSeparatorRows(in tableRange: NSRange) {
        let storageString = storage.string as NSString
        let upper = min(tableRange.location + tableRange.length, storageString.length)
        var lineStart = max(0, tableRange.location)
        while lineStart < upper {
            // Find end of this line (exclusive of newline).
            var lineEnd = lineStart
            while lineEnd < upper {
                let ch = storageString.character(at: lineEnd)
                if ch == 0x0A || ch == 0x0D { break }
                lineEnd += 1
            }
            if lineEnd > lineStart, isSeparatorLine(start: lineStart, end: lineEnd, in: storageString) {
                let range = NSRange(location: lineStart, length: lineEnd - lineStart)
                addAttributes([.foregroundColor: theme.dim], range: range)
            }
            // Advance past newline (handle CRLF).
            if lineEnd < upper, storageString.character(at: lineEnd) == 0x0D {
                lineEnd += 1
            }
            if lineEnd < upper, storageString.character(at: lineEnd) == 0x0A {
                lineEnd += 1
            }
            if lineEnd == lineStart { break }
            lineStart = lineEnd
        }
    }

    /// True if every character in `[start, end)` is one of `|`, `-`, `:`,
    /// space, or tab, AND the line contains at least one `|` and one `-` —
    /// that's the GFM separator-row signature. Plain dashes alone (a thematic
    /// break) shouldn't reach this code path because they live outside any
    /// table, but the `|` check makes the predicate robust regardless.
    private func isSeparatorLine(start: Int, end: Int, in storageString: NSString) -> Bool {
        var sawPipe = false
        var sawDash = false
        for i in start..<end {
            switch storageString.character(at: i) {
            case 0x7C: sawPipe = true               // |
            case 0x2D: sawDash = true               // -
            case 0x3A: break                         // :
            case 0x20, 0x09: break                   // space, tab
            default: return false
            }
        }
        return sawPipe && sawDash
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

    private func dimListMarker(for listItem: ListItem) {
        guard let itemRange = index.nsRange(listItem.range), itemRange.length > 0 else { return }
        let substring = (storage.string as NSString).substring(with: itemRange)
        guard let markerLength = markerLength(in: substring) else { return }
        let markerRange = NSRange(location: itemRange.location, length: markerLength)
        addAttributes([.foregroundColor: theme.dim], range: markerRange)
    }

    /// Returns the length (in UTF-16 units) of the leading list marker —
    /// including any indentation and the space after the marker. Returns `nil`
    /// if a marker can't be found (the item is empty or malformed).
    private func markerLength(in line: String) -> Int? {
        var cursor = line.startIndex
        // Skip leading indentation.
        while cursor < line.endIndex, line[cursor] == " " || line[cursor] == "\t" {
            cursor = line.index(after: cursor)
        }
        guard cursor < line.endIndex else { return nil }
        let first = line[cursor]

        if first == "-" || first == "*" || first == "+" {
            cursor = line.index(after: cursor)
        } else if first.isNumber {
            while cursor < line.endIndex, line[cursor].isNumber {
                cursor = line.index(after: cursor)
            }
            guard cursor < line.endIndex, line[cursor] == "." || line[cursor] == ")" else {
                return nil
            }
            cursor = line.index(after: cursor)
        } else {
            return nil
        }

        // Require (and include) at least one whitespace separator.
        guard cursor < line.endIndex, line[cursor] == " " || line[cursor] == "\t" else {
            return nil
        }
        cursor = line.index(after: cursor)

        return line.utf16.distance(
            from: line.utf16.startIndex, to: cursor.samePosition(in: line.utf16) ?? line.utf16.endIndex)
    }

    private func styleCheckbox(for listItem: ListItem, checkbox: Checkbox) {
        guard let itemRange = index.nsRange(listItem.range), itemRange.length > 0 else { return }
        let storageString = storage.string as NSString
        let substring = storageString.substring(with: itemRange)

        // Find the `[` after the list marker.
        guard let openBracket = substring.firstIndex(of: "[") else { return }
        let offsetToOpen = substring.utf16.distance(
            from: substring.utf16.startIndex,
            to: openBracket.samePosition(in: substring.utf16) ?? substring.utf16.endIndex
        )
        // `[x]` or `[ ]` — three UTF-16 units.
        let checkboxLocation = itemRange.location + offsetToOpen
        let checkboxLength = 3
        guard checkboxLocation + checkboxLength <= storage.length else { return }
        let checkboxRange = NSRange(location: checkboxLocation, length: checkboxLength)
        let color: NSColor = checkbox == .checked ? theme.accent : theme.dim
        addAttributes([.foregroundColor: color], range: checkboxRange)
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
