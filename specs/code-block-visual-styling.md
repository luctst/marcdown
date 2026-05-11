# Spec: Code Block Visual Styling

## Objective
Fenced code blocks currently render with broken or absent visual treatment — they read as plain prose, breaking the user's ability to distinguish code from narrative at a glance. We're restoring code blocks to a first-class visual element: a clearly delineated, padded container with monospace typography, comfortable contrast, and a calm aesthetic that fits Marcdown's minimal floating-panel feel. When a user pastes or writes a fenced block, it should feel like a small, well-lit room inside the document.

## User Stories

- As a writer keeping technical notes, I want fenced code blocks to be visually distinct from prose so I can scan a long note and instantly locate code.
- As a developer pasting a snippet, I want the block to render with monospace text and a contained background so the code is readable and doesn't visually bleed into surrounding paragraphs.
- As a user toggling between light and dark mode, I want the code block container to remain legible and aesthetically consistent in both appearances.
- As someone editing inside a code block, I want the container to expand naturally as I type new lines, without flicker, layout jumps, or the background visually detaching from the text.

## Visual Requirements

- **Container**: each fenced block renders inside a visually unified surface that spans the full content width of the editor, with rounded corners.
- **Background**: a subtle fill that is distinctly different from the editor background but never harsh — think a soft tinted panel, not a stark contrast slab. Light mode reads as a faint warm/neutral gray; dark mode reads as a slightly lifted near-black.
- **Padding**: comfortable internal padding on all four sides so code never touches the container edge. Top and bottom padding clearly separate the block from surrounding paragraphs.
- **Typography**: monospace font for the code itself, sized at parity with body text (not smaller, not larger). Line height tuned for code readability — slightly tighter than prose but still breathable.
- **Fence markers** (the triple-backtick lines and any language identifier): visually de-emphasized — dimmed in color, optionally smaller, and clearly subordinate to the code content. They should feel like quiet metadata, not part of the code.
- **Vertical rhythm**: a clear margin above and below the block to separate it from adjacent paragraphs, headings, or other blocks.
- **No borders required**: fill alone should carry the visual delineation. If a border is used, it must be extremely subtle (hairline, low-contrast).

## Variants & Edge Cases

- **Inline code** (single backticks): out of scope for this fix's container treatment, but should remain visually distinct (existing inline styling preserved — monospace + subtle inline highlight). Must not be confused with or affected by block styling.
- **Single-line fenced block**: still renders as a full container with proper padding — does not collapse to a tight one-line strip.
- **Multi-line fenced block**: container grows naturally with content; background remains continuous across all lines with no gaps between lines.
- **Empty fenced block** (opening and closing fences with nothing between): renders as a small but visible container — user should see that an empty code block exists.
- **Very long lines**: code that exceeds the editor width should follow the editor's existing wrap behavior; the container background must extend correctly across wrapped lines without visual breaks.
- **Language identifier present** (e.g., ` ```swift `): the language tag is visually de-emphasized along with the opening fence; it does not need to render as a styled label or badge in this iteration.
- **Unclosed fence** (user is actively typing, no closing fence yet): block should still render with the container styling from the opening fence onward, gracefully, without flicker on every keystroke.
- **Light mode**: warm/neutral light fill, dark code text, dimmed fence markers.
- **Dark mode**: lifted dark fill, light code text, dimmed fence markers — equivalent visual weight to light mode.
- **Selection inside a block**: native text selection highlight renders cleanly over the container fill; selection is fully visible and the container background is not lost under it.
- **Cursor inside a block**: caret is clearly visible against the container fill in both light and dark mode.
- **Scrolling**: container fill scrolls with the text — no detachment, no lag, no z-order glitches over other styled elements.
- **Adjacent blocks**: two fenced blocks separated by a blank line render as two distinct containers with clear visual separation, not as one merged block.

## Success Criteria

A reviewer can confirm this is done when:

1. Typing ` ``` `, pressing Enter, typing several lines of code, and closing with ` ``` ` produces a visibly contained, padded, monospace block — distinct from surrounding prose at first glance.
2. The opening and closing fence lines are dimmed and visually subordinate to the code content.
3. The container background extends uniformly across every line of the block, including wrapped lines and empty lines within the block.
4. Switching between light and dark mode (system appearance change) results in a code block that remains legible, aesthetically consistent, and proportionally contrasted in both.
5. Selecting text inside a code block shows the native selection highlight clearly without erasing or obscuring the container background.
6. Editing inside a block (adding/removing lines, typing rapidly) does not cause visible flicker, background gaps, or layout jumps.
7. An inline code span on the same line as prose remains styled as inline code and is not promoted to block styling.
8. An empty fenced block is visible as a small container, not invisible.
9. Two adjacent fenced blocks separated by a blank line render as two distinct containers.
10. The block visual passes a side-by-side comparison against Bear or Typora at a "feels equivalently polished" bar — not pixel-identical, but in the same quality tier.

## Out of Scope

- Syntax highlighting of code content by language (keywords, strings, comments colored differently). Code text inside the block is uniformly styled in this iteration.
- Language label badges rendered as styled chips or pills above the block.
- Copy-to-clipboard button or any interactive affordance attached to the block.
- Line numbers inside code blocks.
- Indented code blocks (the 4-space indent variant) — only fenced (triple-backtick) blocks are in scope.
- Inline code styling changes — existing inline code treatment is preserved as-is.
- Configurable themes or user-customizable code block colors.
- Code folding or collapsing of long blocks.

## Open Questions

1. Should the fence lines (` ``` ` and optional language identifier) be **concealed entirely** when the cursor is outside the block (consistent with how Marcdown conceals other markdown syntax like bold/italic markers), or always remain visible-but-dimmed? This is a meaningful UX choice — concealment is more elegant but can disorient users who expect to see the raw markdown.
2. Should the container span the **full editor width** or be **inset** from the left/right margins (similar to a blockquote indent)? Full-width reads cleaner; inset reads more like a "card."
3. What is the target **contrast ratio** between the container fill and the editor background — barely-there (Notion-style, ~3% difference) or more pronounced (GitHub-style, ~8–10% difference)?
4. Should the **caret color** change inside a code block, or remain the system accent? Some editors shift to a neutral caret inside code to reduce visual noise.
5. For an **unclosed fence** still being typed, should the container render immediately on the opening fence line, or only after the closing fence is detected? Immediate rendering is more responsive but can feel "twitchy" if the user is mid-thought.
