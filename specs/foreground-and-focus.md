---
status: draft
branch: feat/foreground-and-focus
---

# Spec: Persistent Panel + Editor Focus Restore

## Objective

Marcdown is a persistent capture surface (Raycast Notes / Apple quick-note category), not a launcher (Spotlight / Raycast launcher category). Two behaviors currently violate that model:

1. The panel hides when the user clicks another app (`windowDidResignKey → hide`). This breaks the core flow of "draft → tab to Safari to grab a URL → tab back, keep drafting."
2. When the command palette closes (ESC, scrim tap, action callback), keystroke focus does not return to the markdown editor. The user has to click the editor to keep typing.

This spec covers a single PR that fixes both, plus the coupled changes those fixes require (hotkey-toggle state, ESC discoverability, window-level audit).

### Success criteria

- Pressing the global hotkey shows the panel and gives the editor first-responder.
- Clicking another app does **not** hide the panel. The panel stays visible at floating level. The editor loses key, the other app gets key.
- Pressing the global hotkey while the panel is visible-but-not-key brings it back to key (does not hide).
- Pressing the global hotkey while the panel is key hides the panel and restores the previously-active app.
- Pressing ESC while the panel is key (and no overlay is active) hides the panel and restores the previously-active app.
- Opening the command palette → pressing ESC → cursor blinks in the editor, typing inserts characters immediately, no click required. Same for scrim-tap dismiss and action-callback dismiss.
- Pressing ESC inside the palette's export submenu pops back to the palette root (does not collapse the overlay).
- A small "esc to close" hint is visible in the footer whenever the panel is key and no overlay is active.
- Panel does not aggressively float above full-screen Spaces or system modals (validated empirically before merge).

## Tech stack

- macOS 15.0+, Swift 6, Xcode 16+, AppKit + SwiftUI.
- No new dependencies.
- Existing: `KeyboardShortcuts` (global hotkey), `swift-markdown`.

## Commands

```
xcodegen generate
xcodebuild -scheme Marcdown -configuration Debug build
swift test --package-path Packages/MarcdownCore
swift test --package-path Packages/MarcdownStyling
```

## Affected files

- `App/Sources/PanelController.swift` — remove resign-key hide; flip `toggle()` to use `isKeyWindow` instead of `isVisible`; possibly adjust `panel.level`.
- `App/Sources/PanelRootView.swift` — centralize focus restore on every overlay dismissal path (ESC, scrim tap, `onDismiss`, action callbacks).
- `App/Sources/CommandPalette.swift` — verify ESC sub-mode pop ordering vs `EscapeKeyMonitor` (palette internal `.onKeyPress(.escape)` at line 280 must fire before the local NSEvent monitor consumes the keystroke; if not, sub-mode ESC must be delegated through `dismissActiveOverlay` with a sub-mode-aware contract).
- `App/Sources/FooterBar.swift` — add "esc to close" hint.
- `App/Sources/MarcdownPanel` (in `PanelController.swift`) — `cancelOperation` already does the right thing, no change unless the level audit forces one.

## Implementation plan

### 1. Remove resign-key hide

In `PanelController.swift`, delete the body of `windowDidResignKey` (or remove the method) so click-away leaves the panel visible. Keep `previouslyActiveApp` capture in `show()` — it is still used by ESC dismiss and hotkey-toggle dismiss.

### 2. Hotkey toggle: visible → key

In `PanelController.toggle()`, replace `if panel.isVisible` with `if panel.isKeyWindow`. New behavior:

- Panel hidden → `show()`.
- Panel visible but not key (user is in another app) → `NSApp.activate(ignoringOtherApps: true)` + `panel.makeKeyAndOrderFront(nil)`. Refresh `previouslyActiveApp` so the next ESC restores the correct app.
- Panel key → `hide(restoreFocus: true)`.

Extract the "bring to key" branch as a small helper to keep `show()` and the new branch from drifting.

### 3. Editor focus restore on overlay dismiss

In `PanelRootView.swift`, route every overlay dismissal through `dismissActiveOverlay()`. Today it is only invoked from the `EscapeKeyMonitor`; the scrim `onTapGesture` and the inline `onDismiss: { activeOverlay = .none }` closures (palette, switcher, export action) all bypass it. Replace those direct mutations with calls to `dismissActiveOverlay()`.

Then, inside `dismissActiveOverlay`, after the state mutation, post a notification (or call a focus helper) that `MarcdownEditor` listens to and which calls `window?.makeFirstResponder(textView)`. Notification name suggestion: `.marcdownEditorShouldFocus`.

### 4. Palette sub-mode ESC ordering

`CommandPalette.swift:280-293` handles ESC to pop sub-modes (e.g. export submenu → palette root). The local `EscapeKeyMonitor` in `PanelRootView.swift:174` is installed via `NSEvent.addLocalMonitorForEvents` and returns `nil` (consumes the event) whenever any overlay is active. Verify which fires first; if the monitor wins, the sub-mode pop is broken.

Fix path if needed: the monitor calls a closure that asks the palette "can you handle ESC internally?" before falling back to `dismissActiveOverlay()`. Concrete shape: lift sub-mode state into `PanelRootView` or expose a binding; the monitor's closure checks "if palette has a sub-mode to pop, pop it; else dismiss overlay."

### 5. ESC discoverability hint

In `FooterBar.swift`, add a leading label `Text("esc to close")` mirroring the existing character-count style (font size 11, tertiary). Visible only when the panel is key and no overlay is active — the parent passes a `showEscHint: Bool` prop derived from `activeOverlay == .none` and panel key state.

### 6. Window-level audit (pre-merge gate)

Manual validation against:

- Full-screen Safari → summon panel → does it appear above? Should: yes (current `.floating` + `.fullScreenAuxiliary`).
- A standard app → click another app → panel stays visible at floating level, not above the system menu bar / not stealing focus.
- A native modal sheet (e.g. Save dialog) → panel must not float above it.

If `.floating` is too aggressive, drop to `.normal` + `.canJoinAllSpaces` while not-key, restore `.floating` while key. Do not implement this preemptively — only if validation shows aggression.

## Testing strategy

- **Unit-testable**: pure helpers in `MarcdownCore` / `MarcdownStyling` only. The behaviors in this spec are AppKit-bound; do not invent abstractions to make them unit-testable.
- **Manual QA checklist** (must pass before merge):
  1. Hotkey shows panel; cursor blinks in editor; typing inserts text.
  2. Click Safari; panel stays visible; Safari is key; menu bar shows Safari.
  3. Hotkey again; panel becomes key; cursor in editor; typing works.
  4. ESC; panel hides; Safari is key.
  5. Hotkey; Cmd-K (palette); ESC; cursor in editor; typing works.
  6. Hotkey; Cmd-K; click scrim; cursor in editor; typing works.
  7. Hotkey; Cmd-K; navigate to Export submenu; ESC pops back to palette root (does not close overlay).
  8. Hotkey; Cmd-K; second ESC closes palette root; cursor in editor.
  9. Quick switcher dismiss paths (ESC, scrim, open) all return focus to editor.
  10. Footer shows "esc to close" only when panel is key and no overlay is active.
  11. Full-screen Safari + summon → panel visible above (acceptable).
  12. Save dialog open in another app + summon → panel does not block the modal (acceptable).

## Boundaries

**Always:**
- Run `xcodebuild` and the two `swift test` package suites before opening the PR.
- Branch name `feat/foreground-and-focus`.
- Commit messages follow commitlint (`feat(panel): …`, `fix(palette): …`).

**Ask first:**
- Any change to `panel.level` or `collectionBehavior` beyond what the audit dictates.
- Adding a new dependency.
- Persisting any new user preference (e.g. an "auto-hide" toggle — explicitly out of scope per the PM review).

**Never:**
- Reintroduce a "click-outside hides panel" code path under any flag or setting in this PR.
- Add a pin / auto-hide toggle (deferred indefinitely).
- Touch auto-save logic — already in product, not in scope.
- Skip the manual QA checklist.

## Out of scope (do not bundle)

- Pin / auto-hide settings toggle.
- Auto-save changes (already shipped).
- Any palette UX beyond the sub-mode ESC ordering fix.
- Any visual redesign of the footer.

## Open questions

1. **Palette sub-mode ESC ordering** — concretely, does `CommandPalette`'s `.onKeyPress(.escape)` (SwiftUI) fire before the AppKit `NSEvent.addLocalMonitorForEvents` monitor? If yes, no plumbing change needed in step 4. If no, we need the binding-based handoff. Resolve by adding a temporary `print` in both handlers and observing order, then deleting the prints.
2. **Focus-restore mechanism** — is a notification (`.marcdownEditorShouldFocus`) cleaner than threading a callback through the editor's `NSViewRepresentable`? The editor already listens for `.marcdownPanelDidHide`; mirroring that pattern is consistent. Default to notification.
3. **`previouslyActiveApp` re-capture on hotkey-bring-to-key** — when the user is in Safari and hits the hotkey to bring Marcdown back to key, do we overwrite `previouslyActiveApp` with Safari (so the next ESC restores Safari)? Default: yes. Confirm this matches the user's mental model.
