# Spec: Code Block Visual Styling

## Objective
Match the Raycast notes code block UX: a rounded container that wraps the code content with no visible fence markers. Users never type or see raw ` ``` ` — typing three backticks at the start of an empty line auto-expands into a code block scaffold, and the fence markers stay invisible thereafter.

## User Stories
- As a writer keeping technical notes, I want fenced code blocks to be visually distinct so I can scan and instantly locate code.
- As a user, I want to create a code block by typing ` ``` ` and immediately start writing inside it — no need to manually close the fence or escape from raw markdown.
- As a user reading my notes, I should never see the raw ` ``` ` syntax — it's an implementation detail of the file format, not a reading-time concern.
- As a user toggling between light and dark mode, I want the container to remain legible in both.

## Visual Requirements
- **Container**: each fenced block renders inside a rounded rectangle that spans the full editor content width.
- **Background**: GitHub-style contrast (~8–10%) against the editor background. Light mode = light gray fill; dark mode = lifted near-black.
- **Padding**: the box has visible breathing room above and below the code text (provided by the collapsed fence lines acting as natural top/bottom padding).
- **Typography**: monospace font, body-text-size, comfortable line height.
- **Fence markers**: completely concealed — zero glyph width via `.marcdownConcealed`. The user never sees ` ``` ` at all once the block is created.
- **Caret**: system accent color, unchanged.

## Behavior

### Auto-expansion
When the user types three consecutive backticks at the **start of an empty line** (and only then), Marcdown immediately:
1. Inserts the matching closing fence three lines below
2. Drops the cursor on the empty line between the two fences
3. Renders the container around the now-empty body

The user never types or sees the closing fence — it's part of the scaffold.

**Trigger scope**: start of empty line only. Typing ` ``` ` mid-line or at the end of a line with prose does NOT auto-expand.

### Backspace at the block boundary
Backspace at the top edge of an empty freshly-created block is a **no-op**. The scaffold is not unwrapped. Users delete blocks by selecting the lines and deleting, like any other content.

### Pasted markdown with raw fences
When the user pastes text containing ` ``` ` markers, the styler **auto-collapses** them on the next styling pass — the pasted block renders with the same container treatment as keystroke-created blocks. No special paste handling needed; the styler already runs on every text change.

### Language identifier
Out of scope for v1. The auto-expansion creates a plain block with no language tag.

## Variants & Edge Cases
- **Empty fenced block**: renders as a small but visible container (just the rounded box with padding from collapsed fence lines).
- **Multi-line block**: container grows naturally with content.
- **Very long lines**: follow existing wrap behavior; container background extends across wrapped lines.
- **Unclosed fence** (rare, since auto-expansion produces matched pairs): container extends from opening fence to end of document. Acceptable — pragmatic over perfect.
- **Inline code** (single backticks): unchanged; existing `.backgroundColor` treatment preserved.
- **Light/dark mode**: GitHub-style contrast in both.
- **Selection inside a block**: native selection highlight renders cleanly over the container fill.
- **Adjacent blocks** (separated by blank line): render as two distinct containers.

## Success Criteria
A reviewer can confirm this is done when:

1. Typing ` ``` ` at the start of an empty line instantly produces a rounded container with the cursor positioned inside an empty body line. No raw fence markers are visible at any point.
2. Typing ` ``` ` mid-line or at end-of-line-with-text does NOT auto-expand.
3. After auto-expansion, typing code inside the block appears in monospace inside the container.
4. The fence marker lines have zero glyph width — `.marcdownConcealed` is set on them.
5. The rounded container wraps the entire block including the (zero-width) fence lines, giving natural top/bottom padding.
6. Pasting markdown text containing ` ``` ` produces the same visual treatment as keystroke-created blocks.
7. Backspace at the top of an empty freshly-created block is a no-op (the scaffold stays).
8. Light and dark mode both render with GitHub-style contrast.
9. Selection inside a block shows the native highlight without erasing the container background.
10. Two adjacent blocks render as two distinct containers.

## Out of Scope
- Syntax highlighting of code content by language.
- Language identifier (` ```swift `) selection or display.
- Copy-to-clipboard button on the block.
- Line numbers.
- Indented code blocks (4-space variant) — only fenced blocks are in scope.
- Inline code styling changes.
- Configurable themes.
- Cursor-aware fence reveal (removed — fences are never visible).
