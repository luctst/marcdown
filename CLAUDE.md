# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Git workflow

**Never push to or work directly on `main`/`master`.** Always create a new branch first, even if the user asks otherwise.

Branch naming convention: `<type>/<context>` where:

- **type** follows commitlint standards: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `style`, `perf`, `ci`, `build`
- **context** uses kebab-case (e.g., `feat/add-strikethrough-support`, `fix/ime-restyle-crash`)

Commit messages follow commitlint conventions (`type: subject` in kebab-case).

## Build & run

```bash
# Generate Xcode project (required before building)
xcodegen generate

# Build via command line
xcodebuild -scheme Marcdown -configuration Debug build

# Run
xcodebuild -scheme Marcdown -configuration Debug run

# Open in Xcode
open Marcdown.xcodeproj
```

Requires: macOS 15.0+, Xcode 16.0+, `xcodegen` (`brew install xcodegen`), Swift 6.

## Tests

```bash
# Core tests (title extraction, index rename/delete)
swift test --package-path Packages/MarcdownCore

# Styling tests (attribute application, LineOffsetIndex)
swift test --package-path Packages/MarcdownStyling
```

Tests use Swift Testing (`@Test`, `@Suite`, `#expect`) — not XCTest.

## Architecture

Three local SPM packages under `Packages/` plus the `App/` target, wired via `project.yml` (xcodegen):

- **MarcdownCore** — Note model, disk IO (`actor NoteStore`), file indexing/watching (`actor NotesIndex`). Pure Foundation, no UI.
- **MarcdownStyling** — Markdown parsing via `swift-markdown` (pinned to `branch: "main"` due to `unsafeFlags` in tags). `MarkdownStyler` + `StyleWalker` convert cmark AST to `NSAttributedString` attributes. `LineOffsetIndex` bridges UTF-8 source ranges to UTF-16 `NSRange`.
- **MarcdownEditor** — `NSViewRepresentable` wrapping an `NSTextView` (TextKit 1). Bridges Core and Styling. Skips restyle during IME composition (`hasMarkedText`).
- **App/** — SwiftUI + AppKit shell. Background-only (`LSUIElement`), floating `NSPanel`, global hotkey via `KeyboardShortcuts`.

### Concurrency model

All IO goes through actors (`NoteStore`, `NotesIndex`). UI layer is `@MainActor` with `@Observable` (not `ObservableObject`). Swift 6 strict concurrency is enforced project-wide with warnings-as-errors.

## Key conventions

- **Swift 6 strict concurrency** — `SWIFT_STRICT_CONCURRENCY: complete`, warnings as errors.
- **Minimal dependencies** — only `swift-markdown` and `KeyboardShortcuts`. New deps need strong justification.
- **AppKit for the editor, SwiftUI for chrome** — the styler mutates `NSTextStorage` in-place; this is intentional.
- **`StyleWalker` must remain a struct** — `MarkupWalker` requires `mutating` visit methods.
- **Notes folder** — `~/marcdown/`, plain `.md` files, UTF-8. No sync logic in the app.
