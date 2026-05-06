# DESIGN.md

This is the load-bearing design document for Marcdown. Read it before you ship
a button. If you find yourself inventing a token, a color, an animation
duration, or a piece of copy voice — first check this file. If it isn't here
and the answer is non-obvious, propose an addition in your PR rather than
silently introducing a new variant.

The codebase already has a working visual language. This document does two
things: it **canonizes** what's there, and it **decides** the handful of places
where the implementation is currently inconsistent so future agents stop
relitigating them.

## What Marcdown is, in design terms

Marcdown is a background macOS application. The user summons it with `⌘⇧Space`
into a floating, non-activating HUD panel and writes markdown. There is no
menu bar, no dock icon, no document picker, no ribbon. The product fits inside
the same family as **Raycast** (HUD chrome, monospaced restraint, keyboard-first),
**Linear** (`⌘K` density, copy as a feature), and **Spotlight** (the panel as
an invocation, not a window). When in doubt, look at how those products handle
your situation, then decide.

The two reference files inside this repo that already meet the bar are
`App/Sources/HeaderBar.swift` and `App/Sources/RaycastTooltip.swift`. They are
the calibration target for everything else.

A note on principle. Rams: *as little design as possible.* Ive: *users can
sense care and can sense carelessness.* These are two halves of the same idea
and they are the only quotes you should be hearing in your head while you
design here. Don't add what doesn't earn its pixels. Care about the pixels
that do.

## Product voice

Marcdown sounds like a colleague who respects your time, not a feature catalog.
Sentences are short. Verbs are plain. Nothing is exclamatory. Empty states are
warm, not cute. Errors say what happened and what to do, in that order.

Cold, wrong:

> No items found in collection.
> Failed to perform operation. Error code: 4.
> Are you sure you want to delete this note? This action cannot be undone.

Warm, right:

> No matches for "abc". Press ⏎ to create it.
> Couldn't save — the notes folder is unavailable. Try again in a moment.
> Deleted *Untitled*. (toast, 4s)

Copy rules:

- **Sentence case** for every label, button, action title, menu item, and
  toast. Title case is reserved for proper nouns. (`Find a Note`, not
  `Find A Note`.)
- **No trailing period** on a single short string (button, label, toast,
  empty state under ~6 words). Use a period only when the string is a real
  sentence with two or more clauses.
- **Ellipsis (`…`, the character, never `...`)** on any action that opens
  further UI. `Find a Note…` opens the switcher; `New Note` does not. This
  matches Apple HIG.
- **Real keyboard glyphs** for shortcuts: `⌘`, `⇧`, `⌥`, `⌃`, `⏎`, `⌫`, `⎋`,
  arrows. Never `Cmd`, `Shift`, `CMD+K`. See the keycap component.
- **One verb per action title.** "Duplicate Note", not "Make a Copy of the
  Current Note". The shortest honest verb wins.
- **No first person from the app.** The app does not say "I" or "we". It
  describes the state, not its own feelings about the state.
- **No emoji in product copy or in this repo.** Project convention.

Three canonical empty-state strings to copy from:

```
Quick Switcher, no notes yet:        "No notes yet. Press ⌘N to create one."
Quick Switcher, no matches:          "No matches for \"<query>\". Press ⏎ to create it."
Command Palette, no matches:         "No matching actions"
```

## Typography

Marcdown uses the system font (`-apple-system` / SF) at four sizes. Anything
outside this scale is a smell — flag it in review.

| Token         | Size | Weight    | Use                                                      |
|---------------|------|-----------|----------------------------------------------------------|
| `body`        | 13pt | regular   | Default UI text; palette/switcher list rows; HeaderBar title |
| `bodyStrong`  | 13pt | semibold  | Switcher row titles (`QuickSwitcher.swift:125`)          |
| `label`       | 12pt | regular   | Tooltip label (`RaycastTooltip.swift:134`)               |
| `secondary`   | 11pt | regular   | Footer character count, switcher previews, tooltip keycap |
| `tertiary`    | 10pt | medium    | Inline status pills ("Current"); reserved for one-glance status |

Editor body font lives separately from the chrome font. The editor is set in
`NSFont.systemFont(ofSize: 14)` — see `NoteEditorView.swift:62` and
`MarkdownStyler.init`. Heading sizes are derived from this base in
`StyleWalker.headingSize`: H1 +10, H2 +7, H3 +4, H4 +2, H5 +1, H6 +0. **Do not
hardcode heading sizes elsewhere.** If you need to render markdown previews
outside the editor, route them through `MarkdownStyler` so the scale stays
consistent.

Code spans and code blocks render in `NSFont.monospacedSystemFont(ofSize:
baseFont.pointSize, weight: .regular)` — see `StyleWalker.monospacedFont`. The
chrome never uses a monospaced font; the editor body never uses a proportional
font for code.

System font, always. We do not bundle a typeface.

## Color

Marcdown follows system appearance. We don't ship a custom palette. Color is
expressed as **roles**, not as hex values:

| Role            | Token                              | Use                                                      |
|-----------------|------------------------------------|----------------------------------------------------------|
| Body            | `.primary` / `NSColor.labelColor`  | Default text                                             |
| Secondary       | `.secondary`                       | Supporting metadata, icons by default                    |
| Tertiary        | `.tertiary`                        | Counts, character totals, "no matching" empty state      |
| Accent          | `Color.accentColor` / `NSColor.controlAccentColor` | Selection, current-note indicator, create actions, focus ring |
| Destructive     | `.red` (system red)                | Delete-icon tint and label tint when isolated as the destructive action |
| Code background | `NSColor(white: 0.5, alpha: 0.12)` | Inline code / fenced block background — see `StylingTheme.swift:36` |
| Quote bar       | `.tertiaryLabelColor`              | Blockquote leading bar                                   |

The styling theme (`StylingTheme.system`) is the source of truth for editor
colors. Do not introduce a second theme. If you need an additional accent
state in the chrome, derive it from `Color.accentColor` with opacity (`0.15`,
`0.20`, or `0.25` — see the spacing/opacity rule below), not from a new color.

**Scrim** behind any modal overlay is `Color.black.opacity(0.18)`. This value
is canonical — see `PanelRootView.swift:174` and `:192`. Don't drift.

We rely on the system to do the right thing in dark mode, increased contrast,
and accessibility-tinted appearance. Anything you write must work in all three
without branching.

## Spacing

The codebase has converged on a small scale. Use these tokens; if you reach
for a value not on the scale, you're probably wrong.

| Token | Value | Where it lives                                                                 |
|-------|-------|--------------------------------------------------------------------------------|
| `xxs` | 2pt   | Internal stack spacing inside list rows (switcher title/preview)               |
| `xs`  | 4pt   | Gaps between adjacent icon buttons in HeaderBar (`HeaderBar.swift:19`)         |
| `sm`  | 6pt   | IconButton corner radius; FooterBar vertical padding; corner radius for keycap pills |
| `md`  | 8pt   | List row vertical padding; tooltip horizontal padding; inter-element gaps      |
| `lg`  | 12pt  | Search-field vertical padding (`CommandPalette.swift:83`)                      |
| `xl`  | 14pt  | Horizontal padding for HeaderBar, FooterBar, palette, switcher rows. **Canonical** |
| `2xl` | 24pt  | Overlay horizontal padding from panel edge (target — see TODO-1)               |
| `3xl` | 32pt  | Overlay vertical padding from panel edge (target — see TODO-1)                 |

**14pt horizontal is the chrome's edge gutter.** Header, footer, palette rows,
switcher rows — all 14pt. If you build a new chrome surface and pick 12pt or
16pt, you'll have created a third standard. Don't.

## Surfaces

There are exactly four surfaces in Marcdown. Each has a token, a fixture, and
a rule.

### Panel — `surface.panel`

The host window. `MarcdownPanel : NSPanel` with style mask `[.titled,
.closable, .resizable, .fullSizeContentView, .hudWindow, .nonactivatingPanel]`,
`level = .floating`, `isFloatingPanel = true`. Constraints in
`PanelSizeConstraints`: minWidth 400, maxWidth 720, minHeight 300, screen
margin 16.

Use the panel for the editor and only the editor. Settings live in their own
window. There is no second panel kind.

### Overlay — `surface.overlay`

The palette and switcher. Anatomy:

```swift
.frame(width: 520, height: 340)              // -> see TODO-1: should be maxWidth/maxHeight
.background(VisualEffectBackground())        // .hudWindow, .behindWindow
.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
.overlay(
    RoundedRectangle(cornerRadius: 10, style: .continuous)
        .strokeBorder(.separator, lineWidth: 1)
)
.shadow(radius: 30, y: 10)
```

Always paired with a `Color.black.opacity(0.18)` scrim that ignores the safe
area and dismisses the overlay on tap. Wrap dismiss in
`withAnimation(.easeOut(duration: 0.15))`.

**Sizing rule (canonical target):** `maxWidth: 520, maxHeight: 340`, with 24pt
horizontal and 32pt vertical padding from the panel edge. The current
implementation uses fixed `width: 520`, which violates the panel's 400pt
minimum width — TODO-1 in `.qa-reports/design-followups-2026-05-06.md` tracks
the fix. New overlays must follow the canonical rule, not the current fixed
form.

### Tooltip — `surface.tooltip`

`RaycastTooltip` rendered into its own borderless `NSWindow` at level
`.statusBar` (above the floating panel, below real menus). The tooltip's
visual treatment is fixed and not theme-able:

```swift
.background(
    RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(Color(white: 0.13))
)
```

Hover delay is 400ms first time, instant for siblings (sibling-fluidity rule
in `TooltipModel`). The tooltip is the only surface in the product that is
explicitly dark in both light and dark mode — it's a HUD artifact, not chrome.

### Scrim — `surface.scrim`

`Color.black.opacity(0.18)`, `.ignoresSafeArea()`, tap to dismiss. Used only
under overlays. Not a substitute for a sheet, and not stackable — at most one
scrim is on screen at a time, enforced by the `ActiveOverlay` state machine.

## Iconography

SF Symbols only. No raster icons, no custom SVG. The product runs on macOS
15+; the full SF Symbols 5 catalog is available.

Sizes:

- **Button cell:** 28×28pt with a 6pt continuous corner. The icon itself is
  whatever default size SF Symbols renders at the inherited font size — do
  not set `.font(.system(size:))` on the icon. See
  `HeaderBar.IconButtonStyle.makeBody`.
- **List-row leading icon:** `.frame(width: 20)` so titles align across rows
  regardless of glyph width. See `CommandPalette.swift:136`.
- **Search-field leading icon:** intrinsic, paired with `.foregroundStyle(.secondary)`.

**Three-color icon system** (canonical, replacing the current "everything is
secondary"):

```swift
enum PaletteCategory { case create, navigate, modify, destructive }

// create       -> .accentColor       (New Note, +, plus.circle)
// navigate     -> .secondary         (Browse, Find, Previous, Next, list rows)
// modify       -> .secondary         (Duplicate, Rename)
// destructive  -> .red               (Delete, Discard)
```

Three colors max. Resist category bingo. The point of three is that destructive
visually separates from create at peripheral-vision speed; if you add a fourth
color you've lost the affordance.

**Filled vs outline:** prefer SF Symbol defaults. Use `.fill` variants only
when a glyph reads as ambiguous in outline at small sizes (rare). Selection
state never swaps the glyph — it changes the row background, not the icon.

## Motion

Motion in Marcdown is short, eased-out, and deferential. Three named tokens:

| Token       | Duration | Curve     | Use                                                   |
|-------------|----------|-----------|-------------------------------------------------------|
| `quick`     | 0.08s    | `.easeOut`| Hover background fade-in; scroll-to-selected snap     |
| `standard`  | 0.15s    | `.easeOut`| Overlay open/close; scrim fade; state-change defaults |
| `deferred`  | 0.20s    | n/a       | Post-dismissal trampoline (`triggerFind` after overlay) |

Used in code as:

```swift
withAnimation(.easeOut(duration: 0.08)) { isHovering = true }     // quick
withAnimation(.easeOut(duration: 0.15)) { activeOverlay = .none } // standard
DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { ... }     // deferred
```

A fourth token, `swap` (0.18s, directional `.move(edge:).combined(with:
.opacity)`), is reserved for the palette → switcher transition where two
near-identical surfaces need to read as a context shift, not a refresh. See
TODO-3.

**Reduced-motion rule:** every `withAnimation(...)` call must respect the
`accessibilityReduceMotion` environment value. The pattern:

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion
// ...
withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { ... }
```

Hover-background fades and scroll-snap animations should also be suppressed
under reduce-motion, not just overlay transitions.

## Components

Each component below has: name, anatomy, sizes, states, do/don't.

### IconButton — `component.iconButton`

**Anatomy.** A 28×28pt cell wrapping an SF Symbol, with a continuous-corner
`6pt` rounded background that fades in on hover and presses darker.

**Reference.** `App/Sources/HeaderBar.swift:49–81`.

```swift
private var backgroundOpacity: Double {
    if configuration.isPressed { return 0.14 }
    if isHovering              { return 0.08 }
    return 0
}
```

**States.** Idle (transparent), hover (`Color.primary.opacity(0.08)`, faded in
over `quick`), pressed (`0.14`, instant). Disabled state should be `.opacity(0.4)`
on the label (not yet implemented; declare it now).

**Do.** Use this style for any chrome icon button that opens further UI.
**Don't.** Use it for a primary call-to-action — IconButtons are tertiary
affordances. **Don't.** Pair with a tooltip whose label simply restates the
visible glyph; tooltips exist to disambiguate.

### Keycap — `component.keycap`

**Anatomy.** A small rounded rectangle with a single key glyph, used inside
tooltips and inside any palette/switcher row that displays a shortcut.

**Reference (canonical).** `RaycastTooltip.swift:139–156`.

```swift
Text(key)
    .font(.system(size: 11, weight: .medium))
    .foregroundStyle(Color.white.opacity(0.92))
    .padding(.horizontal, 4)
    .padding(.vertical, 1)
    .background(
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.white.opacity(0.12))
    )
    .overlay(
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .stroke(Color.white.opacity(0.15), lineWidth: 1)
    )
```

**Multi-key shortcuts** render as a tight `HStack(spacing: 3)` of individual
keycaps (`⇧`, `⌘`, `⌫`), never as a single concatenated string.

The `Capsule().fill(.quaternary)` shortcut pill currently used in
`CommandPalette.row(for:)` is **not** canonical and is targeted for
replacement (TODO-6). New surfaces use the keycap.

The keycap on a tooltip background uses `Color.white.opacity(0.12)` because
the tooltip surface is fixed-dark. On a chrome surface (palette/switcher rows),
swap white for primary so it works in light mode:

```swift
.fill(Color.primary.opacity(0.08))
.stroke(Color.primary.opacity(0.10), lineWidth: 1)
.foregroundStyle(.secondary)
```

### Overlay (palette / switcher) — `component.overlay`

**Anatomy.** Search field on top (44pt tall, 14pt horizontal padding, 12pt
vertical padding, magnifying glass leading icon), `Divider`, scrolling list
below, all wrapped in `surface.overlay` chrome.

**Sizing rule.** Use the canonical `maxWidth: 520, maxHeight: 340`, padded
24pt horizontal / 32pt vertical from the panel edge. At the 400pt panel
minWidth, the overlay shrinks to ~352pt — verify rows still hold (title +
spacer + keycap row).

**States.** Loading, populated, no matches, no items at all. Every overlay
must specify all four. See "State coverage standard" below.

**Differentiation rule.** When two overlays share the same anatomy, the
search-field leading icon is what tells them apart. Palette: `command`.
Switcher: `magnifyingglass`. The transition between them uses the `swap`
motion token.

### List row — `component.listRow`

**Anatomy.** 14pt horizontal padding, 8pt vertical padding,
`maxWidth: .infinity` leading-aligned. A row contains: optional 2pt accent
leading bar (selected only), optional 6pt accent dot (current-note indicator
in switcher), 20pt-wide leading icon, title (`body`/`bodyStrong`), optional
preview (`secondary`), spacer, optional trailing keycap row.

**Selection state (canonical).**

```swift
HStack(spacing: 0) {
    Rectangle()
        .fill(isSelected ? Color.accentColor : .clear)
        .frame(width: 2)
    rowContent
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
}
```

The 2pt leading bar is the keyboard reader's anchor at peripheral vision speed.
The current implementation uses a 0.25-opacity fill alone and is tracked for
update in TODO-12.

**Hover-vs-keyboard arbitration.** Hover sets `selectedIndex` only if
`isUsingKeyboard == false`. The `isUsingKeyboard` flag is set by every
arrow-key press and cleared by `onContinuousHover` reporting `.active` (real
pointer motion, not just a parked cursor). See `CommandPalette.swift:106–123`
— this pattern is canonical and any new selectable list must reproduce it.

**Don't.** Truncate-on-narrow-row by removing the keycap. Truncate the title
first; the keycap is the user's keyboard contract.

### Toast — `component.toast` (proposed)

Currently no implementation; declare the spec now so the next agent has a
target. Used to acknowledge palette-driven actions that otherwise produce no
visible UI change (create, duplicate, delete).

**Anatomy.** A single-line label, optional secondary metadata, in
`surface.tooltip` chrome (`Color(white: 0.13)`, 6pt corner, 8pt horizontal /
5pt vertical padding), anchored above the FooterBar with 12pt bottom inset.

**Duration.** 1.5s for benign actions, 4s for destructive (delete). Fade in
and out on `standard` motion.

**Copy.**

```
Created       -> "New note"
Duplicated    -> "Duplicated"
Deleted       -> "Deleted *Title*"        (4s, italic on title)
```

No toast for navigation (prev/next/jump) — the title in HeaderBar is the
feedback.

### Search field — `component.searchField`

**Anatomy.** `HStack` of leading SF Symbol (`magnifyingglass` for switcher,
`command` for palette) + plain `TextField`, with 14pt horizontal and 12pt
vertical padding inside the overlay.

**Focus ring (canonical).** Wrap the HStack in a 6pt continuous `RoundedRectangle`
overlay tied to the `@FocusState`:

```swift
.overlay(
    RoundedRectangle(cornerRadius: 6, style: .continuous)
        .strokeBorder(
            queryFieldFocused ? Color.accentColor : .clear,
            lineWidth: 1
        )
)
```

The default SwiftUI focus ring is invisible against `.hudWindow` material —
this explicit ring is the rule, not a polish item.

**Focus deferral.** The `queryFieldFocused = true` assignment must be
deferred to the next runloop tick when the overlay is mounted as part of a
swap from another overlay. Use `Task { @MainActor in queryFieldFocused = true }`
inside `onAppear`. See `CommandPalette.swift:43–53` and the rationale comment.

## Interaction patterns

### Overlay vs shortcut precedence

When an overlay is active, every chrome shortcut except `⌘K` and `⌘P` is
disabled — those two stay live so the user can dismiss-or-swap. Implementation
in `PanelRootView.shortcutLayer` via `.disabled(activeOverlay != .none)`.

When a disabled shortcut is pressed while the overlay is active, the search
field flashes a 1pt accent border for 180ms. Tracked as TODO-8. The principle:
silently dropping a keystroke is an erosion of trust.

### Esc routing

`Esc` is routed overlay-first via `EscapeKeyMonitor` (a local `NSEvent` monitor
installed only while `activeOverlay != .none`). If no overlay is active, Esc
falls through to `MarcdownPanel.cancelOperation`, which hides the panel and
returns focus to the previous app. Never call `controller.hide` from inside an
overlay's Esc handler.

### Keyboard vs pointer arbitration

Keyboard wins while it's being used. Pointer wins when it moves. The
`isUsingKeyboard` flag captures this — set by arrow-key presses, cleared by
`onContinuousHover`'s `.active` phase. Any new list must reproduce this; do
not let hover yank a selection that the keyboard set.

### Confirmation for destructive actions

There is no modal confirmation for destructive actions — the `Are you sure?`
alert was removed in commit `e1bf16c`. Instead:

1. The destructive action is **isolated** in its menu/palette (last in the
   list, with a divider above and a 12pt gap).
2. The icon is tinted `.red`.
3. The result is acknowledged via a 4-second toast naming the deleted item.
4. Undo is out of scope for v1 — when it lands, undo is the right answer to
   "are you sure?", not an alert.

## State coverage standard

Every list-bearing surface must specify, in code and in copy, all four
states:

| State            | Trigger                                          | Treatment                                         |
|------------------|--------------------------------------------------|---------------------------------------------------|
| Loading          | Backing data not yet bootstrapped                | Centered `secondary` text + opacity-pulse (skip pulse under reduce-motion) |
| Truly empty      | Bootstrapped, zero items                         | Centered `body` text + the next action and its shortcut as a keycap |
| No results       | Query produces zero matches                      | Centered `body` text naming the query + the create-from-query action if applicable |
| Populated        | The happy path                                   | The list                                          |

The `loading` and `truly empty` states must not be conflated — `notes ==
[]` is not enough information to say "no notes." Surface a separate
`isBootstrapping` flag from the backing store. Tracked as TODO-2.

Three canonical strings (re-stated from Voice for proximity):

```
Switcher loading:   "Loading notes…"
Switcher empty:     "No notes yet. Press ⌘N to create one."   + ⌘N keycap
Switcher no match:  "No matches for \"<query>\". Press ⏎ to create it."
```

## Accessibility floor

These are non-negotiable. If a surface ships without them, it ships broken.

- **VoiceOver labels** on every actionable element. For list rows:
  `accessibilityLabel("<title>, <shortcutLabel>")` and
  `accessibilityValue("Row \(index + 1) of \(filtered.count)")`.
- **Search field count announcement:**
  `accessibilityLabel("Search actions, \(filtered.count) result(s)")`.
- **Keyboard reachability** for every action. If it's in a menu or palette,
  it must be operable from arrow keys + return. If it has a shortcut, the
  shortcut works from the editor too.
- **Visible focus** on every focusable control. The default SwiftUI focus ring
  on `.hudWindow` material is not visible — use the explicit accent ring per
  `component.searchField`.
- **`accessibilityReduceMotion`** honored on all `withAnimation` sites.
- **System contrast.** All chrome uses `.primary`/`.secondary`/`.tertiary` and
  `Color.accentColor`. Do not bake contrast against the `.hudWindow` blur into
  custom colors — the system handles contrast tinting; you would defeat it.
- **Hit targets.** macOS HIG asks for ≥ 28×28pt for mouse targets in compact
  chrome (which is what we're building). The 28pt IconButton meets this. The
  44pt iOS touch target rule does not apply here, but hit targets smaller
  than 28pt do not pass review.

## Decisions deferred

These are explicitly out of scope for v1. Each line says why deferred and what
would trigger a revisit.

- **Custom theming / user-selectable accent.** The system accent is enough.
  Revisit if user research shows accent collision with content (rare for a
  text editor).
- **Light / dark theming beyond system default.** We follow appearance. We do
  not ship a "force dark" mode. Revisit if a meaningful share of users run
  light system + dark editor — currently no signal.
- **Sound design.** No sounds. Revisit if confirmation-by-toast proves
  insufficient and a soft delete chime helps reassure users; do not add
  sounds before that signal exists.
- **Multi-window / multi-panel.** Marcdown is one panel. Revisit if users
  ask for side-by-side editing; the answer is probably split-pane within the
  one panel, not a second window.
- **In-app search across notes.** `⌘F` finds within the current note. Global
  search is the role of the Quick Switcher's title/preview match. Revisit if
  users start typing prose into the switcher expecting full-text results.
- **Undo for destructive actions.** No undo in v1. When added, undo replaces
  the modal-confirmation gap; do not retrofit a confirmation alert in the
  meantime.
- **Editor typography customization.** 14pt system, fixed. Revisit only if
  long-form-writer feedback clusters on it.

---

If you read this far: the bar is `HeaderBar.swift` and `RaycastTooltip.swift`.
Hold every new surface up against those two. If it doesn't sit comfortably
next to them, it isn't done.
