# Spec: Overlay Fixes — 2026-05-06

## Triage Summary

| Finding | Verdict | Rationale |
|---------|---------|-----------|
| TODO-1 — Hardcoded 520pt overlay frame | **Ship it** | Visual clip at minimum panel width. Real, reproducible, zero ambiguity. |
| TODO-2 — "No matching notes" during bootstrap | **Ship it** | False empty state erodes trust on every cold open. Small lift, high signal value. |
| TODO-17 — No DESIGN.md | **Dead** | DESIGN.md exists at repo root, 577 lines, well-maintained. Thomas was wrong. See note below. |

### TODO-17 — Closed

DESIGN.md exists and is load-bearing: it canonizes font tokens, color roles, spacing scale, and product voice; it even names TODO-1 by number in the spacing table (`2xl`/`3xl` tokens). The overlays already use the tokens it documents (14pt horizontal padding, `.tertiary` for empty states, `0.18` scrim). There is no underlying gap to fix. Drop this entirely.

---

## TODO-1 — Overlay Frame Clipping

### Problem Statement

`QuickSwitcher` and `CommandPalette` render at a hardcoded `520×340pt` frame. `PanelController` allows the panel to shrink to `400pt` wide, and `PanelRootView` sets a SwiftUI minimum of `480pt` wide. At either minimum, the overlay is wider than its container by 40–120pt, visually clipping through the panel edge.

### Target User

Every Marcdown user who has resized the panel narrower than 520pt — which is any user who has touched the resize handle at all, since the default opens at 720pt and the resize range bottoms at 400pt.

### Root Cause

Both overlays use `.frame(width: 520, height: 340)`. The correct pattern for an overlay that must fit inside a variable-width parent is `.frame(maxWidth: .infinity, maxHeight: .infinity)` with explicit horizontal padding from the panel edge, so SwiftUI's layout system constrains it to whatever the panel actually is.

DESIGN.md has already canonized the target padding: `2xl` = 24pt horizontal, `3xl` = 32pt vertical (spacing table, lines 147–148).

### Solution

Replace the fixed `.frame(width: 520, height: 340)` modifier in both overlays with:

```swift
.frame(maxWidth: 520, maxHeight: 340)
.padding(.horizontal, 24)
.padding(.vertical, 32)
```

`maxWidth: 520` preserves the preferred width on wide panels. The padding ensures the overlay never touches the panel edge. On narrow panels SwiftUI will compress to `panelWidth - 48pt`.

> Note: the padding is applied at the `QuickSwitcher`/`CommandPalette` call site in `PanelRootView`, not inside the component itself. The component should own its preferred max dimensions; the overlay chrome in `PanelRootView` owns the positioning margin.

### Success Criteria

- At panel width 400pt: overlay width = 352pt (400 - 48). No clipping.
- At panel width 480pt: overlay width = 432pt. No clipping.
- At panel width 720pt (default): overlay width = 520pt (capped by maxWidth). No change from current preferred size.
- Corner radius and shadow remain visually correct at all widths.
- No regression to keyboard navigation or focus behavior.

### Out of Scope

- Changing the overlay height behavior (maxHeight: 340 preserves current behavior).
- Making the overlay size user-configurable.
- Changing padding values not specified by DESIGN.md.

---

## TODO-2 — False "No matching notes" During Bootstrap

### Problem Statement

When the panel first opens, `NotesStore.bootstrap()` runs asynchronously. During the gap between overlay mount and bootstrap completion, `store.notes` is `[]`. `QuickSwitcher` renders `"No matching notes"` for this empty array — the same string it shows for a genuine search miss. The user sees a lie on every cold open.

### Target User

Every user who opens the QuickSwitcher (⌘P) within the first ~200ms of panel show — which in practice includes any user on a slower machine or with a large notes folder.

### Root Cause

`NotesStore` exposes no `isBootstrapping` flag. `QuickSwitcher.list` has two states: populated list, or `"No matching notes"`. There is no third state for "data not yet available."

`CommandPalette` does not have this problem — its actions are computed synchronously from `PanelRootView` state, not loaded async.

### Solution

**Step 1 — Add `isBootstrapping` to `NotesStore`**

Add a `private(set) var isBootstrapping: Bool = true` property. Set it to `false` after `apply(snapshot:ensureScratchIfEmpty:)` completes for the first time (i.e., at the end of the bootstrap task, before the stream subscription starts).

**Step 2 — Pass the flag into `QuickSwitcher`**

Add `let isBootstrapping: Bool` to `QuickSwitcher`'s init. `PanelRootView.switcherOverlay` passes `store.isBootstrapping`.

**Step 3 — Three-state `list` view in `QuickSwitcher`**

```swift
@ViewBuilder
private var list: some View {
    if isBootstrapping {
        // Loading state — notes not yet available
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if filtered.isEmpty {
        Text(emptyStateText)
            .font(.system(size: 13))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
        populatedList
    }
}

private var emptyStateText: String {
    if query.trimmingCharacters(in: .whitespaces).isEmpty {
        return "No notes yet. Press \u{2318}N to create one."
    } else {
        return "No matches for \"\(query.trimmingCharacters(in: .whitespaces))\". Press \u{23CE} to create it."
    }
}
```

The copy matches DESIGN.md's canonical empty-state strings exactly (lines 74–75).

> Note: the "Press ⏎ to create it" affordance in the no-matches state implies the user can hit Return to create a note with that title. If `onSubmit` does not currently do that, the copy should be "No matches" without the creation affordance until that behavior is wired. Do not add copy that implies functionality that doesn't exist.

### Success Criteria

- On cold open (bootstrap not yet complete): QuickSwitcher shows `ProgressView`, not "No matching notes".
- After bootstrap completes with notes: list populates normally.
- After bootstrap completes with zero notes: shows "No notes yet. Press ⌘N to create one."
- When query has no matches: shows "No matches for \"<query>\"." (with or without the creation affordance, depending on whether onSubmit is wired to create).
- `isBootstrapping` transitions from `true` → `false` exactly once, after the first snapshot is applied.
- No regression to `CommandPalette` (it does not consume this flag).

### Out of Scope

- Adding a loading state to `CommandPalette` (not needed — actions are static).
- Showing a loading skeleton or shimmer (ProgressView is sufficient).
- Persisting bootstrap state across show/hide cycles (flag should reset on each `bootstrap()` call if the store is recreated — currently it is not recreated, so `false` is permanent after first boot, which is correct).

---

## Ordered Task List for the Coding Agent

### Task 1 — Add `isBootstrapping` to `NotesStore`

**Files touched:** `App/Sources/NotesStore.swift`

**What to do:**
1. Add `private(set) var isBootstrapping: Bool = true` as a stored property (alongside `notes`, `currentNote`, etc.).
2. In `bootstrap()`, after `await task.value` resolves (i.e., after the inner task body completes), this is already handled by the task body itself — set `isBootstrapping = false` as the last line inside the `Task { @MainActor in ... }` block, after the stream subscription is installed.

**Acceptance criteria:**
- `store.isBootstrapping` is `true` immediately after `NotesStore.init()`.
- It becomes `false` after `bootstrap()` completes.
- It stays `false` on subsequent `bootstrap()` calls (idempotent — the guard at the top of `bootstrap()` returns early if `bootstrapTask` is already set).

**Verify:** Add a `@Test` in `MarcdownCore` or at the App level that creates a `NotesStore`, checks `isBootstrapping == true`, calls `await store.bootstrap()`, then checks `isBootstrapping == false`.

---

### Task 2 — Thread `isBootstrapping` into `QuickSwitcher` and update empty states

**Files touched:** `App/Sources/QuickSwitcher.swift`, `App/Sources/PanelRootView.swift`

**Depends on:** Task 1

**What to do:**
1. Add `let isBootstrapping: Bool` to `QuickSwitcher`'s property list (after `currentNote`).
2. Replace the two-branch `list` computed property with the three-branch version from this spec.
3. Replace the hardcoded `"No matching notes"` string with `emptyStateText` (computed from `query`).
4. In `PanelRootView.switcherOverlay`, pass `isBootstrapping: store.isBootstrapping` to the `QuickSwitcher` initializer.

**Copy to use (verbatim from DESIGN.md):**
- No notes, no query: `"No notes yet. Press ⌘N to create one."`
- No matches, query present: `"No matches for \"<query>\"."`  (drop "Press ⏎ to create it" unless onSubmit creates a note)
- Loading: `ProgressView()` — no label text

**Acceptance criteria:**
- QuickSwitcher opened before bootstrap shows `ProgressView`.
- QuickSwitcher opened after bootstrap with notes shows the list.
- QuickSwitcher opened after bootstrap with empty vault shows the "No notes yet" string.
- Filtering to no matches shows the "No matches for..." string.
- No change to `CommandPalette`.

**Verify:** Build succeeds. Manual test: add a `Task.sleep` before `index.start()` in a debug build to simulate slow bootstrap; open QuickSwitcher during the delay.

---

### Task 3 — Fix overlay frame clipping

**Files touched:** `App/Sources/PanelRootView.swift`

**Depends on:** None (independent of Tasks 1–2, but run after to minimize diff noise)

**What to do:**

In `switcherOverlay`, change:
```swift
QuickSwitcher(
    notes: store.notes,
    onOpen: { url in ... },
    onDismiss: { activeOverlay = .none },
    currentNote: store.currentNote
)
```
to wrap it with padding:
```swift
QuickSwitcher(...)
    .padding(.horizontal, 24)
    .padding(.vertical, 32)
```

In `commandPaletteOverlay`, apply the same `.padding(.horizontal, 24).padding(.vertical, 32)` to the `CommandPalette(...)` call.

Inside `QuickSwitcher.swift` and `CommandPalette.swift`, change:
```swift
.frame(width: 520, height: 340)
```
to:
```swift
.frame(maxWidth: 520, maxHeight: 340)
```

**Acceptance criteria:**
- At panel width 400pt: overlay width = panel width minus 48pt = 352pt. No clipping, no overflow.
- At panel width 720pt: overlay width = 520pt (maxWidth cap applies). Visual parity with current behavior.
- Shadow, corner radius, stroke border render correctly at all widths.
- Keyboard navigation (arrow keys, Enter, Escape) unaffected.

**Verify:** Resize panel to minimum width (drag resize handle left until AppKit stops). Open ⌘P and ⌘K. Confirm overlay is inset from panel edge on both sides.

---

## What Was Cut and Why

**TODO-17 (DESIGN.md missing):** Finding was factually wrong. DESIGN.md is present, 577 lines, and is actively referenced by code and reviewed by this spec. No action required. Closing.
