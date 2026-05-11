# Tasks: List Marker Concealment & Continuation

Companion to [`list-marker-concealment.md`](./list-marker-concealment.md). Every
task lists its acceptance, verification, dependencies, and the files it touches.

## Overview

Seven tasks across three phases. Horizontal slicing (scanner → helpers →
styling → drawing → wiring → paste verify) matches the existing checkbox
implementation; a vertical slice would force writing the scanner / styler /
drawing twice (once per marker kind) for no design benefit.

## Architecture decisions

- **Mirror the checkbox pipeline exactly.** Scanner pass owns concealment; AST
  walk no longer dims list markers.
- **Two marker kinds in one scanner.** `ListLineScanner.scan(line:)` returns
  `.bullet` or `.ordered(number:)` — both are handled in a single classification
  pass.
- **Layout drawing extends `CheckboxIconLayoutManager`** rather than a new
  manager subclass — keeps the TextKit 1 stack at one custom layout manager
  and one delegate.
- **Checkbox precedence.** Any line that classifies as a checkbox (partial or
  complete) under `CheckboxLineScanner` is skipped by the list pass.

---

## Phase 1 — Foundation

### Task 1: Add `.marcdownListMarker` attribute key + `MarcdownListMarkerKind`

**Description:** Introduce the public attribute key the styler will write and
the layout manager will read. Pure type-level addition, no logic.

**Acceptance criteria:**
- [ ] `MarcdownListMarkerKind: Sendable, Equatable` enum exists with cases
      `.bullet` and `.ordered(number: Int)`.
- [ ] `NSAttributedString.Key.marcdownListMarker` exists alongside
      `.marcdownConcealed` and `.marcdownCheckbox`.
- [ ] Doc comment explains: written exclusively by the list-scanner pass; read
      by the layout manager for icon drawing.

**Verification:**
- [ ] `swift build --package-path Packages/MarcdownStyling` succeeds.

**Dependencies:** None.

**Files likely touched:**
- `Packages/MarcdownStyling/Sources/MarcdownStyling/ConcealmentAttribute.swift`

**Estimated scope:** XS (1 file).

---

### Task 2: Implement `ListLineScanner` + tests

**Description:** Pure UTF-16 line classifier. Mirrors `CheckboxLineScanner`
public shape — `.none` / `.partial` / `.complete` — and returns the marker
kind on complete. Returns `.none` for any line that would match the checkbox
scanner.

**Acceptance criteria:**
- [ ] `ListLineShape` enum with `.none`, `.partial(indentLength, markerLength)`,
      `.complete(indentLength, markerLength, kind)`.
- [ ] `.complete(.bullet, …)` for `- text`, `* text`, `+ text`.
- [ ] `.complete(.ordered(N), …)` for `N. text` where N is any positive integer.
- [ ] `.partial` for `-`, `- `, `*`, `1`, `1.`, `1. ` (incomplete bodies).
- [ ] `.none` for plain text, `- [ ] task`, `1) item`, `1.text`.
- [ ] All test cases from spec's Scanner section pass.

**Verification:**
- [ ] `swift test --package-path Packages/MarcdownStyling --filter ListLineScannerTests` passes.

**Dependencies:** None.

**Files likely touched:**
- `Packages/MarcdownStyling/Sources/MarcdownStyling/ListLineScanner.swift` (new)
- `Packages/MarcdownStyling/Tests/MarcdownStylingTests/ListLineScannerTests.swift` (new)

**Estimated scope:** S (2 files).

---

### Task 3: Implement `ListContinuation` (Enter + Backspace) + tests

**Description:** Pure helper that decides Enter and Backspace outcomes on
list-item lines. Mirrors `TaskListContinuation` shape: returns `.noOp`,
`.replace(range, replacement, cursorOffsetInBuffer)`, or `.standard` (BS only).

**Acceptance criteria:**
- [ ] Enter on non-empty bullet `- foo` inserts `\n- ` at cursor (preserves the
      original marker char for `*` and `+`).
- [ ] Enter on non-empty ordered `N. foo` inserts `\n<N+1>. ` at cursor.
- [ ] Enter on empty bullet or ordered body strips the marker, cursor on blank.
- [ ] Enter with cursor before/inside the marker → `.noOp`.
- [ ] Backspace at end of empty bullet or ordered marker atomically deletes
      marker + preceding `\n`.
- [ ] Backspace on `- content` → `.standard`.
- [ ] All test cases from spec's Continuation section pass.

**Verification:**
- [ ] `swift test --package-path Packages/MarcdownStyling --filter ListContinuationTests` passes.

**Dependencies:** Task 2.

**Files likely touched:**
- `Packages/MarcdownStyling/Sources/MarcdownStyling/ListContinuation.swift` (new)
- `Packages/MarcdownStyling/Tests/MarcdownStylingTests/ListContinuationTests.swift` (new)

**Estimated scope:** S (2 files).

---

### Checkpoint: Foundation complete

- [ ] `swift test --package-path Packages/MarcdownStyling` passes (new + existing).
- [ ] No AppKit imports in any new file under MarcdownStyling.
- [ ] No usage of `NSString.paragraphRange(for:)` in new code.

---

## Phase 2 — Rendering

### Task 4: Add `applyListScannerPass` to `MarkdownStyler` + retire `dimListMarker`

**Description:** Run a list-scanner pass after the existing checkbox-scanner
pass. For each line: if `CheckboxLineScanner.scan` is non-`.none`, skip;
else classify with `ListLineScanner` and apply the glyph-strategy attributes
(conceal markers, paint anchor glyphs `.clear`, tag with `.marcdownListMarker`).
Remove the `dimListMarker` call from `StyleWalker.visitListItem` for the
non-checkbox branch.

**Acceptance criteria:**
- [ ] `applyListScannerPass(storage:source:)` runs after `applyCheckboxScannerPass`.
- [ ] Lines matching `CheckboxLineScanner` are not touched by the list pass.
- [ ] Bullet lines: marker char concealed, trailing space painted `.clear`,
      range tagged `.marcdownListMarker = .bullet`.
- [ ] Ordered lines: digits painted `.clear` and monospaced, `.` + space
      concealed, full range tagged `.marcdownListMarker = .ordered(number:)`.
- [ ] `StyleWalker.visitListItem` no longer calls `dimListMarker` for plain
      list items (function body and helper may stay or be deleted — both
      acceptable).
- [ ] All existing `CheckboxLineScanner` / checkbox styling tests still pass.

**Verification:**
- [ ] `swift test --package-path Packages/MarcdownStyling` passes (full suite).
- [ ] `xcodebuild -scheme Marcdown -configuration Debug build` succeeds.

**Dependencies:** Task 1, Task 2.

**Files likely touched:**
- `Packages/MarcdownStyling/Sources/MarcdownStyling/MarkdownStyler.swift`
- `Packages/MarcdownStyling/Sources/MarcdownStyling/StyleWalker.swift`

**Estimated scope:** M (2 files, moderate logic).

---

### Task 5: Extend `CheckboxIconLayoutManager` to draw bullet circle and ordered number

**Description:** Walk `.marcdownListMarker` runs in the visible glyph range
(alongside the existing `.marcdownCheckbox` walk). Draw a filled
`NSBezierPath` circle for `.bullet` and `NSString.draw(in:withAttributes:)`
for `.ordered`. Anchor to glyph advance boxes — no `boundingRect(forGlyphRange:)`.

**Acceptance criteria:**
- [ ] Filled 13 px-cap circle drawn in the space glyph's advance box for
      every `.bullet`-tagged range, `controlAccentColor`.
- [ ] Number string `"<N>."` drawn over the digit glyphs' combined advance for
      every `.ordered(number: N)`-tagged range, `controlAccentColor`,
      system font sized to fit the line height.
- [ ] No double-drawing when a marker straddles two dirty rects (extend the
      existing `drawnRanges` dedupe set or add a sibling).
- [ ] Checkbox icon drawing unchanged.

**Verification:**
- [ ] `xcodebuild -scheme Marcdown -configuration Debug build` succeeds.
- [ ] Manual: open the app, type `- foo` → bullet circle visible, `-` not.
- [ ] Manual: type `1. bar` → accent-coloured `1.` visible, no raw period.
- [ ] Manual: scroll a long buffer with many list items — no flicker, no
      double-draws at the seam between visible / off-screen ranges.

**Dependencies:** Task 1.

**Files likely touched:**
- `Packages/MarcdownEditor/Sources/MarcdownEditor/CheckboxIconLayoutManager.swift`

**Estimated scope:** M (1 file, drawing math).

---

### Checkpoint: Rendering complete

- [ ] `- foo` and `1. bar` render correctly when typed character-by-character.
- [ ] Checkbox rendering still works.
- [ ] No visual regressions in plain text, headings, bold, italic.
- [ ] Build clean, tests green.

---

## Phase 3 — Interaction & paste

### Task 6: Wire `ListContinuation` into `NoteEditorView` (Enter + Backspace)

**Description:** In the coordinator's existing Enter and Backspace handlers,
fall through to `ListContinuation` when the task-list helpers return `.noOp` /
`.standard`. Mirror the existing replace pattern: `shouldChangeText` →
`replaceCharacters` → `didChangeText` → `setSelectedRange`. Undo action names:
`"New List Item"` / `"Remove List Item"`.

**Acceptance criteria:**
- [ ] Enter on non-empty `- foo` inserts `\n- ` and positions cursor at the
      new line's end.
- [ ] Enter on `1. foo` inserts `\n2. `; on `9. foo` inserts `\n10. `.
- [ ] Enter on empty `- ` strips marker, cursor lands on blank line.
- [ ] Backspace at end of empty `- ` or `1. ` atomically removes marker + `\n`.
- [ ] Existing checkbox Enter / Backspace flows unchanged.
- [ ] Undo (Cmd-Z) reverses each list edit as a single step.

**Verification:**
- [ ] `xcodebuild -scheme Marcdown -configuration Debug build` succeeds.
- [ ] Manual flow: type list, continue with Enter, exit with empty Enter,
      atomic-delete with Backspace. Repeat for ordered.
- [ ] Manual: confirm checkbox Enter / Backspace still atomic.

**Dependencies:** Task 3, Task 4, Task 5.

**Files likely touched:**
- `Packages/MarcdownEditor/Sources/MarcdownEditor/NoteEditorView.swift`

**Estimated scope:** S (1 file, two handlers extended).

---

### Task 7: Paste verification

**Description:** Confirm that pasting multi-line list content styles every
line on the first restyle pass. The styler already runs on every text change
(`textDidChange`), so the expectation is that no additional code is needed —
this task is verify-only, with a regression test added to lock the behaviour.

**Acceptance criteria:**
- [ ] Pasting `- a\n- b\n- c` into the editor renders all three lines with
      bullet icons immediately (no second keystroke).
- [ ] Pasting `1. a\n2. b\n3. c` renders all three numbered markers.
- [ ] Pasting a mixed buffer (`- bullet\nplain text\n- [ ] task\n1. ordered`)
      classifies each line per its own kind; checkbox lines remain owned by
      `CheckboxLineScanner`.
- [ ] A styler-level test asserts `applyListScannerPass` tags every list line
      in a multi-line buffer (not just the first).

**Verification:**
- [ ] `swift test --package-path Packages/MarcdownStyling` passes including
      the new multi-line styler test.
- [ ] Manual paste tests against a live editor for each acceptance case.

**Dependencies:** Task 4, Task 5, Task 6.

**Files likely touched:**
- `Packages/MarcdownStyling/Tests/MarcdownStylingTests/` (extend existing
  styler tests or add a new file)

**Estimated scope:** S (1 file).

---

### Checkpoint: Feature complete

- [ ] Every success criterion from the spec ticked.
- [ ] `swift test --package-path Packages/MarcdownStyling` green.
- [ ] `swift test --package-path Packages/MarcdownCore` green.
- [ ] `xcodebuild -scheme Marcdown -configuration Debug build` green.
- [ ] Manual smoke against every success criterion checkbox.
- [ ] Ready for review.

---

## Risks and mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| `ListLineScanner` accidentally matches checkbox lines, double-tagging glyphs | Med | Scanner returns `.none` when `- ` is followed by `[`; pass-level guard re-checks `CheckboxLineScanner` defensively. |
| Multi-digit ordered numbers (`10.`, `100.`) drift visually when the system font is proportional | Med | Force `NSFont.monospacedSystemFont` on the digit char range in the styler pass (same trick as the checkbox 3-char marker). |
| Removing `dimListMarker` regresses something outside the editor (e.g. `HTMLExporter`) | Low | Grep for callers before deletion; `HTMLExporter` reads source text, not styled storage, so it is unaffected. |
| Cursor drifts after Enter / Backspace replacement | Low | `ListContinuation` returns absolute `cursorOffsetInBuffer`; tests assert exact final cursor positions. |
| Layout manager double-draws a marker straddling two dirty rects | Low | Extend the existing `drawnRanges` Set in `CheckboxIconLayoutManager`. |

## Parallelization

- **Task 1 ∥ Task 2** — independent files.
- **Task 4 ∥ Task 5** — different packages, both depend only on Task 1 (and
  Task 2 for the styler). Task 5 can be visually verified once Task 4 lands.
- **Tasks 3 / 6** — sequential (helper before wiring).

## Open questions

None. All product decisions resolved in the spec.
