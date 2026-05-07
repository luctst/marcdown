# Spec: Markdown Table Styling

> **Note:** Earlier drafts of this spec proposed glyph-level *concealment* of pipes
> and the separator row (the same mechanism used for `**`, `_`, `` ` ``). After
> design and product review (see PR discussion), that approach was rejected because
> (a) concealing pipes destroys cell-boundary perception once the underlying
> monospace alignment is gone, (b) concealing the separator row collapses two
> source lines into nothing while the user is mid-edit, producing cursor-jump
> artifacts, and (c) the always-conceal philosophy from commit `8a8d47f` was
> calibrated for one-or-two-character inline delimiters, not whole structural
> lines. The revised approach below uses **dimming** (foreground color) — strictly
> additive, never destructive.

## Objective

Marcdown currently renders GFM tables as raw text with monospace font, giving every
character — body content, pipes, dashes, alignment colons — equal visual weight.
This spec defines the work to make tables read as quiet structured blocks: the
table's structural syntax (pipes, separator/alignment row) recedes via a dim
foreground color, while cell content keeps the default body color. The table
itself remains fully editable plain markdown; no characters are hidden, no
glyphs are suppressed, and `NSTextStorage` is never mutated structurally.

---

## Tech Stack

| Component | Version |
|---|---|
| macOS deployment target | 15.0+ |
| Xcode | 16.0+ |
| Swift | 6 (strict concurrency, warnings-as-errors) |
| TextKit | 1 (`NSTextView` / `NSTextStorage`) |
| swift-markdown | pinned to `branch: "main"` |
| SPM package | `Packages/MarcdownStyling` |

No new dependencies.

---

## Commands

```bash
# Generate Xcode project
xcodegen generate

# Build
xcodebuild -scheme Marcdown -configuration Debug build

# Run styling tests (the only package touched by this feature)
swift test --package-path Packages/MarcdownStyling
```

---

## Project Structure

### Files changed

| File | Change |
|---|---|
| `Packages/MarcdownStyling/Sources/MarcdownStyling/StyleWalker.swift` | Replace stub `visitTable` (which applies blanket monospace and does not descend) with descending implementation; add `visitTableHead`, `visitTableBody`, `visitTableRow`, `visitTableCell` |

### Files added

| File | Purpose |
|---|---|
| `Packages/MarcdownStyling/Tests/MarcdownStylingTests/TableStylingTests.swift` | New `@Suite("TableStyling")` covering the dim treatment for pipes and separator row |

No other files are touched. `MarkdownStyler`, `LineOffsetIndex`,
`ConcealmentAttribute`, and `ConcealmentLayoutDelegate` (in `MarcdownEditor`)
are unchanged. The conceal pipeline is not used for tables at all.

---

## Code Style

`StyleWalker` is a struct with `mutating` visitor methods. The table
implementation follows the same `addAttributes` + `descendInto` pattern as
`visitBlockQuote` — apply block-level attributes, descend so child visitors
(strong, emphasis, links inside cells, etc.) still run.

### Approach

1. `visitTable` no-ops the prior blanket monospace treatment, then descends.
2. `visitTableBody` detects the **separator row** (the `---`/`:---:` line) and
   applies `theme.dim` foreground color across its full source range. The
   detection check is content-based: every non-whitespace character in the
   row's source is one of `|`, `-`, `:`. This must hold *before* we apply
   color, so we read the substring from `storage.string` for the row's range.
3. `visitTableRow` (for non-separator rows, including the header row) scans
   the row's `NSRange` and applies `theme.dim` to each `|` (U+007C) byte.
4. `visitTableCell` calls `descendInto` so inline markup inside cells continues
   to be styled (bold, italic, links, code).

No `applyConceal` calls. No `.marcdownConcealed` attribute. No bold on
header cells. No `monospacedFont()` on the table block. The dimmed separator
row functions as the visual rule between header and body — its `---`
characters naturally form a quiet horizontal line.

```swift
// Illustrative shape only — implementer should verify swift-markdown
// AST details (especially separator row placement) at implementation time.

mutating func visitTable(_ table: Table) {
    descendInto(table)
}

mutating func visitTableHead(_ head: Table.Head) {
    descendInto(head)
}

mutating func visitTableBody(_ body: Table.Body) {
    if let separator = separatorRow(in: body),
       let range = index.nsRange(separator.range), range.length > 0 {
        addAttributes([.foregroundColor: theme.dim], range: range)
        // Skip descending the separator row — it has no cell content worth
        // styling. Descend into the rest of the body normally.
        for child in body.children where !(child as AnyObject === separator as AnyObject) {
            visit(child)
        }
        return
    }
    descendInto(body)
}

mutating func visitTableRow(_ row: Table.Row) {
    guard let range = index.nsRange(row.range), range.length > 0 else {
        descendInto(row)
        return
    }
    dimPipes(in: range)
    descendInto(row)
}

mutating func visitTableCell(_ cell: Table.Cell) {
    descendInto(cell)
}

/// Identifies the separator row — the `| --- | :---: |` line — by content.
/// Returns the first child of the body whose source range contains only
/// `|`, `-`, `:`, and whitespace.
private func separatorRow(in body: Table.Body) -> Table.Row? {
    let storageString = storage.string as NSString
    for child in body.children {
        guard let row = child as? Table.Row,
              let range = index.nsRange(row.range), range.length > 0,
              range.location + range.length <= storageString.length
        else { continue }
        let substring = storageString.substring(with: range)
        let allSyntax = substring.unicodeScalars.allSatisfy {
            $0 == "|" || $0 == "-" || $0 == ":"
                || $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r"
        }
        if allSyntax { return row }
    }
    return nil
}

/// Applies `theme.dim` foreground to every `|` (U+007C) within `range`.
private func dimPipes(in range: NSRange) {
    let s = storage.string as NSString
    let upper = range.location + range.length
    var i = range.location
    while i < upper {
        if s.character(at: i) == 0x7C {
            addAttributes([.foregroundColor: theme.dim],
                          range: NSRange(location: i, length: 1))
        }
        i += 1
    }
}
```

> **AST verification notes for the implementer.** swift-markdown's exact
> placement of the separator row (child of `Table.Head` vs. first child of
> `Table.Body`) and whether `index.nsRange(row.range)` includes the trailing
> `\n` are open questions. The detection helper above sweeps `body.children`
> rather than indexing position-1, which keeps it robust to either layout.
> If the separator turns out to live under `Table.Head`, move the
> `separatorRow(in:)` call into `visitTableHead`.

---

## Testing Strategy

All tests live in
`Packages/MarcdownStyling/Tests/MarcdownStylingTests/TableStylingTests.swift`,
following the same helpers as `ConcealmentTests.swift` and
`MarkdownStylerTests.swift`:

- `styledStorage(_:) -> NSTextStorage` — creates `NSTextStorage`, runs
  `MarkdownStyler().restyle`, returns the storage.
- Read attributes via `storage.attribute(.foregroundColor, at:effectiveRange:)`.

```swift
import AppKit
import Testing
@testable import MarcdownStyling

@MainActor
@Suite("TableStyling")
struct TableStylingTests {

    private func styledStorage(_ source: String) -> NSTextStorage {
        let storage = NSTextStorage(string: source)
        MarkdownStyler().restyle(storage: storage, source: source)
        return storage
    }

    private func color(at index: Int, in storage: NSTextStorage) -> NSColor? {
        guard index < storage.length else { return nil }
        return storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
    }

    // 1. Every pipe in a header row is dim.
    @Test func headerPipesAreDim() {
        let source = "| A | B |\n| --- | --- |\n| 1 | 2 |\n"
        let storage = styledStorage(source)
        let dim = StylingTheme.system.dim
        let pipePositions = source.utf16.enumerated()
            .filter { $0.element == 0x7C }
            .map { $0.offset }
        for pos in pipePositions {
            #expect(color(at: pos, in: storage) == dim)
        }
    }

    // 2. Every non-syntax character in the separator row is dim.
    @Test func separatorRowIsDim() {
        let source = "| A | B |\n| --- | :---: |\n| 1 | 2 |\n"
        let storage = styledStorage(source)
        let dim = StylingTheme.system.dim
        // Separator line spans positions 9..<26 (exclusive of trailing \n).
        let separatorStart = (source as NSString).range(of: "| --- | :---: |").location
        let separatorLen = ("| --- | :---: |" as NSString).length
        for pos in separatorStart..<(separatorStart + separatorLen) {
            #expect(color(at: pos, in: storage) == dim)
        }
    }

    // 3. Cell content is NOT dim — it stays at body color.
    @Test func cellContentIsNotDim() {
        let source = "| Hello | World |\n| --- | --- |\n| Foo | Bar |\n"
        let storage = styledStorage(source)
        let dim = StylingTheme.system.dim
        let body = StylingTheme.system.body
        for word in ["Hello", "World", "Foo", "Bar"] {
            let r = (source as NSString).range(of: word)
            for i in r.location..<(r.location + r.length) {
                #expect(color(at: i, in: storage) != dim)
                #expect(color(at: i, in: storage) == body)
            }
        }
    }

    // 4. No conceal flag is applied to any table position.
    @Test func tablesUseNoConceal() {
        let source = "| A | B |\n| --- | --- |\n| 1 | 2 |\n"
        let storage = styledStorage(source)
        for i in 0..<storage.length {
            let flag = storage.attribute(.marcdownConcealed, at: i, effectiveRange: nil) as? Bool
            #expect(flag != true)
        }
    }

    // 5. The table block does NOT receive blanket monospace.
    @Test func tableIsNotForcedMonospace() {
        let source = "| Hello | World |\n| --- | --- |\n| Foo | Bar |\n"
        let storage = styledStorage(source)
        let r = (source as NSString).range(of: "Hello")
        let font = storage.attribute(.font, at: r.location, effectiveRange: nil) as? NSFont
        // The default base font is the system font, not monospaced.
        #expect(font?.isFixedPitch == false)
    }

    // 6. Storage string is preserved across restyle.
    @Test func tableRestylePreservesCharacters() {
        let source = "| A | B |\n| --- | --- |\n| 1 | 2 |\n"
        let storage = NSTextStorage(string: source)
        MarkdownStyler().restyle(storage: storage, source: source)
        #expect(storage.string == source)
    }

    // 7. Restyle is idempotent.
    @Test func tableRestyleIsIdempotent() {
        let source = "| A | B |\n| --- | --- |\n| 1 | 2 |\n"
        let storage = NSTextStorage(string: source)
        MarkdownStyler().restyle(storage: storage, source: source)
        let firstSnapshot = (0..<storage.length).map {
            (storage.attribute(.foregroundColor, at: $0, effectiveRange: nil) as? NSColor)?.description
        }
        MarkdownStyler().restyle(storage: storage, source: source)
        let secondSnapshot = (0..<storage.length).map {
            (storage.attribute(.foregroundColor, at: $0, effectiveRange: nil) as? NSColor)?.description
        }
        #expect(firstSnapshot == secondSnapshot)
    }

    // 8. Malformed table (no separator row) does not crash; not parsed as Table.
    @Test func malformedTableDoesNotCrash() {
        let source = "| A | B |"
        let storage = NSTextStorage(string: source)
        MarkdownStyler().restyle(storage: storage, source: source)
        #expect(storage.string == source)
    }

    // 9. Adjacent blocks are not contaminated by table styling.
    @Test func adjacentBlocksAreNotContaminated() {
        let source = "# Heading\n\n| A |\n| --- |\n| B |\n\nA paragraph.\n"
        let storage = styledStorage(source)
        let body = StylingTheme.system.body
        let pr = (source as NSString).range(of: "A paragraph.")
        for i in pr.location..<(pr.location + pr.length) {
            #expect(color(at: i, in: storage) == body)
        }
    }

    // 10. Inline markup inside cells still styles (descendInto works).
    @Test func boldInsideCellIsStillBold() {
        let source = "| **bold** | plain |\n| --- | --- |\n| 1 | 2 |\n"
        let storage = styledStorage(source)
        let r = (source as NSString).range(of: "bold")
        let font = storage.attribute(.font, at: r.location, effectiveRange: nil) as? NSFont
        let isBold = font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
        #expect(isBold)
    }
}
```

---

## Boundaries

### Always

- Use `addAttributes([.foregroundColor: theme.dim], range:)` — never replace,
  hide, or delete characters.
- Apply `theme.dim` to each `|` and to the entire separator row source range.
- Detect the separator row by content (`|`, `-`, `:`, whitespace only) and
  by sweeping `Table.Body.children`, not by position index.
- Call `descendInto(...)` on `Table`, `Table.Head`, `Table.Row`, and
  `Table.Cell` so inline markup inside cells (bold, links, etc.) still styles.
- Return early when `index.nsRange` returns `nil` for a node — never force-unwrap.
- Maintain Swift 6 strict concurrency: all storage mutations on `@MainActor`,
  `StyleWalker` remains a struct.

### Ask first

- Adding any glyph-suppression (`.marcdownConcealed`) to table content — this
  was rejected and reintroducing it requires a new product call.
- Bolding header cells — design rejected this; revisit only if user feedback
  shows the dimmed-separator-row treatment is insufficient as a header signal.
- Drawing a horizontal-rule (via `.underlineStyle`, attachment, or layout
  delegate) under the header row — explicitly cut from this slice.
- Per-cell paragraph styles for column alignment (tab stops, etc.) — deferred;
  the math is intractable with proportional fonts.

### Never

- Modify `storage.string` (insert, delete, or replace characters).
- Apply `applyConceal` / `.marcdownConcealed` anywhere inside table styling.
- Apply `monospacedFont()` to the table block.
- Apply `.boldFontMask` to header cells.
- Introduce new SPM dependencies.
- Use `NSTextAttachment`, custom `NSCell`, or any TextKit 2 API.
- Reintroduce the cursor-aware reveal mode removed in `8a8d47f`.

---

## Success Criteria

All criteria are verifiable by running
`swift test --package-path Packages/MarcdownStyling`.

1. **Pipes are dim.** Every `|` (U+007C) inside a parsed `Table` carries
   `.foregroundColor == theme.dim`.
2. **Separator row is dim.** Every character in the separator row's source
   range carries `.foregroundColor == theme.dim`.
3. **Cell content keeps body color.** Characters of cell content (header and
   data alike) carry `.foregroundColor == theme.body`, not `theme.dim`.
4. **No conceal flag.** No position inside a table carries
   `.marcdownConcealed == true`.
5. **No blanket monospace.** Cell content's font is not fixed-pitch (unless
   the user explicitly used inline code inside a cell, which is a separate
   visitor's concern).
6. **Storage invariant.** `storage.string` equals the source after any
   number of `restyle` calls.
7. **Idempotency.** Two consecutive `restyle` calls produce identical
   `.foregroundColor` runs.
8. **No crash on malformed input.** Input lacking a separator row (not parsed
   as a `Table`) produces no crash; storage string is preserved.
9. **No contamination.** A document with a heading before and a paragraph
   after the table has its heading and paragraph styling unaffected.
10. **Inline markup inside cells styles.** `**bold**` inside a cell renders
    bold (i.e. cell-level `descendInto` is wired up).

---

## Non-Goals

The following are explicitly out of scope for this slice. Each was discussed
during product/design review and intentionally deferred:

- **Column-aligned cells.** Real column alignment requires either a custom
  layout manager or per-paragraph tab stops calculated from cell content widths
  — neither is tractable with proportional fonts and the floating-panel layout.
- **Header bold or any header-specific styling.** The dimmed separator row
  serves as the visual delineator. Adding a second signal duplicates effort.
- **Horizontal rule under the header row.** Same rationale.
- **Cursor-aware reveal of dim styling.** Tables are not concealed — they're
  dimmed. The user can still see the syntax; reveal-on-cursor would only add
  flicker.
- **Tables inside blockquotes.** Blockquote indentation paragraph styles will
  apply on top of the table dimming. The combined visual is acceptable; no
  special handling.
- **Wide-table overflow.** The floating panel max-width is 720pt. A table
  wider than that will wrap mid-cell. Behavior matches existing long-paragraph
  wrapping; no special handling.
- **Copy/paste behavior.** Storage characters are unchanged, so the user's
  pasteboard receives raw markdown — which is the desired behavior. No code
  needed.

---

## Resolved Questions

Both questions raised during spec drafting have been resolved during
implementation:

1. **Separator row placement in the AST.** *Resolved: swift-markdown does
   not surface the separator row as a node at all.* The parser consumes
   `| --- | :---: |` and stores its information as `Table.columnAlignments`;
   `Table.Head` covers only the header line, `Table.Body` starts at the first
   data row. The implementation therefore detects separator rows by scanning
   the table's source range line-by-line in `visitTable`, applying `theme.dim`
   to any line whose non-whitespace content is exactly `|`, `-`, `:`,
   space, or tab and that contains at least one `|` and one `-`.
2. **Trailing newline.** *Resolved: irrelevant.* Because the line scan
   computes ranges directly from `storage.string`, the trailing `\n` is
   naturally excluded — dim color ends at the last `|` of the separator row,
   and the newline character has no glyph anyway.
