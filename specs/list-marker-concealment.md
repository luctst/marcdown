# Spec: List Marker Concealment & Continuation

## Objective

Extend Marcdown's existing markdown concealment system to cover plain bullet
(`-`, `*`, `+`) and ordered (`1.`, `2.`, …) list markers. When the user types a
list marker, the raw syntax characters are visually concealed and replaced by a
drawn icon — a filled bullet circle for unordered, the number drawn in accent
colour for ordered — while the characters remain in `NSTextStorage` (preserving
undo / search / copy semantics). Enter and Backspace behaviour match the
established task-list pattern.

**User:** Solo writer in the Marcdown floating panel. No sync or collaboration
surface involved.

**Success:** `- Buy milk` renders as `• Buy milk`; `1. First` renders as
`1. First` (the `1.` drawn in accent colour over concealed source). Enter
continues the list; empty Enter exits. Backspace at end of empty marker is
atomic. Pasted multi-line lists render with markers on every line immediately.

## Tech Stack

- Swift 6 strict concurrency, SPM, TextKit 1 (`NSTextStorage` / `NSLayoutManager`).
- macOS 15+, Xcode 16+.
- No new external dependencies.

## Commands

```bash
# Styling package tests (scanner, continuation)
swift test --package-path Packages/MarcdownStyling

# Core package tests (smoke — should be unaffected)
swift test --package-path Packages/MarcdownCore

# Build sanity
xcodebuild -scheme Marcdown -configuration Debug build
```

## Project Structure

```
Packages/MarcdownStyling/Sources/MarcdownStyling/
  ListLineScanner.swift          ← NEW — pure UTF-16 line scanner
  ListContinuation.swift         ← NEW — Enter / Backspace outcomes
  ConcealmentAttribute.swift     ← ADD .marcdownListMarker key
  MarkdownStyler.swift           ← ADD applyListScannerPass
  StyleWalker.swift              ← REMOVE dimListMarker call for plain list items

Packages/MarcdownEditor/Sources/MarcdownEditor/
  CheckboxIconLayoutManager.swift  ← ADD bullet + number icon drawing
  NoteEditorView.swift             ← INTEGRATE ListContinuation in Enter / BS

Packages/MarcdownStyling/Tests/MarcdownStylingTests/
  ListLineScannerTests.swift     ← NEW
  ListContinuationTests.swift    ← NEW
```

No new SPM packages. No new external dependencies.

## Code Style

Mirror the exact patterns established by `CheckboxLineScanner` /
`TaskListContinuation`:

- Public `enum` with `static func` entry points (no class, no struct state).
- UTF-16 `[UInt16]` array for all scanning (NSRange / NSTextStorage are UTF-16).
- Manual `\n` boundary scanning — never `NSString.paragraphRange(for:)`.
- `Sendable, Equatable` on all public enums.
- AppKit-free in the Styling package (`import Foundation` only).
- Guard-early-return; reject ambiguous shapes as `.none` rather than guessing.

```swift
// Good — mirrors existing pattern
public enum MarcdownListMarkerKind: Sendable, Equatable {
    case bullet                  // -, *, +
    case ordered(number: Int)    // the digit sequence before `.`
}

public enum ListLineShape: Sendable, Equatable {
    case none
    case partial(indentLength: Int, markerLength: Int)
    case complete(indentLength: Int, markerLength: Int, kind: MarcdownListMarkerKind)
}
```

## Testing Strategy

Framework: **Swift Testing** (`@Test`, `@Suite`, `#expect`) — not XCTest.
Location: `Packages/MarcdownStyling/Tests/MarcdownStylingTests/`.
Run: `swift test --package-path Packages/MarcdownStyling`.

### Scanner (`ListLineScannerTests`)

- `.complete(.bullet, …)` for `- text`, `* text`, `+ text`.
- `.complete(.ordered(1), …)` for `1. text`, `10. text`, `99. text`.
- `.partial` for `-`, `- `, `1.`, `1. `, `1` (incomplete).
- `.none` for plain text, `- [ ] task` (checkbox), `1) item` (`)` not in scope), `1.text` (no space).
- Leading whitespace (spaces and tabs) handled correctly; `indentLength` reflects exact UTF-16 count.

### Continuation (`ListContinuationTests`)

- Enter on `- content` → inserts `\n- ` at cursor.
- Enter on `* content` → inserts `\n* ` at cursor (preserves marker char).
- Enter on `1. content` → inserts `\n2. ` at cursor.
- Enter on `9. content` → inserts `\n10. ` at cursor.
- Enter on `- ` (empty body) → strips marker, cursor lands on blank line.
- Enter on `1. ` (empty body) → strips marker.
- Enter with cursor before / inside marker → `.noOp`.
- Backspace at end of empty `- ` → atomic delete of marker + preceding `\n`.
- Backspace at end of empty `1. ` → atomic delete of marker + preceding `\n`.
- Backspace on `- content` → `.standard` (AppKit handles).

### Paste handling

- Pasting `- a\n- b\n- c` styles every line on the first restyle pass — no
  manual trigger, no second keystroke required.
- Pasting `1. a\n2. b\n3. c` styles every numbered line.
- Pasting a mixed buffer (list + plain + checkbox lines) styles each line per
  its own classification; checkbox lines remain owned by `CheckboxLineScanner`.

## Boundaries

**Always do:**
- Run `swift test --package-path Packages/MarcdownStyling` before marking any task done.
- Keep `CheckboxLineScanner` / `TaskListContinuation` untouched — existing checkbox tests must pass.
- Use the scanner pass (not AST) as single source of truth for list marker concealment.
- Skip lines matching `CheckboxLineScanner` from the list scanner pass to avoid double-processing.
- Tab / Shift-Tab on list-item lines fall through to AppKit's default behaviour
  for this slice — nesting is a separate feature.

**Ask first:**
- Tab / Shift-Tab nesting of list items (requires owning the full nesting
  experience: auto-renumber, multi-level, no broken-markdown intermediate
  states). Out of scope for v1; ship as a follow-up when ready to do it right.
- Adding `)` as an ordered list delimiter (`1)` syntax).
- Changing the bullet icon shape or ordered drawing strategy.

**Never do:**
- Use `NSString.paragraphRange(for:)` in continuation / indentation helpers.
- Import AppKit into MarcdownStyling.
- Remove or suppress existing checkbox concealment behaviour.
- Add new SPM dependencies.
- Auto-renumber subsequent items when one is removed or indented.

## Glyph strategy

### Bullet (`- text`, `* text`, `+ text`)

| Char                | Treatment                       | Why                                                |
|---------------------|---------------------------------|----------------------------------------------------|
| `-` / `*` / `+`     | `.marcdownConcealed = true`     | Glyph suppressed by `ConcealmentLayoutDelegate`.   |
| ` ` (space)         | `.foregroundColor = .clear`     | Anchor glyph — layout manager draws `•` in its advance box. |

The 2-char marker range is tagged `.marcdownListMarker = .bullet`. The layout
manager draws a filled `NSBezierPath` circle, 13 px cap, `controlAccentColor`,
centred in the space glyph's advance box. Sizing / anchoring math mirrors
`CheckboxIconLayoutManager.drawIcon`.

### Ordered (`1. text`, `10. text`, …)

| Chars                | Treatment                       | Why                                                |
|----------------------|---------------------------------|----------------------------------------------------|
| digit(s) e.g. `1`    | `.foregroundColor = .clear`     | Anchor glyph(s) for number overlay.                |
| `.`                  | `.marcdownConcealed = true`     | Suppressed.                                        |
| ` ` (space)          | `.marcdownConcealed = true`     | Suppressed.                                        |

The full `N. ` range is tagged `.marcdownListMarker = .ordered(number: N)`.
The layout manager calls `NSString.draw(in:withAttributes:)` with
`[.foregroundColor: controlAccentColor, .font: smallSystemFont(ofSize:)]`,
drawing `"<N>."` over the combined advance of the clear-painted digit glyphs.
No custom path math — the simpler `.draw` primitive handles centring and font
metrics.

## Success Criteria

- [ ] `- text`, `* text`, `+ text` display with bullet `•` icon; raw marker never visible.
- [ ] `1. text`, `10. text` display with drawn number in accent colour; raw digits/period never visible (digits painted `.clear`, period concealed).
- [ ] No flicker or leftover attributes during typing.
- [ ] Enter on non-empty bullet → `\n- ` continuation (preserves the original marker char: `-`/`*`/`+`).
- [ ] Enter on non-empty ordered `N. text` → `\n<N+1>. ` continuation.
- [ ] Enter on empty bullet or ordered item → marker stripped, cursor on blank line.
- [ ] Backspace at end of empty bullet OR ordered item → entire marker removed atomically (including preceding `\n`).
- [ ] Pasting a multi-line list (`- a\n- b\n- c` or `1. a\n2. b\n3. c`) renders every line with its marker immediately, no second keystroke required.
- [ ] Pasted mixed content (list + plain + checkbox lines) styles each line per its own classification.
- [ ] Indented `- text` (already-indented source) still renders with bullet icon.
- [ ] Indented `1. text` (already-indented source) still renders with styled number.
- [ ] Checkbox lines (`- [ ] task`) unchanged — list scanner skips them.
- [ ] Tab / Shift-Tab on list-item lines behave exactly as on plain lines (no nesting in this slice).
- [ ] `swift test --package-path Packages/MarcdownStyling` passes (new + existing tests).
- [ ] `swift test --package-path Packages/MarcdownCore` passes (no regressions).
- [ ] `xcodebuild -scheme Marcdown -configuration Debug build` succeeds.

## Open Questions

None — all assumptions confirmed in chat:

1. Bullet icon: filled circle, 13 px cap. ✓
2. Ordered drawing: `NSString.draw(in:withAttributes:)`, accent colour. ✓
3. Backspace: handles bullet and ordered identically. ✓
4. Tab nesting: **cut from v1.** Ships as a separate feature once we own the
   full nesting experience (auto-renumber, multi-level). Half-nesting would
   corrupt user markdown silently. ✓
5. Paste handling: every list line in a pasted multi-line buffer must style
   on the first pass, no manual trigger. ✓
