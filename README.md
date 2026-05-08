# Marcdown

Hit `Cmd+Shift+Space` anywhere on macOS. Write Markdown. Done.

A background-only macOS markdown editor. Floating panel, global hotkey, plain `.md` files in `~/marcdown/`. No Electron, no account, no cloud. Native Swift 6, AppKit + SwiftUI.

![Marcdown demo](docs/demo.gif)

[**↓ Download v1.0.0 (DMG, macOS 15+)**](https://github.com/luctst/marcdown/releases/latest)

---

## Why this exists

Raycast Notes was convenient but proprietary. Marcdown gives you:

- **Plain text, local files** — notes live in `~/marcdown/` under your control; sync via iCloud Drive, Dropbox, Syncthing, or just `git`.
- **Live markdown rendering** — as you type `# Heading` or `**bold**`, the text renders in place (WYSIWYG-ish; no formatting hotkeys needed).
- **Markdown tables** — Raycast Notes doesn't render them; Marcdown does.
- **Native macOS** — SwiftUI + AppKit; no Electron, no browser overhead. Fast, low-footprint.
- **Keyboard-first UX** — global hotkey, panel overlay, all controls accessible via chords. No mouse required.

## Status

**Working today** (released in slices):

- Live markdown styling (headings, bold, italic, code blocks, blockquotes, tables, lists)
- Floating panel with global hotkey (Cmd+Shift+Space, customizable)
- Multi-note management (quick switcher, prev/next, 9-item recent history)
- H1-driven auto-rename (Untitled N.md becomes "My Note.md" once you type a level-1 heading)
- Keyboard shortcuts for all common actions (new note, delete, jump to recent, etc.)
- File watcher (external edits or deletes are reflected immediately)

**Deliberately out of scope right now:**

- Sync code — the folder is the seam. Use whatever sync tool you prefer; Marcdown watches for changes.
- UI for configuring note storage path — currently hardcoded to `~/marcdown/`.
- Settings beyond keyboard shortcut rebinding (no themes, font picker, etc. — planned).
- iOS client — macOS only for now.

## Architecture

Marcdown is built as a **macOS 15+ background-only app** in Swift 6 with strict concurrency. The UI layer is SwiftUI + AppKit; the core (model, IO, indexing) is pure Foundation, packaged as SPM libraries.

```
marcdowndev/
├── App/                           # Main app target
│   ├── Sources/
│   │   ├── MarcdownApp.swift      # Entry point (@main, Settings scene)
│   │   ├── AppDelegate.swift      # Background mode, global hotkey registration
│   │   ├── PanelController.swift  # NSPanel lifecycle and toggling
│   │   ├── PanelRootView.swift    # Root SwiftUI view (editor + overlays)
│   │   ├── NotesStore.swift       # @MainActor, @Observable facade
│   │   ├── NoteViewModel.swift    # Per-note editor state, debounced save
│   │   ├── QuickSwitcher.swift    # Fuzzy-search note picker overlay
│   │   ├── SettingsView.swift     # Hotkey rebinder UI
│   │   └── Shortcuts.swift        # Global hotkey name definition
│   └── Resources/
│       ├── Info.plist
│       └── Marcdown.entitlements
├── Packages/
│   ├── MarcdownCore/              # Pure Foundation model & IO
│   │   ├── Sources/MarcdownCore/
│   │   │   ├── Note.swift         # Model (id, body, modifiedAt, title extraction)
│   │   │   ├── NoteStore.swift    # actor: load, save, loadOrCreate disk IO
│   │   │   ├── NoteLocation.swift # Constants (~/marcdown/, scratch.md, etc.)
│   │   │   └── NotesIndex.swift   # actor: file watcher, list, create, delete, rename
│   │   └── Tests/MarcdownCoreTests/
│   │       └── NoteTitleTests.swift
│   ├── MarcdownStyling/           # Markdown → NSAttributedString
│   │   ├── Sources/MarcdownStyling/
│   │   │   ├── MarkdownStyler.swift      # @MainActor API (parse, walk, apply attributes)
│   │   │   ├── StyleWalker.swift         # struct: MarkupWalker impl (mutating)
│   │   │   ├── LineOffsetIndex.swift     # UTF-8 column → UTF-16 NSRange converter
│   │   │   └── StylingTheme.swift        # Semantic NSColors (heading, bold, code, etc.)
│   │   └── Tests/MarcdownStylingTests/
│   │       ├── MarkdownStylerTests.swift
│   │       └── LineOffsetIndexTests.swift
│   └── MarcdownEditor/            # NSTextView + SwiftUI glue
│       └── Sources/MarcdownEditor/
│           ├── NoteEditorView.swift    # NSViewRepresentable (TextKit 1 stack)
│           └── EditorTextView.swift    # NSTextView subclass, IME-aware restyle
└── project.yml                    # xcodegen config
```

### Module breakdown

| Module              | Role                                     | Tech                                   | Key points                                                                                                                                                            |
| ------------------- | ---------------------------------------- | -------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **App**             | UI shell, global hotkey, panel lifecycle | SwiftUI, AppKit, NSApplication         | `@MainActor` for AppKit; `@Observable` view models; Settings scene only (no WindowGroup)                                                                              |
| **MarcdownCore**    | Model, disk IO, file indexing            | Swift 6 strict concurrency, Foundation | Two actors: `NoteStore` (single-file IO), `NotesIndex` (watcher + list); pure data.                                                                                   |
| **MarcdownStyling** | Markdown parser & renderer               | `swift-markdown`, Foundation           | Converts cmark source ranges (UTF-8 line + column) to `NSAttributedString` via `LineOffsetIndex` (UTF-16 conversion). Idempotent restyle on keystroke.                |
| **MarcdownEditor**  | Editor surface                           | TextKit 1, NSTextView, SwiftUI         | Hybrid: AppKit backing for the text surface (so styler can mutate attributes in-place without cursor jumps), SwiftUI container. Skips restyle during IME composition. |

### Concurrency model

- **`actor NoteStore`** — serializes disk reads/writes to a single file.
- **`actor NotesIndex`** — owns a `DispatchSourceFileSystemObject` watcher on `~/marcdown/`, publishes snapshots via an async stream.
- **`@MainActor` UI layer** — all AppKit and SwiftUI code. `NotesStore` (the facade) is `@MainActor @Observable`; `NoteViewModel` is `@MainActor`.
- **`@Observable`** — Observation framework, not ObservableObject; simpler, lower-overhead.

### Styling pipeline

1. User types in `NoteEditorView` (NSTextView).
2. `NoteViewModel.text` updates; 300ms debounce before save.
3. Styler runs on keystroke: `MarkdownStyler.restyle(storage:source:)` parses the source with `swift-markdown`, walks the AST with a `StyleWalker`, and mutates `NSTextStorage` attributes in-place.
4. `LineOffsetIndex` bridges `swift-markdown`'s UTF-8 source ranges to NSAttributedString's UTF-16 offsets.
5. Result: live preview, no editor state reset, no cursor jump.

**Caveat:** The styler always sets a baseline before walking, so layered ad-hoc attributes (find highlights, link-press color) get wiped on the next keystroke. This is acceptable for v0 and will be revisited when selection overlays land.

## Requirements

- **macOS 15.0+** (Sequoia or later; `LSUIElement = true` requires modern APIs)
- **Xcode 16.0+** (Swift 6, command line tools)
- **[xcodegen](https://github.com/yonaskolb/XcodeGen)** — `brew install xcodegen`
- **Swift 6** (bundled with Xcode 16)

## Build & run

### Via Xcode

```bash
cd /Users/luctst/marcdowndev
xcodegen generate
open Marcdown.xcodeproj
```

Then press **▶** in Xcode to build and run. The app stays out of the Dock (background-only). Press **Cmd+Shift+Space** to summon the panel.

### Command line

```bash
cd /Users/luctst/marcdowndev
xcodegen generate
xcodebuild -scheme Marcdown -configuration Debug build
xcodebuild -scheme Marcdown -configuration Debug run
```

On first run, a scratch note (`Untitled 1.md`) is created in `~/marcdown/`. Open it or create a new one with **Cmd+N**.

## Tests

```bash
# MarcdownCore tests (Note title extraction, NotesIndex rename/delete collision handling)
swift test --package-path Packages/MarcdownCore

# MarcdownStyling tests (attribute application, LineOffsetIndex UTF-8↔UTF-16 conversion)
swift test --package-path Packages/MarcdownStyling
```

### Test coverage

- **NoteTitleTests** — H1 extraction, fallback to filename, trimming, collision detection.
- **MarkdownStylerTests** — heading/bold/italic/code/blockquote attribute application; idempotent restyle after edit.
- **LineOffsetIndexTests** — UTF-8 multi-byte column conversion, out-of-bounds clamping, empty source handling.

## CI / Release

GitHub Actions runs on every PR and on tag pushes.

### Continuous Integration (`.github/workflows/ci.yml`)

Triggers on PRs into `main` and pushes to `main`. Two jobs run in parallel:

- **`lint`** — hard-fails the PR on any violation. Runs `swift-format lint --strict` against `.swift-format`, `actionlint` on the workflow files, and `commitlint` against the conventional-commit style enforced in `commitlint.config.js`.
- **`test-packages`** — matrix over `MarcdownCore` and `MarcdownStyling`. Each leg runs `swift test --package-path Packages/<name> --parallel`. `MarcdownEditor` has no test target and is excluded; `App/Tests/PanelControllerTests` requires the full app build and is currently exercised only at release time.

To check formatting locally before pushing:

```bash
xcrun swift-format lint --strict --recursive --configuration .swift-format App/ Packages/MarcdownCore/Sources Packages/MarcdownCore/Tests Packages/MarcdownStyling/Sources Packages/MarcdownStyling/Tests Packages/MarcdownEditor/Sources

# Or auto-fix:
xcrun swift-format format --in-place --recursive --configuration .swift-format App/ Packages/...
```

### Releasing (`.github/workflows/release.yml`)

Pushing a `vX.Y.Z` tag triggers the release pipeline:

```bash
git tag v0.2.0
git push origin v0.2.0
```

The workflow then:

1. Reads the version from the tag (no manual `Info.plist` edit).
2. Imports the Developer ID certificate into a temporary keychain.
3. Archives, exports, and signs a Release build.
4. Notarizes via `xcrun notarytool` and staples the `.app`.
5. Builds a DMG, signs and staples it, and computes its SHA-256.
6. Publishes a GitHub Release with the DMG and `.sha256` attached. Pre-release tags (e.g. `v0.2.0-rc1`) are auto-flagged as pre-releases.

### Required secrets

Configure these in **Settings → Secrets and variables → Actions**:

| Secret | What it is |
| --- | --- |
| `DEVELOPER_ID_CERT_P12` | Base64 of the `.p12` exported from Keychain Access. Generate with `base64 -i cert.p12 \| pbcopy`. |
| `DEVELOPER_ID_CERT_PASSWORD` | Password used when exporting the `.p12`. |
| `APPLE_ID` | Apple ID email associated with the Developer Program account. |
| `APPLE_TEAM_ID` | 10-character team ID from [developer.apple.com → Membership](https://developer.apple.com/account/#!/membership). |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password from [appleid.apple.com → Sign-In & Security](https://appleid.apple.com). |
| `SLACK_WEBHOOK_URL` | Incoming webhook for the `#marcdown-ci` Slack channel. Used to notify on workflow failures. |

If any CI or release job fails, a summary message is posted to `#marcdown-ci` with a link to the failed run.

## Keyboard shortcuts

### Global (always available)

| Shortcut            | Action                  | Customizable       |
| ------------------- | ----------------------- | ------------------ |
| **Cmd+Shift+Space** | Toggle panel visibility | Yes (SettingsView) |

### In-panel (when editor has focus)

| Shortcut               | Action                                       |
| ---------------------- | -------------------------------------------- |
| **Cmd+N**              | New note                                     |
| **Cmd+P**              | Quick switcher (fuzzy search)                |
| **Cmd+Shift+⌫**        | Delete current note (with confirmation)      |
| **Cmd+Shift+[**        | Previous note                                |
| **Cmd+Shift+]**        | Next note                                    |
| **Cmd+1** to **Cmd+9** | Jump to recent (1 = most recent, 9 = oldest) |
| **Cmd+,**              | Settings (hotkey rebinder)                   |
| **Esc**                | Hide panel                                   |

## Notes folder

### Location & format

- **Default path:** `~/marcdown/`
- **File format:** Plain `.md` (CommonMark-ish with tables)
- **Encoding:** UTF-8

### Auto-rename

New notes are created as `Untitled N.md` (N = 1, 2, 3, ...). Once you type a level-1 heading (e.g., `# My Project`), the file is automatically renamed to `My-Project.md` (slugified). If a file with that name already exists, the app appends `-2`, `-3`, etc. until a unique name is found.

Auto-rename only happens once per note. After that, the user controls the filename.

### Delete & trash

`Cmd+Shift+⌫` moves the current note to the Trash via `FileManager.trashItem(_:resultingItemURL:)`. Files are never permanently deleted — you can restore them from Finder.

### Syncing

The folder is the seam. To sync with iCloud Drive:

```bash
# Close the app first
mv ~/marcdown ~/Library/Mobile\ Documents/com~apple~CloudDocs/marcdown
ln -s ~/Library/Mobile\ Documents/com~apple~CloudDocs/marcdown ~/marcdown
# Reopen the app
```

The symlink is transparent to Marcdown — it continues to read/write through the symlink as if the folder were local.

You can do the same with Dropbox, Syncthing, or any other sync tool. The app just watches the folder; it doesn't care how changes arrive.

## Conventions

- **Swift 6 strict concurrency** — `SWIFT_STRICT_CONCURRENCY: complete`, warnings as errors. No unsafe concurrency.
- **Minimal dependencies** — only `swift-markdown` (parsing) and `KeyboardShortcuts` (Sindre Sorhus, global hotkey). Adding a new dependency requires strong justification.
- **AppKit/SwiftUI hybrid** — SwiftUI for chrome and overlays (Settings, quick switcher), AppKit (`TextKit 1`) for the editor surface. This keeps the styler simple (can mutate `NSTextStorage` in-place) and the editor responsive.
- **Actors for IO** — all filesystem calls (read, write, watch, delete) happen inside `NoteStore` or `NotesIndex` actors. No unprincipled `Task` spawning.
- **@Observable over ObservableObject** — cleaner, more efficient.
- **Swift Testing** — new tests use `@Test`, `@Suite`, `#expect` (not XCTest).

## Known constraints & gotchas

### swift-markdown branch pin

`swift-markdown` is pinned to `branch: "main"` in `Packages/MarcdownStyling/Package.swift`. Reason: all 0.x releases ship with a `unsafeFlags` declaration for Windows-only functionality, which SPM rejects for versioned consumers on macOS. This should be swapped back to a version tag once Apple ships a clean release.

### StyleWalker is a struct

`StyleWalker` conforms to `MarkupWalker`, which requires `mutating` visit methods. Therefore, `StyleWalker` must be a `struct`, not a `class`. This is fine — it's a lightweight visitor with no state.

### Restyle wipes layered attributes

The styler always applies a baseline set of attributes before walking the AST. Any ad-hoc attributes (e.g., find-and-replace highlights, link press color) are lost on the next keystroke. This is acceptable for v0. Once selection overlays and more sophisticated styling are planned, we'll revisit a multi-pass or differential restyle approach.

### IME composition safety

`NoteEditorView` checks `textView.hasMarkedText` before restyling. This prevents eating in-progress IME input (e.g., Japanese composition). Restyle resumes once composition is complete.

## Project layout

| Directory                     | Purpose                                                                                                                                      |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| **App/**                      | Main macOS application target (SwiftUI entry, AppKit panel, UI view models).                                                                 |
| **Packages/MarcdownCore/**    | SPM package: Note model, disk IO (NoteStore actor), file indexing (NotesIndex actor). Pure Foundation, no UI deps.                           |
| **Packages/MarcdownStyling/** | SPM package: Markdown parser wrapper, syntax highlighter (StyleWalker), UTF-8↔UTF-16 converter (LineOffsetIndex). Depends on swift-markdown. |
| **Packages/MarcdownEditor/**  | SPM package: TextKit 1 wrapper (NoteEditorView, EditorTextView). Bridges Styling and Core.                                                   |
| **project.yml**               | xcodegen config (replaces .pbxproj). Defines targets, packages, schemes, build settings.                                                     |

## Next steps

If you want to extend Marcdown:

- **Add a new markdown element (e.g., strikethrough)** — Update `StyleWalker` to pattern-match on the cmark node type, apply attributes via `StylingTheme`, and write a test in `MarkdownStylerTests.swift`.
- **Add a settings option** — Extend `SettingsView` with a new control, persist to `UserDefaults`, and inject into the relevant module (e.g., `StylingTheme` for colors).
- **Implement sync** — Marcdown doesn't care how files appear in `~/marcdown/`. You can add a sync library (e.g., iCloud API, S3 sync) without touching the core.
- **Profile or optimize** — Use Xcode's Instruments (Time Profiler, System Trace) to identify hotspots. The styler runs on every keystroke, so it's a good first target.

---

Built with Swift 6, AppKit, and SwiftUI. Repo structure follows a workspace pattern: the app depends on three local SPM packages for clean separation of concerns.
