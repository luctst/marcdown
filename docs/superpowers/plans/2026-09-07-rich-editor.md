# Rich Markdown Editor (Bear-style) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Plan file location:** plan mode only allows writing this file. Step 0 of execution: copy it to `docs/superpowers/plans/2026-09-07-rich-editor.md` and commit it with the first task (`docs: rich editor implementation plan`).

**Goal:** Make Marcdown's editor feel like Bear/Notion: rendered-looking markdown (airy line height, hanging list indents, quote bar, drawn horizontal rules, `==highlight==`, fence-less code blocks with a language badge) plus keyboard-first formatting (⌘B/I/E…, heading/list/task/quote toggles, multi-line indent, wrap-selection-on-type, paste-URL-as-link, `/` block menu), without ever altering the markdown on disk.

**Architecture:** Every visual change is an attribute written by `MarkdownStyler`/`StyleWalker` and drawn by `CheckboxIconLayoutManager` (never a character edit). Every editing command is a pure `TextEditOutcome`-returning function in `MarcdownStyling` (AppKit-free, unit-tested) applied by one `Coordinator.apply(_:undoName:in:)` in `MarcdownEditor`. ⌘-chords are caught in the editor's own `performKeyEquivalent`; the App reaches the editor through a payload-carrying `NotificationCenter` name, the same pattern as the existing focus-restore notification.

**Tech Stack:** Swift 6 (strict concurrency, warnings as errors), AppKit TextKit 1 (`NSTextView`/`NSLayoutManager`), SwiftUI chrome, `swift-markdown` (branch `main`), Swift Testing.

**Spec:** This document is the spec. Gap inventory and constraints were derived from `README.md`, `DESIGN.md`, `specs/*.md`, `.specs/*.md` and the source on 2026-09-07 (branch `feat/marcdown-render`).

## Context

The editor already conceals syntax (`# `, `**`, `[](…)`, list markers), continues lists/quotes on Enter, indents with Tab, and draws checkboxes/bullets/code containers. What still reads as "old school": raw `>` and `---` and ``` fences stay visible, wrapped list lines snap back to the left margin, line height is 1.0, headings render in SF while body is Avenir Next, and there is not a single formatting shortcut (`NoteEditorView.swift:23-24` declares this as a design choice). The ⌘K palette's Markdown rows are documentation only. This plan closes those gaps in two phases that each ship working software; images, real tables, syntax highlighting and a floating selection toolbar are explicitly deferred to a follow-up plan.

User decisions already taken: ⌘⌥1–6 for headings (⌘1–9 stays "jump to recent"); the `/` menu reuses the ⌘K palette (new `.blockInsert` sub-mode) instead of a caret-anchored popover.

## Global Constraints

- Swift 6, `SWIFT_STRICT_CONCURRENCY: complete`, warnings as errors, macOS 15.0+, Xcode 16+.
- No new SPM dependencies (only `swift-markdown` and `KeyboardShortcuts`).
- The styler never edits characters, only attributes (`MarkdownStyler.swift:7-9`; locked by `ConcealmentTests.restylePreservesEveryCharacter`).
- Pure helpers in `MarcdownStyling` that scan/edit text are Foundation-only `enum` + `static func`, UTF-16 `[UInt16]` throughout, return `.noOp` on ambiguous shapes (`specs/list-marker-concealment.md` style contract). `MarkdownStyler`/`StyleWalker`/`StylingTheme` may import AppKit.
- Never `.null`-conceal a run that is the only content of a line (collapses the line, drags the caret up). Clear-paint + monospaced font instead (`ConcealmentTests.emptyHeadingWithTrailingSpaceIsClearPaintedMonospaced`).
- `StyleWalker` stays a `struct`.
- Never reintroduce click-outside-hides-panel; never call `controller.hide` from an overlay ESC handler; ⌘K/⌘P stay live while an overlay is open; every other chrome shortcut is disabled while an overlay is open.
- Copy: sentence case, real glyphs (`⌘⇧⌥⌃⏎⌫⎋`), no emoji anywhere in the repo, SF Symbols only.
- swift-format: 4-space indent, 120 columns, `///` doc comments, no block comments. Run `xcrun swift-format lint --strict --recursive --configuration .swift-format <paths>` before each commit.
- Tests: Swift Testing (`@Suite`, `@Test`, `#expect`), `@MainActor` on suites that touch `NSTextStorage`/`NSTextView`.
- Commits: `type: kebab subject`, types from `feat fix refactor test docs chore style perf ci build`. Work stays on the current branch `feat/marcdown-render`; never commit to `main`.
- Test commands: `swift test --package-path Packages/MarcdownStyling`, `swift test --package-path Packages/MarcdownEditor`, `swift test --package-path Packages/MarcdownCore`. App tests: `xcodegen generate && xcodebuild -scheme Marcdown -destination 'platform=macOS' test`.

---

## File Structure

**MarcdownStyling (pure logic + attribute writers)**
- Modify `Sources/MarcdownStyling/StylingTheme.swift` — add `highlight`, `rule`, `lineHeightMultiple` tokens.
- Create `Sources/MarcdownStyling/ParagraphStyling.swift` — copy-on-write paragraph-style mutation helper (keeps line height and earlier indents intact).
- Modify `Sources/MarcdownStyling/MarkdownStyler.swift` — base paragraph style, `forEachLine` helper, hanging indent, highlight pass, thematic-break skip in list pass, focus-reveal strips new overlay tags.
- Modify `Sources/MarcdownStyling/StyleWalker.swift` — heading font/spacing, blockquote clear-paint + tag, thematic break tag, fence clear-paint + language tag.
- Modify `Sources/MarcdownStyling/ConcealmentAttribute.swift` — new keys `.marcdownBlockquote`, `.marcdownThematicBreak`, `.marcdownCodeLanguage`.
- Create `Sources/MarcdownStyling/HighlightScanner.swift` — `==text==` span scanner.
- Modify `Sources/MarcdownStyling/HTMLExporter.swift` — `<mark>` pre-pass + CSS.
- Create `Sources/MarcdownStyling/TextEditOutcome.swift` — shared outcome enum for all editing commands.
- Create `Sources/MarcdownStyling/InlineFormat.swift` — toggle `**`/`*`/`` ` ``/`~~`/`==`, link insertion, URL detection.
- Create `Sources/MarcdownStyling/BlockFormat.swift` — heading/list/task/quote toggles, code block + divider insertion over selected lines.
- Modify `Sources/MarcdownStyling/ListIndentation.swift` — selection-scoped indent/outdent.
- Create `Sources/MarcdownStyling/SelectionWrap.swift` — typed delimiter wraps selection.

**MarcdownEditor (AppKit glue)**
- Modify `Sources/MarcdownEditor/NoteEditorView.swift` — `apply`, `perform`, `performKeyEquivalent`, delegate refactor, restyle guard, shift-arrow.
- Create `Sources/MarcdownEditor/EditorCommand.swift` — public command enum + chord table + notification names.
- Modify `Sources/MarcdownEditor/CheckboxIconLayoutManager.swift` — baseline-anchored icons, quote bar, rule, language badge.
- Create `Tests/MarcdownEditorTests/EditorHarness.swift` — shared TextKit harness for new command tests.

**App**
- Modify `App/Sources/PanelRootView.swift` — palette rows become commands, slash notification → `.blockInsert`.
- Modify `App/Sources/CommandPalette.swift` — `PaletteSubMode.blockInsert`.
- Modify `App/Tests/CommandPaletteSectionTests.swift`, `CommandPaletteActionContractTests.swift`, `CommandPaletteSubModeTests.swift`.

**Repo**
- Modify `.github/workflows/ci.yml` — MarcdownEditor in test matrix and lint paths.
- Modify `README.md`, `DESIGN.md`, `CLAUDE.md` — shortcuts table, editor font truth, test commands.

---

# Phase 1 — Rendering polish

### Task 1: Typography baseline (line height, heading font family and spacing, baseline-anchored icons)

**Files:**
- Modify: `Packages/MarcdownStyling/Sources/MarcdownStyling/StylingTheme.swift`
- Create: `Packages/MarcdownStyling/Sources/MarcdownStyling/ParagraphStyling.swift`
- Modify: `Packages/MarcdownStyling/Sources/MarcdownStyling/MarkdownStyler.swift` (`baseAttributes` ~409, `applyParagraphSpacing` ~394)
- Modify: `Packages/MarcdownStyling/Sources/MarcdownStyling/StyleWalker.swift` (`visitHeading` ~34-53, `visitBlockQuote` ~155, `visitCodeBlock` ~176)
- Modify: `Packages/MarcdownEditor/Sources/MarcdownEditor/NoteEditorView.swift` (`makeNSView` ~80, Coordinator ~126)
- Modify: `Packages/MarcdownEditor/Sources/MarcdownEditor/CheckboxIconLayoutManager.swift` (`drawIcon` ~89-122, `drawBullet` ~190-218)
- Test: `Packages/MarcdownStyling/Tests/MarcdownStylingTests/TypographyTests.swift` (create)

**Interfaces:**
- Produces: `StylingTheme.lineHeightMultiple: CGFloat` (default 1.2), `StylingTheme.highlight: NSColor`, `StylingTheme.rule: NSColor`; `MarkdownStyler.baseParagraphStyle: NSParagraphStyle` (public); `enum ParagraphStyling { static func mutate(in storage: NSTextStorage, range: NSRange, _ body: (NSMutableParagraphStyle) -> Void) }` (internal to MarcdownStyling); `Coordinator.baseParagraphStyle: NSParagraphStyle` (internal to MarcdownEditor).
- Later tasks call `ParagraphStyling.mutate` for every paragraph-style write.

- [ ] **Step 1: Write the failing tests**

```swift
// Packages/MarcdownStyling/Tests/MarcdownStylingTests/TypographyTests.swift
import AppKit
import Testing

@testable import MarcdownStyling

@MainActor
@Suite("Typography baseline")
struct TypographyTests {
    private func styledStorage(_ source: String) -> NSTextStorage {
        let styler = MarkdownStyler()
        let storage = NSTextStorage(string: source)
        styler.restyle(storage: storage, source: source)
        return storage
    }

    private func paragraphStyle(_ storage: NSTextStorage, at offset: Int) -> NSParagraphStyle? {
        storage.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle
    }

    @Test func bodyTextCarriesThemeLineHeight() {
        let storage = styledStorage("hello")
        #expect(paragraphStyle(storage, at: 0)?.lineHeightMultiple == StylingTheme.system.lineHeightMultiple)
        #expect(MarkdownStyler().baseParagraphStyle.lineHeightMultiple == 1.2)
    }

    @Test func listLineKeepsLineHeightAfterListPass() {
        let storage = styledStorage("- foo")
        #expect(paragraphStyle(storage, at: 3)?.lineHeightMultiple == StylingTheme.system.lineHeightMultiple)
        #expect(paragraphStyle(storage, at: 3)?.paragraphSpacingBefore == 4)
    }

    @Test func codeBlockKeepsLineHeight() {
        let storage = styledStorage("```\nlet x = 1\n```")
        #expect(paragraphStyle(storage, at: 5)?.lineHeightMultiple == StylingTheme.system.lineHeightMultiple)
        #expect(paragraphStyle(storage, at: 5)?.headIndent == 14)
    }

    @Test func headingUsesBaseFontFamilyInBold() {
        let storage = styledStorage("# Title")
        let font = storage.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        #expect(font?.familyName == NSFont(name: "AvenirNext-Regular", size: 15)?.familyName)
        #expect(NSFontManager.shared.traits(of: font ?? .systemFont(ofSize: 15)).contains(.boldFontMask))
        #expect(font?.pointSize == 25)
    }

    @Test func headingsGetSpaceAbove() {
        let h1 = styledStorage("# One")
        let h3 = styledStorage("### Three")
        #expect(paragraphStyle(h1, at: 2)?.paragraphSpacingBefore == 16)
        #expect(paragraphStyle(h3, at: 4)?.paragraphSpacingBefore == 8)
        #expect(paragraphStyle(h1, at: 2)?.paragraphSpacing == 4)
        #expect(paragraphStyle(h1, at: 2)?.lineHeightMultiple == StylingTheme.system.lineHeightMultiple)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path Packages/MarcdownStyling --filter TypographyTests`
Expected: FAIL — `lineHeightMultiple` / `baseParagraphStyle` not found (compile error is the expected failure).

- [ ] **Step 3: Add the theme tokens**

In `StylingTheme.swift` add three stored properties and default init parameters:

```swift
    public var quoteBar: NSColor
    /// Background painted behind `==highlighted==` text.
    public var highlight: NSColor
    /// Horizontal rule drawn in place of `---`.
    public var rule: NSColor
    /// Multiplier applied to every line box. 1.2 is the Bear-like "airy" default.
    public var lineHeightMultiple: CGFloat

    public init(
        body: NSColor,
        dim: NSColor,
        accent: NSColor,
        codeBackground: NSColor,
        codeBlockBackground: NSColor,
        quoteBar: NSColor,
        highlight: NSColor = NSColor.systemYellow.withAlphaComponent(0.35),
        rule: NSColor = .separatorColor,
        lineHeightMultiple: CGFloat = 1.2
    ) {
        self.body = body
        self.dim = dim
        self.accent = accent
        self.codeBackground = codeBackground
        self.codeBlockBackground = codeBlockBackground
        self.quoteBar = quoteBar
        self.highlight = highlight
        self.rule = rule
        self.lineHeightMultiple = lineHeightMultiple
    }
```

- [ ] **Step 4: Create the copy-on-write paragraph helper**

```swift
// Packages/MarcdownStyling/Sources/MarcdownStyling/ParagraphStyling.swift
import AppKit

/// Every paragraph-style write in the pipeline goes through here so the
/// theme line height (set by the base pass) and any indent an earlier pass
/// wrote (quote → list → heading) survive the later pass instead of being
/// clobbered by a fresh `NSMutableParagraphStyle()`.
enum ParagraphStyling {
    /// Mutates a copy of the style found at `range.location` and applies it
    /// over `range`. The base pass in `MarkdownStyler.restyle` guarantees a
    /// style is present; the fallback is defensive only.
    static func mutate(
        in storage: NSTextStorage,
        range: NSRange,
        _ body: (NSMutableParagraphStyle) -> Void
    ) {
        guard range.length > 0, range.location < storage.length else { return }
        let existing = storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
        let style = (existing?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        body(style)
        storage.addAttribute(.paragraphStyle, value: style, range: range)
    }
}
```

- [ ] **Step 5: Base paragraph style in `MarkdownStyler`**

Replace `baseAttributes` and `applyParagraphSpacing`:

```swift
    /// Paragraph style every line starts from. Public so the editor can seed
    /// `NSTextView.defaultParagraphStyle`/`typingAttributes` and the empty
    /// document's caret has the same height as typed text.
    public var baseParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = theme.lineHeightMultiple
        return style
    }

    private var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: baseFont,
            .foregroundColor: theme.body,
            .paragraphStyle: baseParagraphStyle,
        ]
    }

    private func applyParagraphSpacing(
        storage: NSTextStorage,
        lineStart: Int,
        lineLength: Int
    ) {
        let storageLength = storage.length
        let upper = min(lineStart + lineLength, storageLength)
        let lower = min(lineStart, storageLength)
        guard upper > lower else { return }
        ParagraphStyling.mutate(in: storage, range: NSRange(location: lower, length: upper - lower)) { style in
            style.paragraphSpacingBefore = 4
        }
    }
```

- [ ] **Step 6: `StyleWalker` — heading font from the base family, heading spacing, copy-on-write for quote and code block**

In `visitHeading` replace the font lines (`let size = …` through `addAttributes([.font: font], range: range)`) with:

```swift
        addAttributes([.font: headingFont(for: heading.level)], range: range)
        ParagraphStyling.mutate(in: storage, range: clampedToStorage(range)) { style in
            style.paragraphSpacingBefore = headingSpacingBefore(for: heading.level)
            style.paragraphSpacing = 4
        }
```

Add to the helpers section:

```swift
    /// Headings share the body font family (Avenir Next by default) at the
    /// theme scale, bolded. Falling back to the system font here is what made
    /// headings look pasted in from another app.
    private func headingFont(for level: Int) -> NSFont {
        let manager = NSFontManager.shared
        let sized = manager.convert(baseFont, toSize: headingSize(for: level))
        return manager.convert(sized, toHaveTrait: .boldFontMask)
    }

    private func headingSpacingBefore(for level: Int) -> CGFloat {
        switch level {
        case 1: return 16
        case 2: return 12
        case 3: return 8
        default: return 6
        }
    }
```

In `visitBlockQuote` replace the `NSMutableParagraphStyle()` block with (this is rewritten again in Task 3; keep the dim color for now so `blockquoteAppliesDimColor` still passes):

```swift
        addAttributes([.foregroundColor: theme.dim], range: range)
        ParagraphStyling.mutate(in: storage, range: clampedToStorage(range)) { style in
            style.firstLineHeadIndent = 12
            style.headIndent = 12
        }
```

In `visitCodeBlock` replace `let paragraph = NSMutableParagraphStyle()` … `addAttributes([.font: …, .paragraphStyle: paragraph], range: range)` with:

```swift
        addAttributes([.font: monospacedFont()], range: range)
        ParagraphStyling.mutate(in: storage, range: clampedToStorage(range)) { style in
            style.paragraphSpacingBefore = 8
            style.paragraphSpacing = 8
            style.firstLineHeadIndent = 14
            style.headIndent = 14
            style.tailIndent = -14
        }
```

- [ ] **Step 7: Seed the text view and re-anchor icons on the baseline**

`NoteEditorView.swift`, Coordinator (next to `codeBlockFillColor`):

```swift
        var baseParagraphStyle: NSParagraphStyle { styler.baseParagraphStyle }
```

`makeNSView`, after `textView.font = …`:

```swift
        textView.defaultParagraphStyle = context.coordinator.baseParagraphStyle
        textView.typingAttributes[.paragraphStyle] = context.coordinator.baseParagraphStyle
```

`CheckboxIconLayoutManager.swift`: TextKit 1 adds the extra `lineHeightMultiple` space *above* the glyphs, so centring on `lineFragRect.height * 0.5` drifts high. Anchor on the baseline instead. In `drawIcon` replace `let iconY = lineY + (lineFragRect.height - side) / 2` with:

```swift
        let baselineY = origin.y + lineFragRect.origin.y + middleLocation.y
        let iconY = baselineY - xHeight(forGlyphAt: middleGlyph) / 2 - side / 2
```

(`lineY` becomes unused in `drawIcon`; delete that line.) In `drawBullet` replace `let iconY = lineY + lineFragRect.height * 0.5 - side * 0.5` with:

```swift
        let baselineY = origin.y + lineFragRect.origin.y + firstLocation.y
        let iconY = baselineY - xHeight(forGlyphAt: firstGlyph) / 2 - side / 2
```

(delete the now-unused `lineY` there too) and add the helper near `orderedOverlayFontSize`:

```swift
    /// x-height of the font the styler wrote at `glyphIndex`, so overlay
    /// icons centre on lowercase text regardless of the line-height multiple.
    private nonisolated func xHeight(forGlyphAt glyphIndex: Int) -> CGFloat {
        let charIndex = characterIndexForGlyph(at: glyphIndex)
        guard let storage = textStorage, charIndex < storage.length,
            let font = storage.attribute(.font, at: charIndex, effectiveRange: nil) as? NSFont
        else { return NSFont.systemFont(ofSize: NSFont.systemFontSize).xHeight }
        return font.xHeight
    }
```

- [ ] **Step 8: Run all styling and editor tests**

Run: `swift test --package-path Packages/MarcdownStyling && swift test --package-path Packages/MarcdownEditor`
Expected: PASS (including existing `MarkdownStylerTests`, `ListAttributeTests`, `FocusLineRevealTests`).

- [ ] **Step 9: Build the app and eyeball**

Run: `xcodegen generate && xcodebuild -scheme Marcdown -configuration Debug build`, launch, type a heading, a paragraph, a bullet list with a checkbox. Check: heading is Avenir Next Bold, lines breathe, bullet and checkbox icons sit on the lowercase x-height, caret on an empty note is as tall as typed text.

- [ ] **Step 10: Commit**

```bash
git add Packages/MarcdownStyling Packages/MarcdownEditor
git commit -m "feat: typography baseline with line height and base-family headings"
```

---

### Task 2: Hanging indent for wrapped list and task lines

**Files:**
- Modify: `Packages/MarcdownStyling/Sources/MarcdownStyling/MarkdownStyler.swift` (`applyCheckboxAttributes` ~176-234, `applyListAttributes` ~295-382, `applyParagraphSpacing` from Task 1)
- Test: `Packages/MarcdownStyling/Tests/MarcdownStylingTests/HangingIndentTests.swift` (create)

**Interfaces:**
- Consumes: `ParagraphStyling.mutate` (Task 1).
- Produces: `MarkdownStyler.monoCellWidth: CGFloat`, `MarkdownStyler.spaceWidth: CGFloat` (private lazy); `applyListParagraphStyle(storage:lineStart:lineLength:hangingIndent:)` replaces `applyParagraphSpacing`.

- [ ] **Step 1: Write the failing tests**

```swift
// Packages/MarcdownStyling/Tests/MarcdownStylingTests/HangingIndentTests.swift
import AppKit
import Testing

@testable import MarcdownStyling

@MainActor
@Suite("Hanging indent on list lines")
struct HangingIndentTests {
    private func headIndent(_ source: String, at offset: Int) -> CGFloat {
        let styler = MarkdownStyler()
        let storage = NSTextStorage(string: source)
        styler.restyle(storage: storage, source: source)
        let style = storage.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle
        return style?.headIndent ?? -1
    }

    private func firstLineHeadIndent(_ source: String) -> CGFloat {
        let styler = MarkdownStyler()
        let storage = NSTextStorage(string: source)
        styler.restyle(storage: storage, source: source)
        let style = storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        return style?.firstLineHeadIndent ?? -1
    }

    @Test func bulletLineHangsBodyUnderFirstCharacter() {
        #expect(headIndent("- foo bar", at: 4) > 0)
        #expect(firstLineHeadIndent("- foo bar") == 0)
    }

    @Test func nestedBulletHangsFurther() {
        #expect(headIndent("  - foo", at: 5) > headIndent("- foo", at: 3))
    }

    @Test func twoDigitOrderedMarkerHangsFurtherThanOneDigit() {
        #expect(headIndent("10. foo", at: 5) > headIndent("1. foo", at: 4))
    }

    @Test func taskLineHangs() {
        #expect(headIndent("- [ ] foo", at: 7) > 0)
    }

    @Test func partialMarkerDoesNotHang() {
        #expect(headIndent("-", at: 0) == 0)
        #expect(headIndent("1.", at: 0) == 0)
    }

    @Test func plainLineDoesNotHang() {
        #expect(headIndent("foo", at: 0) == 0)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path Packages/MarcdownStyling --filter HangingIndentTests`
Expected: FAIL on `bulletLineHangsBodyUnderFirstCharacter` (headIndent is 0).

- [ ] **Step 3: Implement**

In `MarkdownStyler` add after `private let baseFont`:

```swift
    /// Advance of one clear-painted marker cell (markers are forced
    /// monospaced) and of one base-font space — the two units a list prefix
    /// is made of. Computed once; fonts don't change during a styler's life.
    private lazy var monoCellWidth: CGFloat = {
        let mono = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
        return ("0" as NSString).size(withAttributes: [.font: mono]).width
    }()
    private lazy var spaceWidth: CGFloat = (" " as NSString).size(withAttributes: [.font: baseFont]).width
```

Rename `applyParagraphSpacing` to `applyListParagraphStyle` with a new parameter:

```swift
    /// List lines get 4pt of air above and hang wrapped text under the first
    /// body character. `hangingIndent` is 0 for partial markers (nothing to
    /// hang under yet).
    private func applyListParagraphStyle(
        storage: NSTextStorage,
        lineStart: Int,
        lineLength: Int,
        hangingIndent: CGFloat
    ) {
        let storageLength = storage.length
        let upper = min(lineStart + lineLength, storageLength)
        let lower = min(lineStart, storageLength)
        guard upper > lower else { return }
        ParagraphStyling.mutate(in: storage, range: NSRange(location: lower, length: upper - lower)) { style in
            style.paragraphSpacingBefore = 4
            style.firstLineHeadIndent = 0
            style.headIndent = hangingIndent
        }
    }
```

Update every call site:
- checkbox `.partial`: `hangingIndent: 0`
- checkbox `.complete(let indentLength, …)`: visible prefix is the clear-painted middle char + `]` (2 mono cells) plus the base-font space before the body → `hangingIndent: CGFloat(indentLength) * spaceWidth + 2 * monoCellWidth + spaceWidth`
- list `.partial`: `hangingIndent: 0`
- list `.complete(let indentLength, let markerLength, …)` (both bullet and ordered): `hangingIndent: CGFloat(indentLength) * spaceWidth + CGFloat(markerLength) * monoCellWidth`

- [ ] **Step 4: Run the package tests**

Run: `swift test --package-path Packages/MarcdownStyling`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/MarcdownStyling
git commit -m "feat: hang wrapped list lines under the marker"
```

---

### Task 3: Blockquote bar with concealed `>` markers

**Files:**
- Modify: `Packages/MarcdownStyling/Sources/MarcdownStyling/ConcealmentAttribute.swift`
- Modify: `Packages/MarcdownStyling/Sources/MarcdownStyling/StyleWalker.swift` (`visitBlockQuote`, init)
- Modify: `Packages/MarcdownStyling/Sources/MarcdownStyling/MarkdownStyler.swift` (`restyle` defensive removes ~61-67)
- Modify: `Packages/MarcdownEditor/Sources/MarcdownEditor/CheckboxIconLayoutManager.swift`
- Modify: `Packages/MarcdownEditor/Sources/MarcdownEditor/NoteEditorView.swift` (`makeNSView`, Coordinator)
- Modify: `Packages/MarcdownStyling/Tests/MarcdownStylingTests/MarkdownStylerTests.swift` (`blockquoteAppliesDimColor` ~109)
- Test: `Packages/MarcdownStyling/Tests/MarcdownStylingTests/BlockquoteStylingTests.swift` (create)

**Interfaces:**
- Produces: `NSAttributedString.Key.marcdownBlockquote` (Bool), `CheckboxIconLayoutManager.quoteBarColor: NSColor?`, `Coordinator.quoteBarColor: NSColor`.

- [ ] **Step 1: Write the failing tests**

Replace `blockquoteAppliesDimColor` in `MarkdownStylerTests.swift` with:

```swift
    @Test func blockquoteMarkerIsClearPaintedAndBodyKeepsColor() {
        let styler = MarkdownStyler()
        let source = "> quoted line"
        let attributed = styler.attributedString(for: source)

        let markerColor = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(markerColor == NSColor.clear)
        let bodyColor = attributed.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor
        #expect(bodyColor == StylingTheme.system.body)
    }
```

Create `BlockquoteStylingTests.swift`:

```swift
import AppKit
import Testing

@testable import MarcdownStyling

@MainActor
@Suite("Blockquote styling")
struct BlockquoteStylingTests {
    private func styledStorage(_ source: String) -> NSTextStorage {
        let styler = MarkdownStyler()
        let storage = NSTextStorage(string: source)
        styler.restyle(storage: storage, source: source)
        return storage
    }

    private func style(_ storage: NSTextStorage, at offset: Int) -> NSParagraphStyle? {
        storage.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle
    }

    @Test func wholeQuoteIsTagged() {
        let storage = styledStorage("> one\n> two")
        for offset in 0..<storage.length {
            #expect(storage.attribute(.marcdownBlockquote, at: offset, effectiveRange: nil) as? Bool == true)
        }
    }

    @Test func markerIsClearPaintedMonospacedNotConcealed() {
        let storage = styledStorage("> hi")
        for offset in 0..<2 {
            #expect(storage.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? NSColor == NSColor.clear)
            let font = storage.attribute(.font, at: offset, effectiveRange: nil) as? NSFont
            #expect(font?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true)
            #expect(storage.attribute(.marcdownConcealed, at: offset, effectiveRange: nil) as? Bool != true)
        }
    }

    @Test func nestedMarkersAreAllClearPainted() {
        let storage = styledStorage("> > deep")
        for offset in 0..<4 {
            #expect(storage.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? NSColor == NSColor.clear)
        }
        #expect(storage.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor == StylingTheme.system.body)
    }

    @Test func bodyHangsUnderFirstCharacterAndLazyLineAligns() {
        let storage = styledStorage("> first line\nlazy continuation")
        let quoted = style(storage, at: 3)
        let lazy = style(storage, at: 15)
        #expect(quoted?.firstLineHeadIndent == 0)
        #expect((quoted?.headIndent ?? 0) > 0)
        #expect(lazy?.firstLineHeadIndent == lazy?.headIndent)
        #expect(lazy?.headIndent == quoted?.headIndent)
    }

    @Test func focusedLineRevealsMarkerAsDimButKeepsBarTag() {
        let source = "> hi"
        let styler = MarkdownStyler()
        let storage = NSTextStorage(string: source)
        styler.restyle(storage: storage, source: source, focusLine: FocusLine(lineStart: 0, lineLength: 4))
        #expect(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == StylingTheme.system.dim)
        #expect(storage.attribute(.marcdownBlockquote, at: 0, effectiveRange: nil) as? Bool == true)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path Packages/MarcdownStyling --filter "BlockquoteStylingTests|MarkdownStylerTests"`
Expected: FAIL (`.marcdownBlockquote` undefined).

- [ ] **Step 3: Add the attribute key**

In `ConcealmentAttribute.swift`, after `marcdownLink`:

```swift
    /// Tags every character of a blockquote (nested quotes share the run).
    /// Value is a `Bool`. Written by `StyleWalker.visitBlockQuote`; read by
    /// the editor's layout manager to draw one vertical bar beside the run.
    public static let marcdownBlockquote = NSAttributedString.Key("marcdownBlockquote")
```

- [ ] **Step 4: Rewrite `visitBlockQuote`**

Add a stored cell width to `StyleWalker` (init computes it):

```swift
    private let monoCellWidth: CGFloat

    init(
        storage: NSTextStorage,
        theme: StylingTheme,
        baseFont: NSFont,
        index: LineOffsetIndex
    ) {
        self.storage = storage
        self.theme = theme
        self.baseFont = baseFont
        self.index = index
        let mono = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
        self.monoCellWidth = ("0" as NSString).size(withAttributes: [.font: mono]).width
    }
```

Replace `visitBlockQuote`:

```swift
    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        guard let range = index.nsRange(blockQuote.range), range.length > 0 else {
            descendInto(blockQuote)
            return
        }
        let clamped = clampedToStorage(range)
        guard clamped.length > 0 else {
            descendInto(blockQuote)
            return
        }
        storage.addAttribute(.marcdownBlockquote, value: true, range: clamped)
        styleBlockquoteLines(in: clamped)
        descendInto(blockQuote)
    }

    /// Per line of the quote: clear-paint the leading `>` run (monospaced so
    /// it keeps a stable advance — the same treatment as list markers) and
    /// hang the body under the first visible character. Lazy-continuation
    /// lines with no marker get the same head indent so they align. Lines
    /// are walked from their true start so a nested quote's visit (whose
    /// node range begins mid-line) recomputes the same full-line prefix.
    private func styleBlockquoteLines(in blockRange: NSRange) {
        let storageString = storage.string as NSString
        let upper = blockRange.location + blockRange.length
        var lineStart = blockRange.location
        while lineStart > 0, storageString.character(at: lineStart - 1) != 0x0A {
            lineStart -= 1
        }
        let mono = monospacedFont()
        var lastMarkerLength = 0
        while lineStart < upper {
            var lineEnd = lineStart
            while lineEnd < upper, storageString.character(at: lineEnd) != 0x0A {
                lineEnd += 1
            }
            let lineRange = NSRange(location: lineStart, length: lineEnd - lineStart)
            if lineRange.length > 0 {
                let markerLength = blockquoteMarkerLength(at: lineRange, in: storageString)
                if markerLength > 0 {
                    let markerRange = NSRange(location: lineStart, length: markerLength)
                    storage.removeAttribute(.marcdownConcealed, range: markerRange)
                    storage.addAttributes([.foregroundColor: NSColor.clear, .font: mono], range: markerRange)
                    lastMarkerLength = markerLength
                }
                let hang = CGFloat(lastMarkerLength) * monoCellWidth
                ParagraphStyling.mutate(in: storage, range: lineRange) { style in
                    style.headIndent = hang
                    style.firstLineHeadIndent = markerLength > 0 ? 0 : hang
                }
            }
            if lineEnd >= upper { break }
            lineStart = lineEnd + 1
        }
    }

    /// UTF-16 length of the leading quote prefix: up to 3 spaces, then one
    /// or more `>` each optionally followed by a space (`> `, `>> `, `> > `).
    /// 0 when the line carries no marker.
    private func blockquoteMarkerLength(at lineRange: NSRange, in storageString: NSString) -> Int {
        let upper = lineRange.location + lineRange.length
        var probe = lineRange.location
        var leading = 0
        while probe < upper, leading < 3, storageString.character(at: probe) == 0x20 {
            probe += 1
            leading += 1
        }
        var sawMarker = false
        // 0x3E == '>'
        while probe < upper, storageString.character(at: probe) == 0x3E {
            sawMarker = true
            probe += 1
            if probe < upper, storageString.character(at: probe) == 0x20 {
                probe += 1
            }
        }
        return sawMarker ? probe - lineRange.location : 0
    }
```

In `MarkdownStyler.restyle` add `storage.removeAttribute(.marcdownBlockquote, range: fullRange)` to the defensive list.

- [ ] **Step 5: Draw the bar**

`CheckboxIconLayoutManager.swift` — add state, colour, and a draw pass called from `drawBackground` right after `drawCodeBlockBackgrounds`:

```swift
    private nonisolated(unsafe) var drawnQuoteRanges: Set<NSRange> = []
    /// Bar colour for `.marcdownBlockquote` runs; set from `StylingTheme.quoteBar`.
    nonisolated(unsafe) var quoteBarColor: NSColor?
```

```swift
        drawCodeBlockBackgrounds(forGlyphRange: glyphsToShow, at: origin)
        drawBlockquoteBars(forGlyphRange: glyphsToShow, at: origin)
```

```swift
    // MARK: - Blockquote bar

    /// One 3pt rounded bar per `.marcdownBlockquote` run, hugging the left
    /// edge of the text container. The clear-painted `> ` cells provide the
    /// gap between bar and text, so no extra indent is needed here.
    private nonisolated func drawBlockquoteBars(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        drawnQuoteRanges.removeAll(keepingCapacity: true)
        guard let storage = textStorage, let container = textContainers.first else { return }
        guard glyphsToShow.length > 0 else { return }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        guard charRange.length > 0 else { return }

        let storageLength = storage.length
        let upper = min(charRange.location + charRange.length, storageLength)
        let color = quoteBarColor ?? NSColor.tertiaryLabelColor
        var probe = charRange.location
        while probe < upper {
            var effective = NSRange(location: 0, length: 0)
            let value = storage.attribute(
                .marcdownBlockquote,
                at: probe,
                longestEffectiveRange: &effective,
                in: NSRange(location: 0, length: storageLength)
            )
            if let flag = value as? Bool, flag, effective.length > 0, !drawnQuoteRanges.contains(effective) {
                drawnQuoteRanges.insert(effective)
                let glyphs = glyphRange(forCharacterRange: effective, actualCharacterRange: nil)
                if glyphs.length > 0 {
                    let bounding = boundingRect(forGlyphRange: glyphs, in: container)
                    let rect = NSRect(x: origin.x + 4, y: origin.y + bounding.origin.y, width: 3, height: bounding.height)
                    color.setFill()
                    NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
                }
            }
            probe = max(probe + 1, effective.location + effective.length)
        }
    }
```

`NoteEditorView.swift`: Coordinator gets `var quoteBarColor: NSColor { styler.theme.quoteBar }`; `makeNSView` sets `layoutManager.quoteBarColor = context.coordinator.quoteBarColor` next to `codeBlockFillColor`.

- [ ] **Step 6: Run tests**

Run: `swift test --package-path Packages/MarcdownStyling && swift test --package-path Packages/MarcdownEditor`
Expected: PASS. If `FocusLineRevealTests` asserts a blockquote marker colour, it expects `theme.dim` on the focused line, which the clear→dim flip still produces.

- [ ] **Step 7: Build, verify visually**

Type `> quote` then `> > nested`, wrap a long quoted line, press Enter to continue. Check: one bar at left, no visible `>`, wrapped text aligned, `>` reappears dim on the caret line.

- [ ] **Step 8: Commit**

```bash
git add Packages/MarcdownStyling Packages/MarcdownEditor
git commit -m "feat: blockquote bar with concealed markers"
```

---

### Task 4: Horizontal rule

**Files:**
- Modify: `Packages/MarcdownStyling/Sources/MarcdownStyling/ConcealmentAttribute.swift`
- Modify: `Packages/MarcdownStyling/Sources/MarcdownStyling/StyleWalker.swift` (`visitThematicBreak` ~264)
- Modify: `Packages/MarcdownStyling/Sources/MarcdownStyling/MarkdownStyler.swift` (`applyListScannerPass` ~279, `applyFocusReveal` ~112)
- Modify: `Packages/MarcdownEditor/Sources/MarcdownEditor/CheckboxIconLayoutManager.swift`
- Modify: `Packages/MarcdownEditor/Sources/MarcdownEditor/NoteEditorView.swift`
- Test: `Packages/MarcdownStyling/Tests/MarcdownStylingTests/ThematicBreakTests.swift` (create)

**Interfaces:**
- Produces: `NSAttributedString.Key.marcdownThematicBreak` (Bool), `CheckboxIconLayoutManager.ruleColor: NSColor?`, `Coordinator.ruleColor: NSColor`.

- [ ] **Step 1: Write the failing tests**

```swift
// Packages/MarcdownStyling/Tests/MarcdownStylingTests/ThematicBreakTests.swift
import AppKit
import Testing

@testable import MarcdownStyling

@MainActor
@Suite("Thematic break")
struct ThematicBreakTests {
    private func styledStorage(_ source: String, focus: FocusLine? = nil) -> NSTextStorage {
        let styler = MarkdownStyler()
        let storage = NSTextStorage(string: source)
        styler.restyle(storage: storage, source: source, focusLine: focus)
        return storage
    }

    @Test func dashesAreClearPaintedAndTagged() {
        let storage = styledStorage("a\n\n---\n\nb")
        let ruleStart = 3
        for offset in ruleStart..<(ruleStart + 3) {
            #expect(storage.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? NSColor == NSColor.clear)
            #expect(storage.attribute(.marcdownThematicBreak, at: offset, effectiveRange: nil) as? Bool == true)
            #expect(storage.attribute(.marcdownConcealed, at: offset, effectiveRange: nil) as? Bool != true)
        }
        #expect(storage.attribute(.marcdownThematicBreak, at: 0, effectiveRange: nil) == nil)
    }

    @Test func starRuleIsNotTreatedAsBullet() {
        let storage = styledStorage("* * *")
        #expect(storage.attribute(.marcdownListMarker, at: 0, effectiveRange: nil) == nil)
        #expect(storage.attribute(.marcdownThematicBreak, at: 0, effectiveRange: nil) as? Bool == true)
    }

    @Test func focusedRuleShowsDimDashesAndDropsTag() {
        let storage = styledStorage("---", focus: FocusLine(lineStart: 0, lineLength: 3))
        #expect(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == StylingTheme.system.dim)
        #expect(storage.attribute(.marcdownThematicBreak, at: 0, effectiveRange: nil) == nil)
    }

    @Test func setextUnderlineIsNotARule() {
        let storage = styledStorage("Title\n---")
        #expect(storage.attribute(.marcdownThematicBreak, at: 6, effectiveRange: nil) == nil)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path Packages/MarcdownStyling --filter ThematicBreakTests`
Expected: FAIL (key undefined).

- [ ] **Step 3: Implement**

`ConcealmentAttribute.swift`:

```swift
    /// Tags the characters of a thematic break (`---`, `***`, `___`, spaced
    /// variants). Value is a `Bool`. Written by `StyleWalker.visitThematicBreak`;
    /// read by the layout manager to draw a rule; stripped on the focus line.
    public static let marcdownThematicBreak = NSAttributedString.Key("marcdownThematicBreak")
```

`StyleWalker.visitThematicBreak`:

```swift
    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        guard let range = index.nsRange(thematicBreak.range), range.length > 0 else { return }
        let clamped = clampedToStorage(range)
        guard clamped.length > 0 else { return }
        // Clear-paint (never `.null`-conceal): the rule is the whole line, so
        // it must keep an advance for the caret to land on. The layout
        // manager draws the rule in its place.
        storage.removeAttribute(.marcdownConcealed, range: clamped)
        storage.addAttributes(
            [
                .foregroundColor: NSColor.clear,
                .font: monospacedFont(),
                .marcdownThematicBreak: true,
            ],
            range: clamped
        )
        ParagraphStyling.mutate(in: storage, range: clamped) { style in
            style.paragraphSpacingBefore = 8
            style.paragraphSpacing = 8
        }
    }
```

`MarkdownStyler.applyListScannerPass`: `* * *` and `- - -` scan as bullets, so skip tagged lines. Inside the `if lineLength > 0 {` block, first line:

```swift
                if storage.attribute(.marcdownThematicBreak, at: lineStart, effectiveRange: nil) != nil {
                    if lineEnd >= length { break }
                    lineStart = lineEnd + 1
                    continue
                }
```

`MarkdownStyler.applyFocusReveal`: add `storage.removeAttribute(.marcdownThematicBreak, range: range)` after the checkbox strip. `restyle`: add `.marcdownThematicBreak` to the defensive removes.

`CheckboxIconLayoutManager.swift`:

```swift
    private nonisolated(unsafe) var drawnRuleRanges: Set<NSRange> = []
    /// Colour of the drawn horizontal rule; set from `StylingTheme.rule`.
    nonisolated(unsafe) var ruleColor: NSColor?
```

Call `drawThematicBreaks(forGlyphRange: glyphsToShow, at: origin)` after `drawBlockquoteBars` and add:

```swift
    // MARK: - Horizontal rule

    /// A 1pt line across the container at the vertical middle of the
    /// clear-painted `---` line fragment. Anchored on `lineFragmentRect`
    /// (stable) rather than `boundingRect` (see class doc).
    private nonisolated func drawThematicBreaks(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        drawnRuleRanges.removeAll(keepingCapacity: true)
        guard let storage = textStorage, let container = textContainers.first else { return }
        guard glyphsToShow.length > 0 else { return }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        guard charRange.length > 0 else { return }

        let storageLength = storage.length
        let upper = min(charRange.location + charRange.length, storageLength)
        let color = ruleColor ?? NSColor.separatorColor
        var probe = charRange.location
        while probe < upper {
            var effective = NSRange(location: 0, length: 0)
            let value = storage.attribute(
                .marcdownThematicBreak,
                at: probe,
                longestEffectiveRange: &effective,
                in: NSRange(location: 0, length: storageLength)
            )
            if let flag = value as? Bool, flag, effective.length > 0, !drawnRuleRanges.contains(effective) {
                drawnRuleRanges.insert(effective)
                let glyphs = glyphRange(forCharacterRange: effective, actualCharacterRange: nil)
                if glyphs.length > 0 {
                    let fragment = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
                    let rect = NSRect(x: origin.x, y: origin.y + fragment.midY - 0.5, width: container.size.width, height: 1)
                    color.setFill()
                    rect.fill()
                }
            }
            probe = max(probe + 1, effective.location + effective.length)
        }
    }
```

`NoteEditorView.swift`: Coordinator `var ruleColor: NSColor { styler.theme.rule }`; `makeNSView`: `layoutManager.ruleColor = context.coordinator.ruleColor`.

- [ ] **Step 4: Run tests**

Run: `swift test --package-path Packages/MarcdownStyling && swift test --package-path Packages/MarcdownEditor`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/MarcdownStyling Packages/MarcdownEditor
git commit -m "feat: draw thematic breaks as a horizontal rule"
```

---

### Task 5: `==Highlight==`

**Files:**
- Create: `Packages/MarcdownStyling/Sources/MarcdownStyling/HighlightScanner.swift`
- Modify: `Packages/MarcdownStyling/Sources/MarcdownStyling/MarkdownStyler.swift` (`restyle`, new pass, `forEachLine` helper)
- Modify: `Packages/MarcdownStyling/Sources/MarcdownStyling/HTMLExporter.swift`
- Test: `Packages/MarcdownStyling/Tests/MarcdownStylingTests/HighlightScannerTests.swift` (create), `HighlightStylingTests.swift` (create), `HTMLExporterTests.swift` (add one test)

**Interfaces:**
- Produces: `HighlightScanner.scan(line: String) -> [NSRange]` (line-relative ranges covering `==…==`); `HTMLExporter.markHighlights(in:) -> String` (internal).

- [ ] **Step 1: Write the failing tests**

```swift
// Packages/MarcdownStyling/Tests/MarcdownStylingTests/HighlightScannerTests.swift
import Foundation
import Testing

@testable import MarcdownStyling

@Suite("HighlightScanner")
struct HighlightScannerTests {
    @Test func findsSingleSpan() {
        #expect(HighlightScanner.scan(line: "a ==b== c") == [NSRange(location: 2, length: 5)])
    }

    @Test func findsTwoSpans() {
        #expect(
            HighlightScanner.scan(line: "==a== ==b==") == [
                NSRange(location: 0, length: 5),
                NSRange(location: 6, length: 5),
            ])
    }

    @Test func ignoresUnterminated() {
        #expect(HighlightScanner.scan(line: "==open").isEmpty)
    }

    @Test func ignoresSpaceAfterOpener() {
        #expect(HighlightScanner.scan(line: "== not ==").isEmpty)
    }

    @Test func ignoresEmptySpan() {
        #expect(HighlightScanner.scan(line: "====").isEmpty)
    }

    @Test func ignoresSpaceBeforeCloser() {
        #expect(HighlightScanner.scan(line: "==a ==").isEmpty)
    }
}
```

```swift
// Packages/MarcdownStyling/Tests/MarcdownStylingTests/HighlightStylingTests.swift
import AppKit
import Testing

@testable import MarcdownStyling

@MainActor
@Suite("Highlight styling")
struct HighlightStylingTests {
    private func styledStorage(_ source: String) -> NSTextStorage {
        let styler = MarkdownStyler()
        let storage = NSTextStorage(string: source)
        styler.restyle(storage: storage, source: source)
        return storage
    }

    @Test func contentGetsBackgroundAndDelimitersAreConcealed() {
        let storage = styledStorage("x ==hi== y")
        #expect(storage.attribute(.backgroundColor, at: 4, effectiveRange: nil) as? NSColor == StylingTheme.system.highlight)
        #expect(storage.attribute(.marcdownConcealed, at: 2, effectiveRange: nil) as? Bool == true)
        #expect(storage.attribute(.marcdownConcealed, at: 3, effectiveRange: nil) as? Bool == true)
        #expect(storage.attribute(.marcdownConcealed, at: 6, effectiveRange: nil) as? Bool == true)
        #expect(storage.attribute(.marcdownConcealed, at: 7, effectiveRange: nil) as? Bool == true)
        #expect(storage.attribute(.backgroundColor, at: 0, effectiveRange: nil) == nil)
    }

    @Test func codeBlockLinesAreLeftAlone() {
        let storage = styledStorage("```\na ==b== c\n```")
        #expect(storage.attribute(.backgroundColor, at: 8, effectiveRange: nil) == nil)
    }

    @Test func inlineCodeIsLeftAlone() {
        let storage = styledStorage("`a ==b== c`")
        #expect(storage.attribute(.marcdownConcealed, at: 3, effectiveRange: nil) as? Bool != true)
    }
}
```

Add to `HTMLExporterTests.swift`:

```swift
    @Test func highlightExportsAsMark() {
        let html = HTMLExporter.render(markdown: "say ==hi== there", title: "t")
        #expect(html.contains("say <mark>hi</mark> there"))
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path Packages/MarcdownStyling --filter "Highlight|HTMLExporter"`
Expected: FAIL (scanner undefined).

- [ ] **Step 3: Scanner**

```swift
// Packages/MarcdownStyling/Sources/MarcdownStyling/HighlightScanner.swift
import Foundation

/// Pure helper. AppKit-free. `==text==` is not CommonMark, so the AST walk
/// never sees it; this line scanner is the single owner of the shape.
public enum HighlightScanner {
    /// Line-relative UTF-16 ranges of every `==text==` span. A span opens at
    /// `==` followed by a non-space, non-`=` unit and closes at the next `==`
    /// preceded by a non-space unit. Unterminated openers are ignored.
    public static func scan(line: String) -> [NSRange] {
        let units = Array(line.utf16)
        let count = units.count
        var results: [NSRange] = []
        var i = 0
        // Minimum span is `==x==` (5 units).
        while i + 4 < count {
            if units[i] == 0x3D, units[i + 1] == 0x3D, units[i + 2] != 0x20, units[i + 2] != 0x3D {
                guard let close = closingIndex(units, from: i + 3) else { return results }
                results.append(NSRange(location: i, length: close + 2 - i))
                i = close + 2
                continue
            }
            i += 1
        }
        return results
    }

    private static func closingIndex(_ units: [UInt16], from start: Int) -> Int? {
        var j = start
        while j + 1 < units.count {
            if units[j] == 0x3D, units[j + 1] == 0x3D, units[j - 1] != 0x20 {
                return j
            }
            j += 1
        }
        return nil
    }
}
```

- [ ] **Step 4: Styler pass + `forEachLine` helper**

In `MarkdownStyler` add a line iterator and migrate the two existing scanner passes to it (they are byte-for-byte the same loop):

```swift
    /// Calls `body` once per line of `source` with the line's UTF-16 start
    /// offset and its content (no trailing `\n`). Empty lines are skipped.
    private func forEachLine(in source: String, _ body: (_ lineStart: Int, _ line: String) -> Void) {
        let units = Array(source.utf16)
        let length = units.count
        var lineStart = 0
        while lineStart <= length {
            var lineEnd = lineStart
            while lineEnd < length, units[lineEnd] != 0x0A {
                lineEnd += 1
            }
            if lineEnd > lineStart {
                body(lineStart, String(decoding: units[lineStart..<lineEnd], as: UTF16.self))
            }
            if lineEnd >= length { break }
            lineStart = lineEnd + 1
        }
    }
```

`applyCheckboxScannerPass` becomes:

```swift
    private func applyCheckboxScannerPass(storage: NSTextStorage, source: String) {
        forEachLine(in: source) { lineStart, line in
            applyCheckboxAttributes(
                for: CheckboxLineScanner.scan(line: line),
                storage: storage,
                lineStart: lineStart,
                lineLength: (line as NSString).length
            )
        }
    }
```

`applyListScannerPass` keeps its checkbox-precedence logic but inside `forEachLine`, and the Task 4 thematic-break skip becomes a plain `guard … == nil else { return }` at the top of the closure.

New pass, called in `restyle` after `applyListScannerPass` and before the focus reveal:

```swift
    /// `==text==` → highlight background on the content, delimiters concealed.
    /// Skips code (fenced blocks via the tag, inline code via the monospaced
    /// font already applied by the walker).
    private func applyHighlightPass(storage: NSTextStorage, source: String) {
        forEachLine(in: source) { lineStart, line in
            guard storage.attribute(.marcdownCodeBlock, at: lineStart, effectiveRange: nil) == nil else { return }
            for span in HighlightScanner.scan(line: line) {
                let location = lineStart + span.location
                guard span.length > 4, location + span.length <= storage.length else { continue }
                if let font = storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont,
                    font.fontDescriptor.symbolicTraits.contains(.monoSpace)
                {
                    continue  // ponytail: also skips highlights inside tables; revisit if it bites
                }
                storage.addAttribute(
                    .backgroundColor,
                    value: theme.highlight,
                    range: NSRange(location: location + 2, length: span.length - 4)
                )
                applyConceal(storage: storage, range: NSRange(location: location, length: 2))
                applyConceal(storage: storage, range: NSRange(location: location + span.length - 2, length: 2))
            }
        }
    }
```

- [ ] **Step 5: HTML export**

In `HTMLExporter.render` change `let body = HTMLFormatter.format(markdown)` to `let body = HTMLFormatter.format(markHighlights(in: markdown))` and add:

```swift
    /// `==text==` → `<mark>text</mark>`. cmark passes inline HTML through, so
    /// this pre-pass is enough. ponytail: also rewrites inside code spans;
    /// switch to a post-AST rewrite if that ever matters.
    static func markHighlights(in markdown: String) -> String {
        markdown.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let text = String(line)
            let units = Array(text.utf16)
            var rebuilt = ""
            var cursor = 0
            for span in HighlightScanner.scan(line: text) {
                rebuilt += String(decoding: units[cursor..<span.location], as: UTF16.self)
                rebuilt += "<mark>"
                rebuilt += String(decoding: units[(span.location + 2)..<(span.location + span.length - 2)], as: UTF16.self)
                rebuilt += "</mark>"
                cursor = span.location + span.length
            }
            rebuilt += String(decoding: units[cursor...], as: UTF16.self)
            return rebuilt
        }.joined(separator: "\n")
    }
```

Add to `defaultCSS`: `mark { background: rgba(255,214,10,.35); padding: 0 .1em; border-radius: 2px; }`

- [ ] **Step 6: Run tests**

Run: `swift test --package-path Packages/MarcdownStyling`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Packages/MarcdownStyling
git commit -m "feat: highlight syntax with mark export"
```

---

### Task 6: Fence-less code blocks with a language badge

**Files:**
- Modify: `Packages/MarcdownStyling/Sources/MarcdownStyling/ConcealmentAttribute.swift`
- Modify: `Packages/MarcdownStyling/Sources/MarcdownStyling/StyleWalker.swift` (`visitCodeBlock` ~168-207, `dimFenceLines` ~212)
- Modify: `Packages/MarcdownStyling/Sources/MarcdownStyling/MarkdownStyler.swift` (`applyFocusReveal`, `restyle`)
- Modify: `Packages/MarcdownEditor/Sources/MarcdownEditor/CheckboxIconLayoutManager.swift`
- Test: `Packages/MarcdownStyling/Tests/MarcdownStylingTests/MarkdownStylerTests.swift` (add two tests)

**Interfaces:**
- Produces: `NSAttributedString.Key.marcdownCodeLanguage` (String) on the opening fence line.

- [ ] **Step 1: Write the failing tests** (append to `MarkdownStylerTests`)

```swift
    @Test func fenceLinesAreClearPaintedAndOpeningFenceCarriesLanguage() {
        let styler = MarkdownStyler()
        let source = "```swift\nlet x = 1\n```"
        let storage = NSTextStorage(string: source)
        styler.restyle(storage: storage, source: source)

        #expect(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == NSColor.clear)
        #expect(storage.attribute(.marcdownCodeLanguage, at: 0, effectiveRange: nil) as? String == "swift")
        let closing = (source as NSString).length - 1
        #expect(storage.attribute(.foregroundColor, at: closing, effectiveRange: nil) as? NSColor == NSColor.clear)
        #expect(storage.attribute(.marcdownCodeLanguage, at: closing, effectiveRange: nil) == nil)
        #expect(storage.attribute(.foregroundColor, at: 10, effectiveRange: nil) as? NSColor == StylingTheme.system.body)
    }

    @Test func focusedFenceLineRevealsDimFenceAndHidesBadge() {
        let styler = MarkdownStyler()
        let source = "```swift\nlet x = 1\n```"
        let storage = NSTextStorage(string: source)
        styler.restyle(storage: storage, source: source, focusLine: FocusLine(lineStart: 0, lineLength: 8))

        #expect(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == StylingTheme.system.dim)
        #expect(storage.attribute(.marcdownCodeLanguage, at: 0, effectiveRange: nil) == nil)
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path Packages/MarcdownStyling --filter MarkdownStylerTests`
Expected: FAIL (key undefined).

- [ ] **Step 3: Implement**

`ConcealmentAttribute.swift`:

```swift
    /// Tags the opening fence line of a fenced code block with its info
    /// string (`swift` in ```` ```swift ````). Value is a `String`. Written by
    /// `StyleWalker.visitCodeBlock`; read by the layout manager to draw a
    /// language badge; stripped on the focus line.
    public static let marcdownCodeLanguage = NSAttributedString.Key("marcdownCodeLanguage")
```

`StyleWalker.visitCodeBlock`: replace the call `dimFenceLines(in: clamped)` with `concealFenceLines(in: clamped, language: codeBlock.language)` and replace `dimFenceLines` with:

```swift
    /// Fence lines are clear-painted (monospaced already, so they keep an
    /// advance and the caret can land on them) and the first one carries the
    /// language tag. Focus-line reveal flips them to dim so the user still
    /// sees ```` ``` ```` while editing that line.
    private func concealFenceLines(in blockRange: NSRange, language: String?) {
        guard blockRange.length > 0 else { return }
        let storageString = storage.string as NSString
        let upper = blockRange.location + blockRange.length
        var lineStart = blockRange.location
        var isFirstFence = true
        while lineStart < upper {
            var lineEnd = lineStart
            while lineEnd < upper, storageString.character(at: lineEnd) != 0x0A {
                lineEnd += 1
            }
            let lineRange = NSRange(location: lineStart, length: lineEnd - lineStart)
            if lineRange.length > 0, isFenceLine(at: lineRange, in: storageString) {
                storage.removeAttribute(.marcdownConcealed, range: lineRange)
                storage.addAttribute(.foregroundColor, value: NSColor.clear, range: lineRange)
                if isFirstFence, let language, !language.isEmpty {
                    storage.addAttribute(.marcdownCodeLanguage, value: language, range: lineRange)
                }
                isFirstFence = false
            }
            if lineEnd >= upper { break }
            lineStart = lineEnd + 1
        }
    }
```

`MarkdownStyler.applyFocusReveal`: add `storage.removeAttribute(.marcdownCodeLanguage, range: range)`. `restyle`: add it to the defensive removes.

`CheckboxIconLayoutManager.swift`: add `private nonisolated(unsafe) var drawnBadgeRanges: Set<NSRange> = []`, call `drawCodeLanguageBadges(forGlyphRange:at:)` right after `drawCodeBlockBackgrounds`, and:

```swift
    // MARK: - Code language badge

    /// Right-aligned language name on the (clear-painted) opening fence
    /// line, 4pt smaller than the code font, secondary colour. Uses the same
    /// baseline conversion as `drawOrderedNumber`.
    private nonisolated func drawCodeLanguageBadges(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        drawnBadgeRanges.removeAll(keepingCapacity: true)
        guard let storage = textStorage, let container = textContainers.first else { return }
        guard glyphsToShow.length > 0 else { return }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        guard charRange.length > 0 else { return }

        let storageLength = storage.length
        let upper = min(charRange.location + charRange.length, storageLength)
        var probe = charRange.location
        while probe < upper {
            var effective = NSRange(location: 0, length: 0)
            let value = storage.attribute(
                .marcdownCodeLanguage,
                at: probe,
                longestEffectiveRange: &effective,
                in: NSRange(location: 0, length: storageLength)
            )
            if let language = value as? String, effective.length > 0, !drawnBadgeRanges.contains(effective) {
                drawnBadgeRanges.insert(effective)
                let glyphs = glyphRange(forCharacterRange: effective, actualCharacterRange: nil)
                if glyphs.length > 0 {
                    let fragment = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
                    let baseline = location(forGlyphAt: glyphs.location)
                    let size = max(9, orderedOverlayFontSize(forGlyphAt: glyphs.location) - 4)
                    let font = NSFont.monospacedSystemFont(ofSize: size, weight: .medium)
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: NSColor.secondaryLabelColor,
                    ]
                    let width = (language as NSString).size(withAttributes: attributes).width
                    let point = NSPoint(
                        x: origin.x + container.size.width - 14 - width,
                        y: origin.y + fragment.origin.y + baseline.y - font.ascender
                    )
                    (language as NSString).draw(at: point, withAttributes: attributes)
                }
            }
            probe = max(probe + 1, effective.location + effective.length)
        }
    }
```

- [ ] **Step 4: Run tests, build, verify**

Run: `swift test --package-path Packages/MarcdownStyling && swift test --package-path Packages/MarcdownEditor`
Expected: PASS. In the app: type ```` ```swift ````, Enter, code, Enter, ```` ``` ````. Check: rounded container, no visible fences off-line, `swift` at top-right, fence reappears dim when the caret is on it.

- [ ] **Step 5: Commit**

```bash
git add Packages/MarcdownStyling Packages/MarcdownEditor
git commit -m "feat: conceal code fences and draw a language badge"
```

---

### Task 7: Skip redundant restyles on caret moves within a line

**Files:**
- Modify: `Packages/MarcdownEditor/Sources/MarcdownEditor/NoteEditorView.swift` (`restyle` ~173, `textDidChange` ~182, `textViewDidChangeSelection` ~208)
- Test: `Packages/MarcdownEditor/Tests/MarcdownEditorTests/FocusRestyleTests.swift` (create)

**Interfaces:**
- Produces: `Coordinator.revealedFocusLine: FocusLine?` (internal, read by tests).

- [ ] **Step 1: Write the failing test**

```swift
// Packages/MarcdownEditor/Tests/MarcdownEditorTests/FocusRestyleTests.swift
import AppKit
import MarcdownStyling
import SwiftUI
import Testing

@testable import MarcdownEditor

@MainActor
@Suite("Focus-line restyle guard")
struct FocusRestyleTests {
    @Test func movingWithinALineKeepsRevealAndMovingLinesUpdatesIt() {
        let storage = NSTextStorage(string: "**a**\n**b**")
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        layoutManager.addTextContainer(container)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 400), textContainer: container)
        var sink = ""
        let coordinator = NoteEditorView.Coordinator(text: Binding(get: { sink }, set: { sink = $0 }))
        textView.delegate = coordinator
        coordinator.install(textView: textView, storage: storage)

        textView.setSelectedRange(NSRange(location: 1, length: 0))
        coordinator.textViewDidChangeSelection(Notification(name: NSText.didChangeNotification, object: textView))
        #expect(coordinator.revealedFocusLine == FocusLine(lineStart: 0, lineLength: 5))
        #expect(storage.attribute(.marcdownConcealed, at: 0, effectiveRange: nil) as? Bool != true)

        textView.setSelectedRange(NSRange(location: 3, length: 0))
        coordinator.textViewDidChangeSelection(Notification(name: NSText.didChangeNotification, object: textView))
        #expect(coordinator.revealedFocusLine == FocusLine(lineStart: 0, lineLength: 5))

        textView.setSelectedRange(NSRange(location: 8, length: 0))
        coordinator.textViewDidChangeSelection(Notification(name: NSText.didChangeNotification, object: textView))
        #expect(coordinator.revealedFocusLine == FocusLine(lineStart: 6, lineLength: 5))
        #expect(storage.attribute(.marcdownConcealed, at: 0, effectiveRange: nil) as? Bool == true)
        #expect(storage.attribute(.marcdownConcealed, at: 6, effectiveRange: nil) as? Bool != true)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path Packages/MarcdownEditor --filter FocusRestyleTests`
Expected: FAIL (`revealedFocusLine` undefined).

- [ ] **Step 3: Implement**

In `Coordinator`:

```swift
        /// The line the last restyle revealed. Caret moves inside that line
        /// don't change what is concealed, so `textViewDidChangeSelection`
        /// skips the full re-parse for them.
        private(set) var revealedFocusLine: FocusLine?

        func restyle() {
            guard let storage else { return }
            restyle(storage: storage)
        }

        private func restyle(storage: NSTextStorage) {
            let focus = currentFocusLine()
            styler.restyle(storage: storage, source: storage.string, focusLine: focus)
            revealedFocusLine = focus
        }
```

`textDidChange`: replace the `styler.restyle(...)` call with `restyle(storage: storage)`. `textViewDidChangeSelection`: replace the `styler.restyle(...)` call with:

```swift
            if currentFocusLine() == revealedFocusLine { return }
            restyle(storage: storage)
```

`updateNSView` already calls `context.coordinator.restyle()`; unchanged.

- [ ] **Step 4: Run tests and commit**

Run: `swift test --package-path Packages/MarcdownEditor`
Expected: PASS.

```bash
git add Packages/MarcdownEditor
git commit -m "perf: skip restyle when the caret stays on the revealed line"
```

---

# Phase 2 — Editing commands

### Task 8: Command plumbing and inline formatting shortcuts (⌘B ⌘I ⌘E ⇧⌘X ⇧⌘H ⇧⌘K)

**Files:**
- Create: `Packages/MarcdownStyling/Sources/MarcdownStyling/TextEditOutcome.swift`
- Create: `Packages/MarcdownStyling/Sources/MarcdownStyling/InlineFormat.swift`
- Create: `Packages/MarcdownEditor/Sources/MarcdownEditor/EditorCommand.swift`
- Modify: `Packages/MarcdownEditor/Sources/MarcdownEditor/NoteEditorView.swift` (Coordinator; `FocusOnAttachTextView`; `makeNSView`; doc comment lines 23-24)
- Create: `Packages/MarcdownEditor/Tests/MarcdownEditorTests/EditorHarness.swift`
- Modify: `.github/workflows/ci.yml` (matrix ~105, lint paths ~51-57)
- Test: `Packages/MarcdownStyling/Tests/MarcdownStylingTests/InlineFormatTests.swift`, `Packages/MarcdownEditor/Tests/MarcdownEditorTests/EditorCommandTests.swift`, `Packages/MarcdownEditor/Tests/MarcdownEditorTests/InlineFormatCommandTests.swift` (all create)

**Interfaces:**
- Produces:
  - `public enum TextEditOutcome: Sendable, Equatable { case noOp; case replace(range: NSRange, replacement: String, selection: NSRange) }` — `selection` is in post-edit coordinates.
  - `InlineFormat.toggleOutcome(buffer: String, selection: NSRange, delimiter: String) -> TextEditOutcome`
  - `InlineFormat.linkOutcome(buffer: String, selection: NSRange, url: String) -> TextEditOutcome`
  - `InlineFormat.isHTTPURL(_ text: String) -> Bool`
  - `public enum EditorCommand: Hashable, Sendable` with cases `bold, italic, inlineCode, strikethrough, highlight, link, heading(Int), bulletList, orderedList, taskList, quote, codeBlock, divider`; `static func command(forKey key: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> EditorCommand?`
  - `Coordinator.perform(_ command: EditorCommand) -> Bool` (internal, `@discardableResult`); `Coordinator.apply(_ outcome: TextEditOutcome, undoName: String, in textView: NSTextView) -> Bool`
  - `EditorHarness.make(buffer: String) -> EditorHarness` with `storage`, `textView`, `coordinator`, `setCaret(_:)`, `select(_:_:)`, `send(_:)`.
- Tasks 9–13 route every edit through `apply` and every command through `perform`.

- [ ] **Step 1: Write the failing pure tests**

```swift
// Packages/MarcdownStyling/Tests/MarcdownStylingTests/InlineFormatTests.swift
import Foundation
import Testing

@testable import MarcdownStyling

@Suite("InlineFormat")
struct InlineFormatTests {
    @Test func wrapsSelection() {
        #expect(
            InlineFormat.toggleOutcome(buffer: "hello world", selection: NSRange(location: 0, length: 5), delimiter: "**")
                == .replace(range: NSRange(location: 0, length: 5), replacement: "**hello**", selection: NSRange(location: 2, length: 5)))
    }

    @Test func unwrapsWhenDelimitersSurroundSelection() {
        #expect(
            InlineFormat.toggleOutcome(buffer: "**hello**", selection: NSRange(location: 2, length: 5), delimiter: "**")
                == .replace(range: NSRange(location: 0, length: 9), replacement: "hello", selection: NSRange(location: 0, length: 5)))
    }

    @Test func unwrapsWhenSelectionIncludesDelimiters() {
        #expect(
            InlineFormat.toggleOutcome(buffer: "a **b** c", selection: NSRange(location: 2, length: 5), delimiter: "**")
                == .replace(range: NSRange(location: 2, length: 5), replacement: "b", selection: NSRange(location: 2, length: 1)))
    }

    @Test func trimsWhitespaceBeforeWrapping() {
        #expect(
            InlineFormat.toggleOutcome(buffer: "hi there", selection: NSRange(location: 2, length: 6), delimiter: "*")
                == .replace(range: NSRange(location: 3, length: 5), replacement: "*there*", selection: NSRange(location: 4, length: 5)))
    }

    @Test func caretInsertsPairAndParksInside() {
        #expect(
            InlineFormat.toggleOutcome(buffer: "ab", selection: NSRange(location: 1, length: 0), delimiter: "`")
                == .replace(range: NSRange(location: 1, length: 0), replacement: "``", selection: NSRange(location: 2, length: 0)))
    }

    @Test func caretInsideEmptyPairRemovesIt() {
        #expect(
            InlineFormat.toggleOutcome(buffer: "a****b", selection: NSRange(location: 3, length: 0), delimiter: "**")
                == .replace(range: NSRange(location: 1, length: 4), replacement: "", selection: NSRange(location: 1, length: 0)))
    }

    @Test func whitespaceOnlySelectionIsNoOp() {
        #expect(InlineFormat.toggleOutcome(buffer: "a  b", selection: NSRange(location: 1, length: 2), delimiter: "*") == .noOp)
    }

    @Test func linkWithSelectionAndURLPutsCaretAfter() {
        #expect(
            InlineFormat.linkOutcome(buffer: "see docs", selection: NSRange(location: 4, length: 4), url: "https://x.y")
                == .replace(range: NSRange(location: 4, length: 4), replacement: "[docs](https://x.y)", selection: NSRange(location: 23, length: 0)))
    }

    @Test func linkWithSelectionAndNoURLParksCaretInParens() {
        #expect(
            InlineFormat.linkOutcome(buffer: "docs", selection: NSRange(location: 0, length: 4), url: "")
                == .replace(range: NSRange(location: 0, length: 4), replacement: "[docs]()", selection: NSRange(location: 7, length: 0)))
    }

    @Test func linkWithCaretParksInsideBrackets() {
        #expect(
            InlineFormat.linkOutcome(buffer: "", selection: NSRange(location: 0, length: 0), url: "")
                == .replace(range: NSRange(location: 0, length: 0), replacement: "[]()", selection: NSRange(location: 1, length: 0)))
    }

    @Test func detectsHTTPURLs() {
        #expect(InlineFormat.isHTTPURL("https://example.com/a?b=c"))
        #expect(InlineFormat.isHTTPURL("  http://x.io \n"))
        #expect(!InlineFormat.isHTTPURL("example.com"))
        #expect(!InlineFormat.isHTTPURL("https://a b"))
        #expect(!InlineFormat.isHTTPURL("mailto:a@b.c"))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path Packages/MarcdownStyling --filter InlineFormatTests`
Expected: FAIL (types undefined).

- [ ] **Step 3: Implement the pure helpers**

```swift
// Packages/MarcdownStyling/Sources/MarcdownStyling/TextEditOutcome.swift
import Foundation

/// Result of any editing command. Shared by inline/block formatting,
/// selection indent, and paste helpers so the editor applies every edit with
/// one code path. `selection` is expressed in the buffer *after* the edit.
public enum TextEditOutcome: Sendable, Equatable {
    case noOp
    case replace(range: NSRange, replacement: String, selection: NSRange)
}
```

```swift
// Packages/MarcdownStyling/Sources/MarcdownStyling/InlineFormat.swift
import Foundation

/// Pure helpers for inline formatting commands. AppKit-free, UTF-16 offsets.
public enum InlineFormat {
    /// Toggle `delimiter` (`**`, `*`, `` ` ``, `~~`, `==`) around `selection`.
    /// - Caret: `**|**` removes the empty pair; otherwise inserts a pair and
    ///   parks the caret inside.
    /// - Selection already wrapped (either side of, or inside, the selection):
    ///   unwrap.
    /// - Otherwise wrap the whitespace-trimmed selection (`**foo **` is not
    ///   strong) and select the inner text.
    public static func toggleOutcome(buffer: String, selection: NSRange, delimiter: String) -> TextEditOutcome {
        let units = Array(buffer.utf16)
        let delim = Array(delimiter.utf16)
        let dl = delim.count
        guard dl > 0, selection.location >= 0, selection.location + selection.length <= units.count else {
            return .noOp
        }

        if selection.length == 0 {
            let caret = selection.location
            if caret >= dl, caret + dl <= units.count,
                Array(units[(caret - dl)..<caret]) == delim,
                Array(units[caret..<(caret + dl)]) == delim
            {
                return .replace(
                    range: NSRange(location: caret - dl, length: dl * 2),
                    replacement: "",
                    selection: NSRange(location: caret - dl, length: 0)
                )
            }
            return .replace(
                range: NSRange(location: caret, length: 0),
                replacement: delimiter + delimiter,
                selection: NSRange(location: caret + dl, length: 0)
            )
        }

        var lower = selection.location
        var upper = selection.location + selection.length
        while lower < upper, isSpace(units[lower]) { lower += 1 }
        while upper > lower, isSpace(units[upper - 1]) { upper -= 1 }
        guard upper > lower else { return .noOp }

        if lower >= dl, upper + dl <= units.count,
            Array(units[(lower - dl)..<lower]) == delim,
            Array(units[upper..<(upper + dl)]) == delim
        {
            return .replace(
                range: NSRange(location: lower - dl, length: upper - lower + 2 * dl),
                replacement: String(decoding: units[lower..<upper], as: UTF16.self),
                selection: NSRange(location: lower - dl, length: upper - lower)
            )
        }
        if upper - lower >= 2 * dl,
            Array(units[lower..<(lower + dl)]) == delim,
            Array(units[(upper - dl)..<upper]) == delim
        {
            return .replace(
                range: NSRange(location: lower, length: upper - lower),
                replacement: String(decoding: units[(lower + dl)..<(upper - dl)], as: UTF16.self),
                selection: NSRange(location: lower, length: upper - lower - 2 * dl)
            )
        }
        let inner = String(decoding: units[lower..<upper], as: UTF16.self)
        return .replace(
            range: NSRange(location: lower, length: upper - lower),
            replacement: delimiter + inner + delimiter,
            selection: NSRange(location: lower + dl, length: upper - lower)
        )
    }

    /// `[selection](url)`. Caret lands after `)` when a URL is given, inside
    /// `()` when it is empty, and inside `[]` when there was no selection.
    public static func linkOutcome(buffer: String, selection: NSRange, url: String) -> TextEditOutcome {
        let units = Array(buffer.utf16)
        guard selection.location >= 0, selection.location + selection.length <= units.count else { return .noOp }
        let label = String(decoding: units[selection.location..<(selection.location + selection.length)], as: UTF16.self)
        let replacement = "[\(label)](\(url))"
        let start = selection.location
        let caret: Int
        if selection.length == 0 {
            caret = start + 1
        } else if url.isEmpty {
            caret = start + selection.length + 3
        } else {
            caret = start + (replacement as NSString).length
        }
        return .replace(range: selection, replacement: replacement, selection: NSRange(location: caret, length: 0))
    }

    /// True for a single `http`/`https` URL with a host and no interior whitespace.
    public static func isHTTPURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: { $0.isWhitespace }),
            let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            url.host != nil
        else { return false }
        return true
    }

    private static func isSpace(_ unit: UInt16) -> Bool { unit == 0x20 || unit == 0x09 }
}
```

- [ ] **Step 4: Run pure tests**

Run: `swift test --package-path Packages/MarcdownStyling --filter InlineFormatTests`
Expected: PASS.

- [ ] **Step 5: Write the failing editor tests and the shared harness**

```swift
// Packages/MarcdownEditor/Tests/MarcdownEditorTests/EditorHarness.swift
import AppKit
import SwiftUI

@testable import MarcdownEditor

/// Real TextKit 1 stack + Coordinator, mirroring the private harness in
/// `ListIndentCommandTests`. New command tests share this one.
@MainActor
struct EditorHarness {
    let storage: NSTextStorage
    let textView: NSTextView
    let coordinator: NoteEditorView.Coordinator

    static func make(buffer: String) -> EditorHarness {
        let storage = NSTextStorage(string: buffer)
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        layoutManager.addTextContainer(container)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 400), textContainer: container)
        textView.allowsUndo = true
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true

        var sink = buffer
        let coordinator = NoteEditorView.Coordinator(text: Binding(get: { sink }, set: { sink = $0 }))
        textView.delegate = coordinator
        coordinator.install(textView: textView, storage: storage)
        coordinator.restyle()
        return EditorHarness(storage: storage, textView: textView, coordinator: coordinator)
    }

    func setCaret(_ location: Int) {
        textView.setSelectedRange(NSRange(location: location, length: 0))
    }

    func select(_ location: Int, _ length: Int) {
        textView.setSelectedRange(NSRange(location: location, length: length))
    }

    func send(_ selector: Selector) -> Bool {
        coordinator.textView(textView, doCommandBy: selector)
    }
}
```

```swift
// Packages/MarcdownEditor/Tests/MarcdownEditorTests/EditorCommandTests.swift
import AppKit
import Testing

@testable import MarcdownEditor

@Suite("EditorCommand chord table")
struct EditorCommandTests {
    @Test func commandBoldAndShiftCommandQuote() {
        #expect(EditorCommand.command(forKey: "b", keyCode: 11, modifiers: [.command]) == .bold)
        #expect(EditorCommand.command(forKey: "B", keyCode: 11, modifiers: [.command, .shift]) == .quote)
    }

    @Test func extraModifiersDoNotMatch() {
        #expect(EditorCommand.command(forKey: "b", keyCode: 11, modifiers: [.command, .option]) == nil)
        #expect(EditorCommand.command(forKey: "b", keyCode: 11, modifiers: [.command, .control]) == nil)
    }

    @Test func capsLockIsIgnored() {
        #expect(EditorCommand.command(forKey: "B", keyCode: 11, modifiers: [.command, .capsLock]) == .bold)
    }

    @Test func headingsMatchPhysicalDigitKeys() {
        #expect(EditorCommand.command(forKey: "&", keyCode: 18, modifiers: [.command, .option]) == .heading(1))
        #expect(EditorCommand.command(forKey: "6", keyCode: 22, modifiers: [.command, .option]) == .heading(6))
        #expect(EditorCommand.command(forKey: "0", keyCode: 29, modifiers: [.command, .option]) == .heading(0))
        #expect(EditorCommand.command(forKey: "1", keyCode: 18, modifiers: [.command]) == nil)
    }

    @Test func remainingChords() {
        #expect(EditorCommand.command(forKey: "i", keyCode: 34, modifiers: [.command]) == .italic)
        #expect(EditorCommand.command(forKey: "e", keyCode: 14, modifiers: [.command]) == .inlineCode)
        #expect(EditorCommand.command(forKey: "x", keyCode: 7, modifiers: [.command, .shift]) == .strikethrough)
        #expect(EditorCommand.command(forKey: "h", keyCode: 4, modifiers: [.command, .shift]) == .highlight)
        #expect(EditorCommand.command(forKey: "k", keyCode: 40, modifiers: [.command, .shift]) == .link)
        #expect(EditorCommand.command(forKey: "l", keyCode: 37, modifiers: [.command, .shift]) == .bulletList)
        #expect(EditorCommand.command(forKey: "n", keyCode: 45, modifiers: [.command, .shift]) == .orderedList)
        #expect(EditorCommand.command(forKey: "t", keyCode: 17, modifiers: [.command, .shift]) == .taskList)
    }
}
```

```swift
// Packages/MarcdownEditor/Tests/MarcdownEditorTests/InlineFormatCommandTests.swift
import AppKit
import Testing

@testable import MarcdownEditor

@MainActor
@Suite("Inline formatting commands")
struct InlineFormatCommandTests {
    @Test func boldWrapsSelection() {
        let harness = EditorHarness.make(buffer: "hello world")
        harness.select(0, 5)

        #expect(harness.coordinator.perform(.bold) == true)
        #expect(harness.storage.string == "**hello** world")
        #expect(harness.textView.selectedRange() == NSRange(location: 2, length: 5))
    }

    @Test func boldTwiceRoundTrips() {
        let harness = EditorHarness.make(buffer: "hello")
        harness.select(0, 5)
        harness.coordinator.perform(.bold)
        harness.coordinator.perform(.bold)
        #expect(harness.storage.string == "hello")
        #expect(harness.textView.selectedRange() == NSRange(location: 0, length: 5))
    }

    @Test func italicCaretInsertsPair() {
        let harness = EditorHarness.make(buffer: "")
        harness.setCaret(0)
        harness.coordinator.perform(.italic)
        #expect(harness.storage.string == "**")
        #expect(harness.textView.selectedRange() == NSRange(location: 1, length: 0))
    }

    @Test func highlightAndStrikethroughAndCode() {
        let harness = EditorHarness.make(buffer: "abc")
        harness.select(0, 3)
        harness.coordinator.perform(.highlight)
        #expect(harness.storage.string == "==abc==")
        harness.coordinator.perform(.highlight)
        harness.coordinator.perform(.strikethrough)
        #expect(harness.storage.string == "~~abc~~")
        harness.coordinator.perform(.strikethrough)
        harness.coordinator.perform(.inlineCode)
        #expect(harness.storage.string == "`abc`")
    }

    @Test func undoRestoresBuffer() {
        let harness = EditorHarness.make(buffer: "hello")
        harness.select(0, 5)
        harness.coordinator.perform(.bold)
        harness.textView.undoManager?.undo()
        #expect(harness.storage.string == "hello")
    }
}
```

- [ ] **Step 6: Run to verify failure**

Run: `swift test --package-path Packages/MarcdownEditor --filter "EditorCommandTests|InlineFormatCommandTests"`
Expected: FAIL (`EditorCommand`, `perform` undefined).

- [ ] **Step 7: `EditorCommand`**

```swift
// Packages/MarcdownEditor/Sources/MarcdownEditor/EditorCommand.swift
import AppKit

/// Every formatting command the editor understands. Dispatched from three
/// places with one implementation (`Coordinator.perform`): ⌘-chords caught
/// in the text view, the ⌘K palette's Markdown rows, and the `/` menu.
public enum EditorCommand: Hashable, Sendable {
    case bold
    case italic
    case inlineCode
    case strikethrough
    case highlight
    case link
    /// 1…6 set a heading level; 0 turns the line back into a paragraph.
    case heading(Int)
    case bulletList
    case orderedList
    case taskList
    case quote
    case codeBlock
    case divider

    /// Chord table. Letters match the layout's character (lower-cased so
    /// Shift/Caps Lock don't matter); heading digits match the physical key
    /// so AZERTY/QWERTZ layouts, where digits need Shift, still work.
    /// Modifiers must match exactly — ⌥⌘B is not Bold.
    static func command(forKey key: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> EditorCommand? {
        let mods = modifiers.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        let command: NSEvent.ModifierFlags = [.command]
        let shiftCommand: NSEvent.ModifierFlags = [.command, .shift]
        let optionCommand: NSEvent.ModifierFlags = [.command, .option]

        if mods == optionCommand, let level = headingLevel(forKeyCode: keyCode) {
            return .heading(level)
        }
        switch (key.lowercased(), mods) {
        case ("b", command): return .bold
        case ("i", command): return .italic
        case ("e", command): return .inlineCode
        case ("x", shiftCommand): return .strikethrough
        case ("h", shiftCommand): return .highlight
        case ("k", shiftCommand): return .link
        case ("l", shiftCommand): return .bulletList
        case ("n", shiftCommand): return .orderedList
        case ("t", shiftCommand): return .taskList
        case ("b", shiftCommand): return .quote
        default: return nil
        }
    }

    /// kVK_ANSI_0…6 virtual key codes.
    private static func headingLevel(forKeyCode code: UInt16) -> Int? {
        switch code {
        case 29: return 0
        case 18: return 1
        case 19: return 2
        case 20: return 3
        case 21: return 4
        case 23: return 5
        case 22: return 6
        default: return nil
        }
    }
}
```

- [ ] **Step 8: Coordinator `apply` + `perform`, text view `performKeyEquivalent`**

In `NoteEditorView.swift` replace the doc-comment lines 23-24 ("There are no formatting hotkeys…") with:

```swift
/// Formatting commands (⌘B, ⌘I, …) are caught in `FocusOnAttachTextView.
/// performKeyEquivalent` and routed to `Coordinator.perform`, which is also
/// the entry point for the command palette and the `/` menu.
```

Add to `Coordinator` (after `toggleCheckbox`):

```swift
        // MARK: - Formatting commands

        /// Single entry point for every formatting command. Returns `false`
        /// when nothing changed so a ⌘-chord can fall through to AppKit.
        @discardableResult
        func perform(_ command: EditorCommand) -> Bool {
            guard let textView, let storage else { return false }
            if textView.hasMarkedText() { return false }
            let buffer = storage.string
            let selection = textView.selectedRange()
            switch command {
            case .bold:
                return apply(InlineFormat.toggleOutcome(buffer: buffer, selection: selection, delimiter: "**"), undoName: "Bold", in: textView)
            case .italic:
                return apply(InlineFormat.toggleOutcome(buffer: buffer, selection: selection, delimiter: "*"), undoName: "Italic", in: textView)
            case .inlineCode:
                return apply(InlineFormat.toggleOutcome(buffer: buffer, selection: selection, delimiter: "`"), undoName: "Inline Code", in: textView)
            case .strikethrough:
                return apply(InlineFormat.toggleOutcome(buffer: buffer, selection: selection, delimiter: "~~"), undoName: "Strikethrough", in: textView)
            case .highlight:
                return apply(InlineFormat.toggleOutcome(buffer: buffer, selection: selection, delimiter: "=="), undoName: "Highlight", in: textView)
            case .link:
                let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
                let url = InlineFormat.isHTTPURL(clipboard) ? clipboard.trimmingCharacters(in: .whitespacesAndNewlines) : ""
                return apply(InlineFormat.linkOutcome(buffer: buffer, selection: selection, url: url), undoName: "Link", in: textView)
            case .heading, .bulletList, .orderedList, .taskList, .quote, .codeBlock, .divider:
                return false  // Task 9
            }
        }

        /// The one place edits from pure helpers touch the storage: the
        /// same shouldChange → replace → didChange → select dance every
        /// keystroke handler already does, with a named undo group.
        @discardableResult
        func apply(_ outcome: TextEditOutcome, undoName: String, in textView: NSTextView) -> Bool {
            guard let storage = textView.textStorage else { return false }
            switch outcome {
            case .noOp:
                return false
            case .replace(let range, let replacement, let selection):
                guard textView.shouldChangeText(in: range, replacementString: replacement) else { return false }
                textView.undoManager?.setActionName(undoName)
                storage.replaceCharacters(in: range, with: replacement)
                textView.didChangeText()
                textView.setSelectedRange(selection)
                return true
            }
        }
```

In `FocusOnAttachTextView` add:

```swift
    /// Receives ⌘-chords the chord table recognises. Returns whether the
    /// command changed anything; `false` lets AppKit's default run.
    var commandHandler: ((EditorCommand) -> Bool)?

    /// ⌘-keyDowns walk the view tree here before reaching `keyDown`. The
    /// first-responder guard keeps chords from firing while a palette text
    /// field owns the keyboard (DESIGN.md: chrome shortcuts are disabled
    /// while an overlay is open). Chord sets are disjoint from the App's
    /// SwiftUI `.keyboardShortcut` layer, so order between the two never
    /// matters.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self,
            let key = event.charactersIgnoringModifiers,
            let command = EditorCommand.command(forKey: key, keyCode: event.keyCode, modifiers: event.modifierFlags),
            commandHandler?(command) == true
        else { return super.performKeyEquivalent(with: event) }
        return true
    }
```

In `makeNSView`, after the `checkboxClickHandler` assignment:

```swift
        textView.commandHandler = { [weak coordinator = context.coordinator] command in
            coordinator?.perform(command) ?? false
        }
```

- [ ] **Step 9: Run editor tests**

Run: `swift test --package-path Packages/MarcdownEditor`
Expected: PASS.

- [ ] **Step 10: CI covers the editor package**

`.github/workflows/ci.yml`: matrix line becomes `package: [MarcdownCore, MarcdownStyling, MarcdownEditor, MarcdownLaunchKit]`; lint paths add `Packages/MarcdownEditor/Tests` after `Packages/MarcdownEditor/Sources`. Run `actionlint .github/workflows/ci.yml` if installed, and the swift-format lint command from Global Constraints over `Packages/MarcdownEditor`.

- [ ] **Step 11: Build and try the chords**

`xcodegen generate && xcodebuild -scheme Marcdown -configuration Debug build`, run. Select a word, ⌘B → `**word**` rendered bold, selection stays on the word; ⌘B again unwraps. ⌘K still opens the palette; with the palette open ⌘B does nothing. Copy a URL, select text, ⇧⌘K → link.

- [ ] **Step 12: Commit**

```bash
git add Packages/MarcdownStyling Packages/MarcdownEditor .github/workflows/ci.yml
git commit -m "feat: inline formatting shortcuts with a shared command channel"
```

---

### Task 9: Block commands — headings, bullet/numbered/task lists, quote, code block, divider

**Files:**
- Create: `Packages/MarcdownStyling/Sources/MarcdownStyling/BlockFormat.swift`
- Modify: `Packages/MarcdownEditor/Sources/MarcdownEditor/NoteEditorView.swift` (`perform` block cases)
- Test: `Packages/MarcdownStyling/Tests/MarcdownStylingTests/BlockFormatTests.swift`, `Packages/MarcdownEditor/Tests/MarcdownEditorTests/BlockCommandTests.swift` (create)

**Interfaces:**
- Produces: `public enum BlockKind: Sendable, Equatable { case paragraph, heading(Int), bullet, ordered, task, quote }`; `BlockFormat.toggleOutcome(buffer: String, selection: NSRange, kind: BlockKind) -> TextEditOutcome`; `BlockFormat.codeBlockOutcome(buffer:selection:) -> TextEditOutcome`; `BlockFormat.dividerOutcome(buffer:selection:) -> TextEditOutcome`.
- Consumes: `TextEditOutcome`, `CheckboxLineScanner.scan`, `ListLineScanner.scan`, `Coordinator.apply`, `runRenumberPass`.

- [ ] **Step 1: Write the failing pure tests**

```swift
// Packages/MarcdownStyling/Tests/MarcdownStylingTests/BlockFormatTests.swift
import Foundation
import Testing

@testable import MarcdownStyling

@Suite("BlockFormat")
struct BlockFormatTests {
    private func toggled(_ buffer: String, _ location: Int, _ length: Int = 0, _ kind: BlockKind) -> (String, NSRange)? {
        guard case .replace(let range, let replacement, let selection) = BlockFormat.toggleOutcome(
            buffer: buffer, selection: NSRange(location: location, length: length), kind: kind)
        else { return nil }
        let ns = buffer as NSString
        return (ns.replacingCharacters(in: range, with: replacement), selection)
    }

    @Test func headingOnPlainLineShiftsCaret() {
        let result = toggled("hello", 3, .heading(2))
        #expect(result?.0 == "## hello")
        #expect(result?.1 == NSRange(location: 6, length: 0))
    }

    @Test func headingReplacesExistingListMarker() {
        #expect(toggled("- item", 6, .heading(1))?.0 == "# item")
    }

    @Test func headingOnSameLevelTogglesOff() {
        let result = toggled("# title", 7, .heading(1))
        #expect(result?.0 == "title")
        #expect(result?.1 == NSRange(location: 5, length: 0))
    }

    @Test func headingLevelChangeIsNotAToggleOff() {
        #expect(toggled("# title", 2, .heading(3))?.0 == "### title")
    }

    @Test func paragraphStripsAnyMarker() {
        #expect(toggled("> q", 3, .paragraph)?.0 == "q")
        #expect(toggled("- [ ] t", 7, .paragraph)?.0 == "t")
        #expect(BlockFormat.toggleOutcome(buffer: "plain", selection: NSRange(location: 0, length: 0), kind: .paragraph) == .noOp)
    }

    @Test func caretInsideOldMarkerLandsAfterNewMarker() {
        #expect(toggled("- item", 1, .quote)?.1 == NSRange(location: 2, length: 0))
    }

    @Test func multiLineSelectionBecomesNumberedListAndSelectsAll() {
        let result = toggled("a\nb\nc", 0, 5, .ordered)
        #expect(result?.0 == "1. a\n2. b\n3. c")
        #expect(result?.1 == NSRange(location: 0, length: 14))
    }

    @Test func partialMultiLineSelectionCoversWholeTouchedLines() {
        // Selection spans offsets 1..<5 ("a\nbb"): lines 1 and 2, not line 3.
        #expect(toggled("aa\nbb\ncc", 1, 4, .bullet)?.0 == "- aa\n- bb\ncc")
    }

    @Test func mixedLinesAreConvertedNotToggledOff() {
        #expect(toggled("- a\nb", 0, 5, .bullet)?.0 == "- a\n- b")
    }

    @Test func allBulletsToggleOff() {
        #expect(toggled("- a\n- b", 0, 7, .bullet)?.0 == "a\nb")
    }

    @Test func taskAndQuotePreserveIndent() {
        #expect(toggled("  - a", 5, .task)?.0 == "  - [ ] a")
        #expect(toggled("  x", 3, .quote)?.0 == "  > x")
    }

    @Test func codeBlockWrapsSelectedLines() {
        guard case .replace(let range, let replacement, let selection) = BlockFormat.codeBlockOutcome(
            buffer: "a\nb", selection: NSRange(location: 0, length: 3))
        else { Issue.record("expected replace"); return }
        #expect(range == NSRange(location: 0, length: 3))
        #expect(replacement == "```\na\nb\n```")
        #expect(selection == NSRange(location: 4, length: 3))
    }

    @Test func codeBlockOnEmptyLineParksCaretInside() {
        #expect(
            BlockFormat.codeBlockOutcome(buffer: "", selection: NSRange(location: 0, length: 0))
                == .replace(range: NSRange(location: 0, length: 0), replacement: "```\n\n```", selection: NSRange(location: 4, length: 0)))
    }

    @Test func codeBlockAfterTextGoesOnNextLine() {
        #expect(
            BlockFormat.codeBlockOutcome(buffer: "x", selection: NSRange(location: 1, length: 0))
                == .replace(range: NSRange(location: 1, length: 0), replacement: "\n```\n\n```", selection: NSRange(location: 6, length: 0)))
    }

    @Test func dividerOnEmptyLineAndAfterText() {
        #expect(
            BlockFormat.dividerOutcome(buffer: "", selection: NSRange(location: 0, length: 0))
                == .replace(range: NSRange(location: 0, length: 0), replacement: "---", selection: NSRange(location: 3, length: 0)))
        #expect(
            BlockFormat.dividerOutcome(buffer: "x", selection: NSRange(location: 1, length: 0))
                == .replace(range: NSRange(location: 1, length: 0), replacement: "\n\n---", selection: NSRange(location: 6, length: 0)))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path Packages/MarcdownStyling --filter BlockFormatTests`
Expected: FAIL (types undefined).

- [ ] **Step 3: Implement**

```swift
// Packages/MarcdownStyling/Sources/MarcdownStyling/BlockFormat.swift
import Foundation

/// Line-level block types a command can set.
public enum BlockKind: Sendable, Equatable {
    case paragraph
    case heading(Int)
    case bullet
    case ordered
    case task
    case quote
}

/// Pure helpers for block commands. AppKit-free, UTF-16 offsets.
public enum BlockFormat {
    /// Rewrites every line touched by `selection` to `kind`, keeping leading
    /// indent. If every touched line already is `kind`, the marker is removed
    /// (toggle off). Ordered items are numbered from 1. A caret stays on its
    /// text (clamped to after the new marker); a multi-line selection ends
    /// up covering the rewritten lines.
    public static func toggleOutcome(buffer: String, selection: NSRange, kind: BlockKind) -> TextEditOutcome {
        let units = Array(buffer.utf16)
        guard selection.location >= 0, selection.location + selection.length <= units.count else { return .noOp }
        let (blockStart, blockEnd) = lineSpan(units: units, selection: selection)
        let lines = splitLines(units: units, from: blockStart, to: blockEnd)
        let prefixes = lines.map { LinePrefix.scan(line: $0) }
        let removing = kind == .paragraph || prefixes.allSatisfy { $0.kind == kind }

        var rebuilt: [String] = []
        var number = 1
        var firstNewPrefixLength = 0
        for (line, prefix) in zip(lines, prefixes) {
            let marker: String
            if removing {
                marker = ""
            } else {
                switch kind {
                case .paragraph: marker = ""
                case .heading(let level): marker = String(repeating: "#", count: max(1, min(6, level))) + " "
                case .bullet: marker = "- "
                case .ordered:
                    marker = "\(number). "
                    number += 1
                case .task: marker = "- [ ] "
                case .quote: marker = "> "
                }
            }
            if rebuilt.isEmpty { firstNewPrefixLength = prefix.indentLength + (marker as NSString).length }
            let indent = String(decoding: line[0..<prefix.indentLength], as: UTF16.self)
            let body = String(decoding: line[prefix.prefixLength...], as: UTF16.self)
            rebuilt.append(indent + marker + body)
        }
        let replacement = rebuilt.joined(separator: "\n")
        let original = String(decoding: units[blockStart..<blockEnd], as: UTF16.self)
        guard replacement != original else { return .noOp }

        let range = NSRange(location: blockStart, length: blockEnd - blockStart)
        let newSelection: NSRange
        if selection.length == 0 {
            let delta = firstNewPrefixLength - prefixes[0].prefixLength
            newSelection = NSRange(location: max(blockStart + firstNewPrefixLength, selection.location + delta), length: 0)
        } else {
            newSelection = NSRange(location: blockStart, length: (replacement as NSString).length)
        }
        return .replace(range: range, replacement: replacement, selection: newSelection)
    }

    /// Fenced code block. With a selection: fence the touched lines and
    /// select their bodies. With a caret on an empty line: replace it with an
    /// empty block; on a non-empty line: open the block on the next line.
    public static func codeBlockOutcome(buffer: String, selection: NSRange) -> TextEditOutcome {
        let units = Array(buffer.utf16)
        guard selection.location >= 0, selection.location + selection.length <= units.count else { return .noOp }
        let (blockStart, blockEnd) = lineSpan(units: units, selection: selection)
        if selection.length > 0 {
            let body = String(decoding: units[blockStart..<blockEnd], as: UTF16.self)
            return .replace(
                range: NSRange(location: blockStart, length: blockEnd - blockStart),
                replacement: "```\n" + body + "\n```",
                selection: NSRange(location: blockStart + 4, length: blockEnd - blockStart)
            )
        }
        if blockEnd == blockStart {
            return .replace(
                range: NSRange(location: blockStart, length: 0),
                replacement: "```\n\n```",
                selection: NSRange(location: blockStart + 4, length: 0)
            )
        }
        return .replace(
            range: NSRange(location: blockEnd, length: 0),
            replacement: "\n```\n\n```",
            selection: NSRange(location: blockEnd + 5, length: 0)
        )
    }

    /// `---` on its own line. After text it is preceded by a blank line so
    /// CommonMark doesn't read it as a setext heading underline.
    public static func dividerOutcome(buffer: String, selection: NSRange) -> TextEditOutcome {
        let units = Array(buffer.utf16)
        guard selection.location >= 0, selection.location + selection.length <= units.count else { return .noOp }
        let (blockStart, blockEnd) = lineSpan(units: units, selection: selection)
        if blockEnd == blockStart {
            return .replace(
                range: NSRange(location: blockStart, length: 0),
                replacement: "---",
                selection: NSRange(location: blockStart + 3, length: 0)
            )
        }
        return .replace(
            range: NSRange(location: blockEnd, length: 0),
            replacement: "\n\n---",
            selection: NSRange(location: blockEnd + 5, length: 0)
        )
    }

    // MARK: - Line prefix classification

    struct LinePrefix: Equatable {
        let indentLength: Int
        /// Indent + marker, i.e. where the body starts.
        let prefixLength: Int
        let kind: BlockKind?

        static func scan(line: [UInt16]) -> LinePrefix {
            let text = String(decoding: line, as: UTF16.self)
            var indent = 0
            while indent < line.count, line[indent] == 0x20 || line[indent] == 0x09 { indent += 1 }

            if case .complete(let indentLength, let bracket, _) = CheckboxLineScanner.scan(line: text) {
                var end = bracket + 3
                if end < line.count, line[end] == 0x20 { end += 1 }
                return LinePrefix(indentLength: indentLength, prefixLength: end, kind: .task)
            }
            if case .complete(let indentLength, let markerLength, let markerKind) = ListLineScanner.scan(line: text) {
                switch markerKind {
                case .bullet: return LinePrefix(indentLength: indentLength, prefixLength: indentLength + markerLength, kind: .bullet)
                case .ordered: return LinePrefix(indentLength: indentLength, prefixLength: indentLength + markerLength, kind: .ordered)
                }
            }
            var probe = indent
            var hashes = 0
            while probe < line.count, hashes < 6, line[probe] == 0x23 {
                hashes += 1
                probe += 1
            }
            if hashes > 0, probe < line.count, line[probe] == 0x20 {
                return LinePrefix(indentLength: indent, prefixLength: probe + 1, kind: .heading(hashes))
            }
            if indent < line.count, line[indent] == 0x3E {
                var end = indent + 1
                if end < line.count, line[end] == 0x20 { end += 1 }
                return LinePrefix(indentLength: indent, prefixLength: end, kind: .quote)
            }
            return LinePrefix(indentLength: indent, prefixLength: indent, kind: nil)
        }
    }

    // MARK: - Helpers

    /// Start of the first line and end (exclusive of `\n`) of the last line
    /// touched by `selection`.
    static func lineSpan(units: [UInt16], selection: NSRange) -> (Int, Int) {
        var start = selection.location
        while start > 0, units[start - 1] != 0x0A { start -= 1 }
        var end = selection.location + selection.length
        // A selection ending right after a newline does not touch the next line.
        if selection.length > 0, end > 0, units[end - 1] == 0x0A { end -= 1 }
        while end < units.count, units[end] != 0x0A { end += 1 }
        return (start, end)
    }

    static func splitLines(units: [UInt16], from: Int, to: Int) -> [[UInt16]] {
        var lines: [[UInt16]] = []
        var lineStart = from
        var probe = from
        while probe < to {
            if units[probe] == 0x0A {
                lines.append(Array(units[lineStart..<probe]))
                lineStart = probe + 1
            }
            probe += 1
        }
        lines.append(Array(units[lineStart..<to]))
        return lines
    }
}
```

- [ ] **Step 4: Run pure tests**

Run: `swift test --package-path Packages/MarcdownStyling --filter BlockFormatTests`
Expected: PASS.

- [ ] **Step 5: Write the failing editor test**

```swift
// Packages/MarcdownEditor/Tests/MarcdownEditorTests/BlockCommandTests.swift
import AppKit
import Testing

@testable import MarcdownEditor

@MainActor
@Suite("Block formatting commands")
struct BlockCommandTests {
    @Test func headingOneOnCaretLine() {
        let harness = EditorHarness.make(buffer: "hello")
        harness.setCaret(5)
        #expect(harness.coordinator.perform(.heading(1)) == true)
        #expect(harness.storage.string == "# hello")
        #expect(harness.textView.selectedRange() == NSRange(location: 7, length: 0))
    }

    @Test func paragraphCommandStripsHeading() {
        let harness = EditorHarness.make(buffer: "## hello")
        harness.setCaret(8)
        harness.coordinator.perform(.heading(0))
        #expect(harness.storage.string == "hello")
    }

    @Test func orderedListOverSelectionRenumbersWithNeighbours() {
        let harness = EditorHarness.make(buffer: "1. a\nb\nc")
        harness.select(5, 3)
        harness.coordinator.perform(.orderedList)
        #expect(harness.storage.string == "1. a\n2. b\n3. c")
    }

    @Test func taskQuoteAndDivider() {
        let harness = EditorHarness.make(buffer: "x")
        harness.setCaret(1)
        harness.coordinator.perform(.taskList)
        #expect(harness.storage.string == "- [ ] x")
        harness.coordinator.perform(.quote)
        #expect(harness.storage.string == "> x")
        harness.coordinator.perform(.divider)
        #expect(harness.storage.string == "> x\n\n---")
    }
}
```

- [ ] **Step 6: Implement the block cases in `Coordinator.perform`**

Replace the `case .heading, .bulletList, …: return false  // Task 9` line with `default: return performBlock(command, in: textView)` and add:

```swift
        private func performBlock(_ command: EditorCommand, in textView: NSTextView) -> Bool {
            guard let storage = textView.textStorage else { return false }
            let buffer = storage.string
            let selection = textView.selectedRange()
            let kind: BlockKind
            let undoName: String
            switch command {
            case .heading(let level):
                kind = level == 0 ? .paragraph : .heading(level)
                undoName = level == 0 ? "Paragraph" : "Heading \(level)"
            case .bulletList:
                kind = .bullet
                undoName = "Bullet List"
            case .orderedList:
                kind = .ordered
                undoName = "Numbered List"
            case .taskList:
                kind = .task
                undoName = "Task List"
            case .quote:
                kind = .quote
                undoName = "Quote"
            case .codeBlock:
                return apply(BlockFormat.codeBlockOutcome(buffer: buffer, selection: selection), undoName: "Code Block", in: textView)
            case .divider:
                return apply(BlockFormat.dividerOutcome(buffer: buffer, selection: selection), undoName: "Divider", in: textView)
            default:
                return false
            }
            let handled = apply(BlockFormat.toggleOutcome(buffer: buffer, selection: selection, kind: kind), undoName: undoName, in: textView)
            if handled {
                runRenumberPass(in: textView, around: textView.selectedRange().location)
            }
            return handled
        }
```

- [ ] **Step 7: Run editor tests**

Run: `swift test --package-path Packages/MarcdownEditor`
Expected: PASS. If `orderedListOverSelectionRenumbersWithNeighbours` fails because `OrderedListRenumber.renumberRun` anchors on the caret line only, change the assertion buffer to `"a\nb\nc"` selecting all and expect `"1. a\n2. b\n3. c"`; note the neighbour-merge ceiling with a `// ponytail:` comment in `performBlock`.

- [ ] **Step 8: Build, try ⌘⌥1…6, ⇧⌘L/N/T/B on single lines and selections. Commit**

```bash
git add Packages/MarcdownStyling Packages/MarcdownEditor
git commit -m "feat: heading, list, task, quote, code block and divider commands"
```

---

### Task 10: Tab / Shift-Tab over a multi-line selection

**Files:**
- Modify: `Packages/MarcdownStyling/Sources/MarcdownStyling/ListIndentation.swift`
- Modify: `Packages/MarcdownEditor/Sources/MarcdownEditor/NoteEditorView.swift` (`handleInsertTab` ~296, `handleInsertBacktab` ~322)
- Test: `Packages/MarcdownStyling/Tests/MarcdownStylingTests/ListIndentationTests.swift` (append), `Packages/MarcdownEditor/Tests/MarcdownEditorTests/ListIndentCommandTests.swift` (append)

**Interfaces:**
- Produces: `ListIndentation.indentOutcome(buffer: String, selection: NSRange) -> TextEditOutcome`, `ListIndentation.outdentOutcome(buffer: String, selection: NSRange) -> TextEditOutcome`.
- Consumes: `BlockFormat.lineSpan`, `BlockFormat.splitLines`, `Coordinator.apply`.

- [ ] **Step 1: Write the failing tests** (append to `ListIndentationTests`)

```swift
    @Test func selectionIndentsEveryListLineAndSelectsThem() {
        #expect(
            ListIndentation.indentOutcome(buffer: "- a\n- b\nplain", selection: NSRange(location: 0, length: 13))
                == .replace(range: NSRange(location: 0, length: 13), replacement: "  - a\n  - b\nplain", selection: NSRange(location: 0, length: 17)))
    }

    @Test func selectionWithNoListLinesIsNoOp() {
        #expect(ListIndentation.indentOutcome(buffer: "a\nb", selection: NSRange(location: 0, length: 3)) == .noOp)
    }

    @Test func selectionOutdentsUpToOneUnitPerLine() {
        #expect(
            ListIndentation.outdentOutcome(buffer: "  - a\n\t- b\n- c", selection: NSRange(location: 0, length: 14))
                == .replace(range: NSRange(location: 0, length: 14), replacement: "- a\n- b\n- c", selection: NSRange(location: 0, length: 11)))
    }
```

Append to `ListIndentCommandTests` (uses that file's own harness):

```swift
    @Test func tabWithSelectionIndentsAllSelectedListLines() {
        let harness = makeHarness(buffer: "- a\n- b")
        harness.textView.setSelectedRange(NSRange(location: 0, length: 7))

        let handled = harness.send(#selector(NSResponder.insertTab(_:)))

        #expect(handled == true)
        #expect(harness.storage.string == "  - a\n  - b")
        #expect(harness.textView.selectedRange() == NSRange(location: 0, length: 11))
    }

    @Test func backtabWithSelectionOutdentsAllSelectedListLines() {
        let harness = makeHarness(buffer: "  - a\n  - b")
        harness.textView.setSelectedRange(NSRange(location: 0, length: 11))

        let handled = harness.send(#selector(NSResponder.insertBacktab(_:)))

        #expect(handled == true)
        #expect(harness.storage.string == "- a\n- b")
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path Packages/MarcdownStyling --filter ListIndentationTests`
Expected: FAIL (overload missing).

- [ ] **Step 3: Implement** (append to `ListIndentation`)

```swift
    /// Tab with a selection: indent every list/task line among the touched
    /// lines by two spaces. `.noOp` if none of them is a list line. The new
    /// selection covers the rewritten lines.
    public static func indentOutcome(buffer: String, selection: NSRange) -> TextEditOutcome {
        rewriteSelectedLines(buffer: buffer, selection: selection) { line in
            "  " + line
        }
    }

    /// Shift-Tab with a selection: strip one indent unit (two spaces, or one
    /// tab, or a lone space) from every list/task line among the touched lines.
    public static func outdentOutcome(buffer: String, selection: NSRange) -> TextEditOutcome {
        rewriteSelectedLines(buffer: buffer, selection: selection) { line in
            if line.hasPrefix("\t") { return String(line.dropFirst()) }
            if line.hasPrefix("  ") { return String(line.dropFirst(2)) }
            if line.hasPrefix(" ") { return String(line.dropFirst()) }
            return line
        }
    }

    private static func rewriteSelectedLines(
        buffer: String,
        selection: NSRange,
        _ transform: (String) -> String
    ) -> TextEditOutcome {
        let units = Array(buffer.utf16)
        guard selection.location >= 0, selection.location + selection.length <= units.count else { return .noOp }
        let (start, end) = BlockFormat.lineSpan(units: units, selection: selection)
        let lines = BlockFormat.splitLines(units: units, from: start, to: end).map { String(decoding: $0, as: UTF16.self) }
        let rebuilt = lines.map { isListOrTaskLine(line: $0) ? transform($0) : $0 }
        let replacement = rebuilt.joined(separator: "\n")
        let original = lines.joined(separator: "\n")
        guard replacement != original else { return .noOp }
        return .replace(
            range: NSRange(location: start, length: end - start),
            replacement: replacement,
            selection: NSRange(location: start, length: (replacement as NSString).length)
        )
    }
```

In `NoteEditorView.swift` `handleInsertTab`, replace the `// Selection-based indent (multiple lines) — TODO…` comment and `if selection.length > 0 { return false }` with:

```swift
            if selection.length > 0 {
                let handled = apply(
                    ListIndentation.indentOutcome(buffer: storage.string, selection: selection),
                    undoName: "Indent List Items",
                    in: textView
                )
                if handled { runRenumberPass(in: textView, around: textView.selectedRange().location) }
                return handled
            }
```

Same shape in `handleInsertBacktab` with `outdentOutcome` and `"Outdent List Items"`.

- [ ] **Step 4: Run both packages' tests, commit**

Run: `swift test --package-path Packages/MarcdownStyling && swift test --package-path Packages/MarcdownEditor`
Expected: PASS.

```bash
git add Packages/MarcdownStyling Packages/MarcdownEditor
git commit -m "feat: indent and outdent every list line in a selection"
```

---

### Task 11: Typed delimiter wraps the selection; pasted URL becomes a link

**Files:**
- Create: `Packages/MarcdownStyling/Sources/MarcdownStyling/SelectionWrap.swift`
- Modify: `Packages/MarcdownEditor/Sources/MarcdownEditor/NoteEditorView.swift` (`textView(_:shouldChangeTextIn:replacementString:)` ~748-796)
- Test: `Packages/MarcdownStyling/Tests/MarcdownStylingTests/SelectionWrapTests.swift`, `Packages/MarcdownEditor/Tests/MarcdownEditorTests/ShouldChangeTextTests.swift` (create)

**Interfaces:**
- Produces: `SelectionWrap.outcome(buffer: String, selection: NSRange, typed: String) -> TextEditOutcome`; `Coordinator.linePrefix(before cursor: Int, in buffer: String) -> String` (internal helper reused by Task 12).

- [ ] **Step 1: Write the failing tests**

```swift
// Packages/MarcdownStyling/Tests/MarcdownStylingTests/SelectionWrapTests.swift
import Foundation
import Testing

@testable import MarcdownStyling

@Suite("SelectionWrap")
struct SelectionWrapTests {
    @Test func asteriskWrapsAndKeepsSelectionOnText() {
        #expect(
            SelectionWrap.outcome(buffer: "hi there", selection: NSRange(location: 0, length: 2), typed: "*")
                == .replace(range: NSRange(location: 0, length: 2), replacement: "*hi*", selection: NSRange(location: 1, length: 2)))
    }

    @Test func bracketsAndParensUseTheirCloser() {
        #expect(
            SelectionWrap.outcome(buffer: "x", selection: NSRange(location: 0, length: 1), typed: "[")
                == .replace(range: NSRange(location: 0, length: 1), replacement: "[x]", selection: NSRange(location: 1, length: 1)))
        #expect(
            SelectionWrap.outcome(buffer: "x", selection: NSRange(location: 0, length: 1), typed: "(")
                == .replace(range: NSRange(location: 0, length: 1), replacement: "(x)", selection: NSRange(location: 1, length: 1)))
    }

    @Test func nonWrappingCharacterAndEmptySelectionAreNoOp() {
        #expect(SelectionWrap.outcome(buffer: "x", selection: NSRange(location: 0, length: 1), typed: "a") == .noOp)
        #expect(SelectionWrap.outcome(buffer: "x", selection: NSRange(location: 0, length: 0), typed: "*") == .noOp)
    }
}
```

```swift
// Packages/MarcdownEditor/Tests/MarcdownEditorTests/ShouldChangeTextTests.swift
import AppKit
import Testing

@testable import MarcdownEditor

@MainActor
@Suite("shouldChangeText interception")
struct ShouldChangeTextTests {
    @Test func typingAsteriskOverSelectionWraps() {
        let harness = EditorHarness.make(buffer: "hello")
        harness.select(0, 5)
        let allow = harness.coordinator.textView(harness.textView, shouldChangeTextIn: NSRange(location: 0, length: 5), replacementString: "*")
        #expect(allow == false)
        #expect(harness.storage.string == "*hello*")
        #expect(harness.textView.selectedRange() == NSRange(location: 1, length: 5))
    }

    @Test func pastingURLOverSelectionMakesLink() {
        let harness = EditorHarness.make(buffer: "docs here")
        harness.select(0, 4)
        let allow = harness.coordinator.textView(harness.textView, shouldChangeTextIn: NSRange(location: 0, length: 4), replacementString: "https://x.y/")
        #expect(allow == false)
        #expect(harness.storage.string == "[docs](https://x.y/) here")
    }

    @Test func pastingPlainTextOverSelectionIsLeftToAppKit() {
        let harness = EditorHarness.make(buffer: "docs")
        harness.select(0, 4)
        let allow = harness.coordinator.textView(harness.textView, shouldChangeTextIn: NSRange(location: 0, length: 4), replacementString: "plain text")
        #expect(allow == true)
        #expect(harness.storage.string == "docs")
    }

    @Test func checkboxExpansionStillWorks() {
        let harness = EditorHarness.make(buffer: "[]")
        harness.setCaret(2)
        let allow = harness.coordinator.textView(harness.textView, shouldChangeTextIn: NSRange(location: 2, length: 0), replacementString: " ")
        #expect(allow == false)
        #expect(harness.storage.string == "- [ ] ")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path Packages/MarcdownStyling --filter SelectionWrapTests`
Expected: FAIL.

- [ ] **Step 3: Implement**

```swift
// Packages/MarcdownStyling/Sources/MarcdownStyling/SelectionWrap.swift
import Foundation

/// Typing a markdown delimiter with text selected wraps the text instead of
/// replacing it (Bear/Notion behaviour). Pure, AppKit-free.
public enum SelectionWrap {
    public static func outcome(buffer: String, selection: NSRange, typed: String) -> TextEditOutcome {
        guard selection.length > 0 else { return .noOp }
        let closer: String
        switch typed {
        case "*", "_", "`", "~", "=", "\"": closer = typed
        case "[": closer = "]"
        case "(": closer = ")"
        default: return .noOp
        }
        let units = Array(buffer.utf16)
        guard selection.location >= 0, selection.location + selection.length <= units.count else { return .noOp }
        let inner = String(decoding: units[selection.location..<(selection.location + selection.length)], as: UTF16.self)
        return .replace(
            range: selection,
            replacement: typed + inner + closer,
            selection: NSRange(location: selection.location + 1, length: selection.length)
        )
    }
}
```

Rewrite the delegate method in `Coordinator`:

```swift
        public func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard let storage = textView.textStorage, let replacement = replacementString, !textView.hasMarkedText()
            else { return true }
            let buffer = storage.string

            if affectedCharRange.length > 0 {
                // Paste or drop of a URL over selected text → markdown link.
                if InlineFormat.isHTTPURL(replacement) {
                    let url = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
                    return !apply(InlineFormat.linkOutcome(buffer: buffer, selection: affectedCharRange, url: url), undoName: "Paste Link", in: textView)
                }
                // A typed delimiter wraps the selection. Dead-key layouts
                // deliver `` ` `` as a composition whose event characters
                // differ from the final string — those fall through.
                if (replacement as NSString).length == 1, isLiveKeystroke(for: replacement) {
                    return !apply(SelectionWrap.outcome(buffer: buffer, selection: affectedCharRange, typed: replacement), undoName: "Wrap Selection", in: textView)
                }
                return true
            }

            if replacement == " " {
                return allowSpaceOrExpandCheckbox(in: textView, storage: storage, cursor: affectedCharRange.location)
            }
            return true
        }

        /// True unless a keyDown is in flight whose characters differ from
        /// `replacement` (dead-key composition). No current event (tests,
        /// programmatic insertion) counts as live.
        private func isLiveKeystroke(for replacement: String) -> Bool {
            guard let event = NSApp.currentEvent, event.type == .keyDown else { return true }
            return event.characters == replacement
        }

        /// Content of the caret's line from its start up to `cursor`.
        func linePrefix(before cursor: Int, in buffer: String) -> String {
            let units = Array(buffer.utf16)
            guard cursor >= 0, cursor <= units.count else { return "" }
            var lineStart = cursor
            while lineStart > 0, units[lineStart - 1] != 0x0A {
                lineStart -= 1
            }
            return String(decoding: units[lineStart..<cursor], as: UTF16.self)
        }

        /// The pre-existing `[]` + space → `- [ ] ` expansion, unchanged in
        /// behaviour, moved out of the delegate method.
        private func allowSpaceOrExpandCheckbox(in textView: NSTextView, storage: NSTextStorage, cursor: Int) -> Bool {
            let prefix = linePrefix(before: cursor, in: storage.string)
            guard let expansion = CheckboxAutoExpansion.expansionOnTypingSpace(beforeCursorOnLine: prefix) else {
                return true
            }
            let lineStart = cursor - (prefix as NSString).length
            let prefixRange = NSRange(location: lineStart, length: cursor - lineStart)
            guard textView.shouldChangeText(in: prefixRange, replacementString: expansion) else { return false }
            textView.undoManager?.setActionName("Insert Checkbox")
            storage.replaceCharacters(in: prefixRange, with: expansion)
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: lineStart + (expansion as NSString).length, length: 0))
            return false
        }
```

- [ ] **Step 4: Run tests, build, verify ⌘V of a URL over a selection and typing `*` over a selection. Commit**

Run: `swift test --package-path Packages/MarcdownStyling && swift test --package-path Packages/MarcdownEditor`
Expected: PASS (including the existing `CheckboxAutoExpansion` editor tests).

```bash
git add Packages/MarcdownStyling Packages/MarcdownEditor
git commit -m "feat: wrap selection on typed delimiter and paste url as link"
```

---

### Task 12: Palette Markdown rows become commands; `/` opens the block menu

**Files:**
- Modify: `Packages/MarcdownEditor/Sources/MarcdownEditor/EditorCommand.swift` (notification names)
- Modify: `Packages/MarcdownEditor/Sources/MarcdownEditor/NoteEditorView.swift` (Coordinator observer, slash trigger, slash consumption)
- Modify: `App/Sources/CommandPalette.swift` (`PaletteSubMode`, six switches)
- Modify: `App/Sources/PanelRootView.swift` (`makePaletteActions`, `makeMarkdownReferenceRows` → `makeMarkdownRows`, `paletteActions`, `.onReceive`)
- Modify: `App/Tests/CommandPaletteSectionTests.swift`, `App/Tests/CommandPaletteActionContractTests.swift`, `App/Tests/CommandPaletteSubModeTests.swift`
- Test: `Packages/MarcdownEditor/Tests/MarcdownEditorTests/SlashMenuTests.swift` (create)

**Interfaces:**
- Produces (public, MarcdownEditor): `Notification.Name.marcdownEditorPerformCommand`, `Notification.Name.marcdownEditorSlashMenu`, `EditorCommandNotification.key = "command"`; `PaletteSubMode.blockInsert`; `makeMarkdownRows(setOverlay:perform:) -> [PaletteAction]`; `makePaletteActions(setOverlay:newNote:triggerFind:duplicate:delete:prev:next:perform:)`.
- Consumes: `Coordinator.perform`, `linePrefix(before:in:)`.

- [ ] **Step 1: Write the failing editor test**

```swift
// Packages/MarcdownEditor/Tests/MarcdownEditorTests/SlashMenuTests.swift
import AppKit
import Testing

@testable import MarcdownEditor

@MainActor
@Suite("Slash menu plumbing")
struct SlashMenuTests {
    @Test func commandNotificationIsPerformed() {
        let harness = EditorHarness.make(buffer: "hi")
        harness.select(0, 2)
        NotificationCenter.default.post(
            name: .marcdownEditorPerformCommand,
            object: nil,
            userInfo: [EditorCommandNotification.key: EditorCommand.bold]
        )
        #expect(harness.storage.string == "**hi**")
    }

    @Test func loneSlashIsConsumedByABlockCommand() {
        let harness = EditorHarness.make(buffer: "a\n/")
        harness.setCaret(3)
        harness.coordinator.perform(.heading(2))
        #expect(harness.storage.string == "a\n## ")
        #expect(harness.textView.selectedRange() == NSRange(location: 5, length: 0))
    }

    @Test func slashInsideTextIsKept() {
        let harness = EditorHarness.make(buffer: "a/b")
        harness.setCaret(3)
        harness.coordinator.perform(.bold)
        #expect(harness.storage.string == "a/b****")
    }

    @Test func slashOnEmptyLineIsInsertedAndSignals() {
        let harness = EditorHarness.make(buffer: "")
        harness.setCaret(0)
        let allow = harness.coordinator.textView(harness.textView, shouldChangeTextIn: NSRange(location: 0, length: 0), replacementString: "/")
        #expect(allow == true)
        #expect(harness.coordinator.didRequestSlashMenu == true)
    }

    @Test func slashAfterTextDoesNotSignal() {
        let harness = EditorHarness.make(buffer: "ab")
        harness.setCaret(2)
        _ = harness.coordinator.textView(harness.textView, shouldChangeTextIn: NSRange(location: 2, length: 0), replacementString: "/")
        #expect(harness.coordinator.didRequestSlashMenu == false)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path Packages/MarcdownEditor --filter SlashMenuTests`
Expected: FAIL (names undefined).

- [ ] **Step 3: Editor side**

Append to `EditorCommand.swift`:

```swift
/// Keys used in the `userInfo` of `.marcdownEditorPerformCommand`.
public enum EditorCommandNotification {
    public static let key = "command"
}

extension Notification.Name {
    /// Posted by the App (palette rows, `/` menu) with
    /// `userInfo[EditorCommandNotification.key] = EditorCommand`. The editor's
    /// coordinator performs it on the current selection.
    public static let marcdownEditorPerformCommand = Notification.Name("MarcdownEditorPerformCommand")

    /// Posted by the editor when the user types `/` at the start of a line.
    /// The App opens the command palette in its block-insert sub-mode.
    public static let marcdownEditorSlashMenu = Notification.Name("MarcdownEditorSlashMenu")
}
```

In `Coordinator`:

```swift
        private nonisolated(unsafe) var commandObserver: NSObjectProtocol?
        /// Set when the last `shouldChangeText` posted the slash-menu
        /// notification. Read by tests; the App reacts to the notification.
        private(set) var didRequestSlashMenu = false
```

In `init`, after the focus observer:

```swift
            commandObserver = NotificationCenter.default.addObserver(
                forName: .marcdownEditorPerformCommand,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let command = notification.userInfo?[EditorCommandNotification.key] as? EditorCommand
                MainActor.assumeIsolated {
                    guard let self, let command else { return }
                    self.perform(command)
                }
            }
```

In `deinit`, also remove `commandObserver`. In `perform`, right after the `hasMarkedText` guard, insert `consumeSlashTrigger(in: textView)` and re-read `buffer`/`selection` after it (move the two `let`s below the call). Add:

```swift
        /// If the caret line is exactly `/` (after optional indent) the user
        /// got here through the slash menu: delete the slash so the block
        /// command lands on a clean line. Stateless on purpose — Escape
        /// leaves the `/` in place like Notion, and any other line is untouched.
        private func consumeSlashTrigger(in textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let cursor = textView.selectedRange().location
            let prefix = linePrefix(before: cursor, in: storage.string)
            let trimmed = prefix.drop(while: { $0 == " " || $0 == "\t" })
            guard trimmed == "/" else { return }
            let units = Array(storage.string.utf16)
            var lineEnd = cursor
            while lineEnd < units.count, units[lineEnd] != 0x0A { lineEnd += 1 }
            guard lineEnd == cursor else { return }
            let slashRange = NSRange(location: cursor - 1, length: 1)
            guard textView.shouldChangeText(in: slashRange, replacementString: "") else { return }
            storage.replaceCharacters(in: slashRange, with: "")
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: cursor - 1, length: 0))
        }
```

In the delegate method, before the final `return true`:

```swift
            if replacement == "/" {
                let prefix = linePrefix(before: affectedCharRange.location, in: buffer)
                didRequestSlashMenu = prefix.allSatisfy { $0 == " " || $0 == "\t" }
                if didRequestSlashMenu {
                    // Deferred one tick so the overlay state change happens
                    // outside this text-change transaction.
                    Task { @MainActor in
                        NotificationCenter.default.post(name: .marcdownEditorSlashMenu, object: nil)
                    }
                }
            }
```

- [ ] **Step 4: Run editor tests**

Run: `swift test --package-path Packages/MarcdownEditor`
Expected: PASS.

- [ ] **Step 5: Update the App tests first**

`CommandPaletteSubModeTests.swift` add:

```swift
    @Test("⎋ from blockInsert dismisses instead of popping to root")
    func escapeFromBlockInsertDismisses() {
        #expect(paletteSubModeAfterEscape(current: .blockInsert) == nil)
    }
```

`CommandPaletteSectionTests.swift`: replace every `makeMarkdownReferenceRows()` with `makeMarkdownRows(setOverlay: { _ in }, perform: { _ in })`; add `perform: { _ in }` as the last argument of both `makePaletteActions` calls; change the count test to `#expect(rows.count == 15)`; replace the `markdownReferenceRowsAreReferenceKind` test with:

```swift
    @Test("Markdown rows are leaf commands")
    func markdownRowsAreLeafKind() {
        let rows = makeMarkdownRows(setOverlay: { _ in }, perform: { _ in })
        #expect(rows.allSatisfy { $0.handler != nil })
    }
```

titles test expects `["Bold", "Italic", "Heading 1", "Heading 2", "Heading 3", "Bullet list", "Numbered list", "Task list", "Quote", "Inline code", "Code block", "Link", "Strikethrough", "Highlight", "Divider"]`; shortcut-chip test expects `["⌘B", "⌘I", "⌥⌘1", "⌥⌘2", "⌥⌘3", "⇧⌘L", "⇧⌘N", "⇧⌘T", "⇧⌘B", "⌘E", "", "⇧⌘K", "⇧⌘X", "⇧⌘H", ""]`; `markdownIds.count == 15`.

`CommandPaletteActionContractTests.swift`: add `perform: { observed.performed.append($0) }` to `makeActions`, add `var performed: [EditorCommand] = []` to `Observed` (needs `import MarcdownEditor`), and replace the two reference-row tests with:

```swift
    @Test("Markdown rows dismiss the overlay and perform their command")
    func markdownRowsDismissAndPerform() {
        let observed = Observed()
        observed.overlay = .palette
        let actions = makeActions(capturing: observed)

        handler(for: "md-bold", in: actions)?()

        #expect(observed.overlay == .none)
        #expect(observed.performed == [.bold])
    }

    @Test("Every Markdown row has a handler")
    func markdownRowsHaveHandlers() {
        let observed = Observed()
        let actions = makeActions(capturing: observed)
        let rows = actions.filter { $0.section == .markdown }
        #expect(rows.count == 15)
        #expect(rows.allSatisfy { $0.handler != nil })
    }
```

- [ ] **Step 6: App implementation**

`CommandPalette.swift`:

```swift
enum PaletteSubMode: Equatable, Sendable {
    case root
    case exportFormat
    /// Opened by typing `/` at the start of a line: only the Markdown rows.
    case blockInsert
}
```

`paletteSubModeAfterEscape`: `case .blockInsert: return nil`. `displayedActions`: `case .blockInsert: return actions.filter { $0.section == .markdown }`. `searchPlaceholder`: `"Insert block"`. `searchLeadingIcon`: `"slash.circle"`. `emptyStateCopy`: `"No matching blocks"`. `searchAccessibilityLabel`: `"Insert block, \(count) result\(plural)"`.

`PanelRootView.swift` — `makePaletteActions` gains a trailing parameter `perform: @escaping @MainActor (EditorCommand) -> Void` and ends with `return commands + makeMarkdownRows(setOverlay: setOverlay, perform: perform)`. Replace `makeMarkdownReferenceRows` and `markdownReference` with:

```swift
/// The palette's Markdown section: one leaf per `EditorCommand`, chip shows
/// the chord. Every handler owns its overlay state (dismiss, then perform),
/// per the contract locked in `CommandPaletteActionContractTests`.
@MainActor
func makeMarkdownRows(
    setOverlay: @escaping @MainActor (ActiveOverlay) -> Void,
    perform: @escaping @MainActor (EditorCommand) -> Void
) -> [PaletteAction] {
    let rows: [(id: String, title: String, icon: String, chord: String, command: EditorCommand)] = [
        ("md-bold", "Bold", "bold", "⌘B", .bold),
        ("md-italic", "Italic", "italic", "⌘I", .italic),
        ("md-heading-1", "Heading 1", "number", "⌥⌘1", .heading(1)),
        ("md-heading-2", "Heading 2", "number", "⌥⌘2", .heading(2)),
        ("md-heading-3", "Heading 3", "number", "⌥⌘3", .heading(3)),
        ("md-list", "Bullet list", "list.bullet", "⇧⌘L", .bulletList),
        ("md-ordered-list", "Numbered list", "list.number", "⇧⌘N", .orderedList),
        ("md-task", "Task list", "checklist", "⇧⌘T", .taskList),
        ("md-quote", "Quote", "text.quote", "⇧⌘B", .quote),
        ("md-inline-code", "Inline code", "chevron.left.forwardslash.chevron.right", "⌘E", .inlineCode),
        ("md-code-block", "Code block", "curlybraces", "", .codeBlock),
        ("md-link", "Link", "link", "⇧⌘K", .link),
        ("md-strikethrough", "Strikethrough", "strikethrough", "⇧⌘X", .strikethrough),
        ("md-highlight", "Highlight", "highlighter", "⇧⌘H", .highlight),
        ("md-divider", "Divider", "minus", "", .divider),
    ]
    return rows.map { row in
        PaletteAction(id: row.id, title: row.title, icon: row.icon, shortcutLabel: row.chord, section: .markdown) {
            setOverlay(.none)
            perform(row.command)
        }
    }
}
```

`paletteActions` passes:

```swift
            perform: { command in
                NotificationCenter.default.post(
                    name: .marcdownEditorPerformCommand,
                    object: nil,
                    userInfo: [EditorCommandNotification.key: command]
                )
            }
```

Add to the `body` modifier chain:

```swift
        .onReceive(NotificationCenter.default.publisher(for: .marcdownEditorSlashMenu)) { _ in
            guard activeOverlay == .none else { return }
            paletteSubMode = .blockInsert
            withAnimation(.easeOut(duration: 0.15)) { activeOverlay = .palette }
        }
```

`PaletteActionKind.reference` stays (still used by section tests' constructors); nothing produces it any more.

- [ ] **Step 7: Run App tests and build**

Run: `xcodegen generate && xcodebuild -scheme Marcdown -destination 'platform=macOS' test`
Expected: PASS. Manual: type `/` on an empty line → palette opens with Markdown rows only, typing filters, ⏎ on "Heading 1" → line becomes `# ` with the slash gone; Esc → `/` stays; ⌘K → "Bold" row wraps the selection.

- [ ] **Step 8: Commit**

```bash
git add App Packages/MarcdownEditor
git commit -m "feat(palette): markdown rows run editor commands and slash opens block menu"
```

---

### Task 13: Shift-arrow selects across a concealed run in one step

**Files:**
- Modify: `Packages/MarcdownEditor/Sources/MarcdownEditor/NoteEditorView.swift` (`doCommandBy` ~285-290, `handleArrow` ~369)
- Test: `Packages/MarcdownEditor/Tests/MarcdownEditorTests/ConcealedRunNavigationTests.swift` (append)

- [ ] **Step 1: Write the failing tests** (append, using that file's own harness)

```swift
    @Test func shiftRightExtendsOverConcealedClosingLinkSyntax() {
        let harness = makeHarness(buffer: "[a](b) x")
        harness.textView.setSelectedRange(NSRange(location: 1, length: 1))

        let handled = harness.send(#selector(NSResponder.moveRightAndModifySelection(_:)))

        #expect(handled == true)
        #expect(harness.textView.selectedRange() == NSRange(location: 1, length: 5))
    }

    @Test func shiftLeftExtendsOverConcealedOpeningDelimiter() {
        let harness = makeHarness(buffer: "**foo**")
        harness.textView.setSelectedRange(NSRange(location: 2, length: 3))

        let handled = harness.send(#selector(NSResponder.moveLeftAndModifySelection(_:)))

        #expect(handled == true)
        #expect(harness.textView.selectedRange() == NSRange(location: 0, length: 5))
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path Packages/MarcdownEditor --filter ConcealedRunNavigationTests`
Expected: FAIL (`handled == false`).

- [ ] **Step 3: Implement**

Route the two selectors in `doCommandBy`:

```swift
            if selector == #selector(NSResponder.moveLeftAndModifySelection(_:)) {
                return handleArrow(in: textView, direction: .left, extend: true)
            }
            if selector == #selector(NSResponder.moveRightAndModifySelection(_:)) {
                return handleArrow(in: textView, direction: .right, extend: true)
            }
```

Change `handleArrow` to `handleArrow(in textView: NSTextView, direction: ArrowDirection, extend: Bool = false)`; replace `if selection.length > 0 { return false }` with `if selection.length > 0, !extend { return false }`; the probe index becomes the active end (`selection.location + selection.length` for right, `selection.location` for left, matching the anchor assumption in `handleMoveToBeginningOfLine`); and each `textView.setSelectedRange(NSRange(location: target, length: 0))` becomes:

```swift
                if extend {
                    textView.setSelectedRange(NSRange(location: selection.location, length: target - selection.location))
                } else {
                    textView.setSelectedRange(NSRange(location: target, length: 0))
                }
```

for `.right`, and for `.left`:

```swift
                if extend {
                    textView.setSelectedRange(NSRange(location: target, length: selection.location + selection.length - target))
                } else {
                    textView.setSelectedRange(NSRange(location: target, length: 0))
                }
```

- [ ] **Step 4: Run tests, commit**

Run: `swift test --package-path Packages/MarcdownEditor`
Expected: PASS.

```bash
git add Packages/MarcdownEditor
git commit -m "feat: shift-arrow jumps concealed runs"
```

---

### Task 14: Docs

**Files:**
- Modify: `README.md` (Keyboard shortcuts ~169-190, Features ~30-38)
- Modify: `DESIGN.md` (editor font line ~93-95)
- Modify: `CLAUDE.md` (Tests section)
- Create: `docs/superpowers/plans/2026-09-07-rich-editor.md` (this file, if not already committed in Task 1)

- [ ] **Step 1: README** — add a "Formatting (editor focused)" table under Keyboard shortcuts:

```markdown
### Formatting (when the editor has focus)

| Shortcut                   | Action                                  |
| -------------------------- | --------------------------------------- |
| **Cmd+B** / **Cmd+I**      | Bold / italic (toggle around selection) |
| **Cmd+E**                  | Inline code                             |
| **Cmd+Shift+X**            | Strikethrough                           |
| **Cmd+Shift+H**            | Highlight (`==text==`)                  |
| **Cmd+Shift+K**            | Link (uses a URL on the clipboard)      |
| **Cmd+Opt+1** … **Cmd+Opt+6** | Heading 1–6; **Cmd+Opt+0** paragraph |
| **Cmd+Shift+L** / **N** / **T** | Bullet / numbered / task list      |
| **Cmd+Shift+B**            | Quote                                   |
| **Tab** / **Shift+Tab**    | Indent / outdent list lines (selection aware) |
| **/** at line start        | Block menu (same rows as ⌘K → Markdown) |

Typing `*`, `_`, `` ` ``, `~`, `=`, `[` or `(` with text selected wraps it; pasting a URL over selected text makes a link.
```

Also update the Features bullets to mention highlight, drawn rules/quote bars, and the slash menu; fix the stale `cd /Users/luctst/marcdowndev` (line ~82) to `mardowndev`.

- [ ] **Step 2: DESIGN.md** — replace the "editor font is `NSFont.systemFont(ofSize: 14)`" sentence with the truth: Avenir Next Regular 15pt (`MarkdownStyler.swift`), headings derived from it via `NSFontManager` bold at the +10/+7/+4/+2/+1/0 scale, `lineHeightMultiple` 1.2.

- [ ] **Step 3: CLAUDE.md** — add `swift test --package-path Packages/MarcdownEditor` under Tests with the note "(command routing, formatting commands)".

- [ ] **Step 4: Commit**

```bash
git add README.md DESIGN.md CLAUDE.md docs/superpowers/plans/2026-09-07-rich-editor.md
git commit -m "docs: formatting shortcuts, editor typography truth, editor test command"
```

---

## Verification (end-to-end)

1. `swift test --package-path Packages/MarcdownStyling`, `swift test --package-path Packages/MarcdownEditor`, `swift test --package-path Packages/MarcdownCore` — all green.
2. `xcodegen generate && xcodebuild -scheme Marcdown -destination 'platform=macOS' test` — App tests green (palette contracts updated in Task 12).
3. `xcrun swift-format lint --strict --recursive --configuration .swift-format App/ Packages/MarcdownCore/Sources Packages/MarcdownCore/Tests Packages/MarcdownStyling/Sources Packages/MarcdownStyling/Tests Packages/MarcdownEditor/Sources Packages/MarcdownEditor/Tests` — clean.
4. Manual QA in the running app (⌘⇧Space):
   - Paste the sample below, move the caret through every line: markers reveal only on the caret line; nothing on disk changes (`cat ~/marcdown/<note>.md`).
   - Wrap a long bullet: continuation aligns under the text. Quote shows a bar, `---` shows a rule, ```` ```swift ```` shows a container with a `swift` badge and no fences, `==x==` is yellow.
   - Select a word: ⌘B, ⌘B, ⌘I, ⌘E, ⇧⌘X, ⇧⌘H each toggle. Type `*` over a selection. Copy a URL, select text, ⌘V.
   - ⌘⌥2 on a list line → `## `; ⇧⌘N over three selected lines → numbered; Tab over the selection indents all.
   - `/` on an empty line → palette in block mode; ⏎ on Quote → `> `; Esc from the menu leaves `/`.
   - Open ⌘K, press ⌘B: nothing happens in the editor (chords are dead while an overlay is open).
   - Undo (⌘Z) reverts each command in one step.
   - Check a CJK input source: typing with IME composition still works (all interceptions bail on `hasMarkedText`).

Sample note:

```
# Title
Body with **bold**, *italic*, `code`, ~~gone~~, ==hi== and a [link](https://example.com).

> A quote that is long enough to wrap onto a second visual line inside the panel width.
> > nested

- item one that is long enough to wrap onto a second visual line inside the panel width
  - nested
- [ ] task

1. one
2. two

---

```swift
let x = 1
```
```

## Deferred (follow-up plan)

Inline image previews and drag-and-drop, real table rendering, syntax highlighting inside code blocks, a floating selection toolbar, wiki links and tags, a table of contents. None of these block the Bear-feel this plan delivers, and each needs its own design (attachments vs. draw-in-gap for images; `NSTextTable` is incompatible with the never-edit-characters invariant).

## Self-review notes

- Spec coverage: every user-chosen scope item (rendering ×6, commands ×7, slash menu, multi-line indent, wrap-on-type, paste-URL) maps to Tasks 1–13; docs in 14.
- Type consistency: `TextEditOutcome` (Task 8) is the only outcome type used by Tasks 9–12; `ParagraphStyling.mutate` (Task 1) is used by Tasks 2–4 and 6; `EditorHarness.make` (Task 8) by Tasks 9, 11, 12; `linePrefix(before:in:)` (Task 11) by Task 12; `BlockFormat.lineSpan`/`splitLines` (Task 9) by Task 10.
- Risks called out in code: chord routing relies on disjoint chord sets with the SwiftUI layer (Task 8 comment); `OrderedListRenumber` anchors on one run (Task 9 Step 7 fallback); highlight skips monospaced runs including tables (Task 5 ponytail comment); slash menu keystrokes typed before the palette focuses land in the editor (known ceiling).
