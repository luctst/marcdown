import AppKit
import Foundation
import Testing

@testable import MarcdownStyling

/// Tests for fenced code block (triple-backtick) styling applied by
/// `MarkdownStyler` / `StyleWalker`.
///
/// The contract under test:
///   - Fence marker lines (` ``` ` / ` ```swift `) are clear-painted
///     monospaced glyphs (not `.marcdownConcealed`), tagged with
///     `.marcdownCodeFence = true`.
///   - Code body lines get a monospaced font + a `.backgroundColor` fill.
///   - The full block range (fences + body) is tagged with
///     `.marcdownCodeBlock = true`.
///   - `StylingTheme.system.codeBackground` ships with a GitHub-style alpha
///     (>= 0.08) so the block is visibly distinct from prose.
///   - Restyle never mutates `storage.string`.
///
/// These tests target the storage attribute boundary — the same boundary the
/// layout delegate and the editor consume.
@MainActor
@Suite("FencedCodeBlock")
struct FencedCodeBlockTests {

    // MARK: - Helpers

    private func styledStorage(_ source: String) -> NSTextStorage {
        let styler = MarkdownStyler()
        let storage = NSTextStorage(string: source)
        styler.restyle(storage: storage, source: source)
        return storage
    }

    private func isMonospaced(_ font: NSFont?) -> Bool {
        font?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true
    }

    // MARK: - Fence marker line styling

    /// The opening ` ``` ` line is rendered with clear glyphs so the user can
    /// still place the cursor on it and edit, but the syntax characters
    /// disappear visually. We assert on every character of that line (offsets
    /// 0..<3 in the canonical source).
    @Test func openingFenceCharsAreClearPainted() {
        let source = "```\nlet x = 1\nlet y = 2\n```"
        let storage = styledStorage(source)

        for offset in 0..<3 {
            let color = storage.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? NSColor
            #expect(color == NSColor.clear, "Opening fence char at \(offset) not clear-painted")
        }
    }

    /// Fence chars must NOT use `.marcdownConcealed` — that attribute
    /// collapses glyph advance via `.null`, which would drag the caret onto
    /// the previous line while the user is typing the fence. The clear-paint
    /// strategy preserves advance.
    @Test func openingFenceCharsAreNotMarcdownConcealed() {
        let source = "```\nlet x = 1\nlet y = 2\n```"
        let storage = styledStorage(source)

        for offset in 0..<3 {
            let value = storage.attribute(.marcdownConcealed, at: offset, effectiveRange: nil) as? Bool
            #expect(value != true, "Fence char at \(offset) was marked .marcdownConcealed")
        }
    }

    @Test func openingFenceCharsAreMonospaced() {
        let source = "```\nlet x = 1\nlet y = 2\n```"
        let storage = styledStorage(source)

        for offset in 0..<3 {
            let font = storage.attribute(.font, at: offset, effectiveRange: nil) as? NSFont
            #expect(isMonospaced(font), "Opening fence char at \(offset) not monospaced")
        }
    }

    @Test func openingFenceIsTaggedAsCodeFence() {
        let source = "```\nlet x = 1\nlet y = 2\n```"
        let storage = styledStorage(source)

        for offset in 0..<3 {
            let value = storage.attribute(.marcdownCodeFence, at: offset, effectiveRange: nil) as? Bool
            #expect(value == true, "Opening fence char at \(offset) missing .marcdownCodeFence")
        }
    }

    /// A language-tagged opening fence (` ```swift `) — every char on the
    /// fence line (the backticks AND the language tag) is part of the marker
    /// and gets the same treatment.
    @Test func languageTaggedOpeningFenceIsClearPaintedAndTagged() {
        let source = "```swift\nlet x = 1\n```"
        let storage = styledStorage(source)

        // "```swift" spans offsets 0..<8.
        for offset in 0..<8 {
            let color = storage.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? NSColor
            #expect(color == NSColor.clear, "Lang-tag fence char at \(offset) not clear-painted")

            let fence = storage.attribute(.marcdownCodeFence, at: offset, effectiveRange: nil) as? Bool
            #expect(fence == true, "Lang-tag fence char at \(offset) missing .marcdownCodeFence")
        }
    }

    /// The closing fence gets the same treatment as the opening fence: clear
    /// glyphs + the `.marcdownCodeFence` tag. We locate it by string range
    /// rather than hand-computed offsets to keep the test resilient to
    /// trailing newline conventions.
    @Test func closingFenceIsClearPaintedAndTagged() {
        let source = "```\nlet x = 1\nlet y = 2\n```"
        let storage = styledStorage(source)

        let ns = source as NSString
        let closingRange = ns.range(of: "```", options: .backwards)
        #expect(closingRange.location != NSNotFound)

        for offset in closingRange.location..<(closingRange.location + closingRange.length) {
            let color = storage.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? NSColor
            #expect(color == NSColor.clear, "Closing fence char at \(offset) not clear-painted")

            let fence = storage.attribute(.marcdownCodeFence, at: offset, effectiveRange: nil) as? Bool
            #expect(fence == true, "Closing fence char at \(offset) missing .marcdownCodeFence")
        }
    }

    // MARK: - Code body styling

    @Test func codeBodyCharsAreMonospaced() {
        let source = "```\nlet x = 1\nlet y = 2\n```"
        let storage = styledStorage(source)

        // Sample the "x" inside "let x = 1" on the first body line.
        let ns = source as NSString
        let bodyRange = ns.range(of: "let x = 1")
        #expect(bodyRange.location != NSNotFound)

        let font = storage.attribute(.font, at: bodyRange.location, effectiveRange: nil) as? NSFont
        #expect(isMonospaced(font), "Body char is not monospaced")
    }

    @Test func codeBodyCharsHaveBackgroundColor() {
        let source = "```\nlet x = 1\nlet y = 2\n```"
        let storage = styledStorage(source)

        let ns = source as NSString
        let bodyRange = ns.range(of: "let x = 1")
        #expect(bodyRange.location != NSNotFound)

        let bg = storage.attribute(.backgroundColor, at: bodyRange.location, effectiveRange: nil) as? NSColor
        #expect(bg != nil, "Body char has no .backgroundColor")
    }

    // MARK: - Block-level tag

    @Test func codeBodyIsTaggedAsCodeBlock() {
        let source = "```\nlet x = 1\nlet y = 2\n```"
        let storage = styledStorage(source)

        let ns = source as NSString
        let bodyRange = ns.range(of: "let x = 1")
        #expect(bodyRange.location != NSNotFound)

        let value = storage.attribute(.marcdownCodeBlock, at: bodyRange.location, effectiveRange: nil) as? Bool
        #expect(value == true, "Body char missing .marcdownCodeBlock")
    }

    /// Two adjacent fenced blocks separated by a blank line — both should
    /// independently get `.marcdownCodeBlock = true` on their body chars.
    /// This guards against an implementation that only tags the first block
    /// or that accidentally extends a single tag across the blank-line gap.
    @Test func adjacentCodeBlocksAreBothTagged() {
        let source = "```\nA\n```\n\n```\nB\n```"
        let storage = styledStorage(source)

        let ns = source as NSString
        let firstBody = ns.range(of: "A")
        let secondBody = ns.range(of: "B")
        #expect(firstBody.location != NSNotFound)
        #expect(secondBody.location != NSNotFound)

        let firstTag = storage.attribute(.marcdownCodeBlock, at: firstBody.location, effectiveRange: nil) as? Bool
        let secondTag = storage.attribute(.marcdownCodeBlock, at: secondBody.location, effectiveRange: nil) as? Bool

        #expect(firstTag == true, "First block body not tagged .marcdownCodeBlock")
        #expect(secondTag == true, "Second block body not tagged .marcdownCodeBlock")
    }

    /// Inline code (` `foo` ` on a prose line) is a different beast — it gets
    /// `.marcdownConcealed` on the backticks but must NOT receive the
    /// block-level `.marcdownCodeBlock` tag. Otherwise the editor would
    /// treat inline backticks as a full block (background fill across the
    /// entire prose line, etc).
    @Test func inlineCodeIsNotTaggedAsCodeBlock() {
        let source = "Some `inline` text"
        let storage = styledStorage(source)

        let ns = source as NSString
        let inlineRange = ns.range(of: "inline")
        #expect(inlineRange.location != NSNotFound)

        let value = storage.attribute(.marcdownCodeBlock, at: inlineRange.location, effectiveRange: nil) as? Bool
        #expect(value != true, "Inline code char was tagged .marcdownCodeBlock")
    }

    // MARK: - Theme

    /// The previous `codeBackground` was `NSColor(white: 0.5, alpha: 0.12)`
    /// against a gray midpoint — ~6% effective contrast. GitHub's block uses
    /// roughly 8% on light and ~12% on dark. We assert the alpha component
    /// alone is >= 0.08 so the block reads as a distinct surface in both
    /// appearances. Resolved against generic RGB to handle either a plain or
    /// dynamic color descriptor.
    @Test func codeBackgroundHasGithubStyleAlpha() {
        let theme = StylingTheme.system
        let resolved = theme.codeBackground.usingColorSpace(.genericRGB) ?? theme.codeBackground
        #expect(resolved.alphaComponent >= 0.08, "codeBackground alpha is \(resolved.alphaComponent), expected >= 0.08")
    }

    // MARK: - Disk invariant

    @Test func restyleDoesNotMutateStorageString() {
        let sources = [
            "```\nlet x = 1\nlet y = 2\n```",
            "```swift\nlet x = 1\n```",
            "```\nA\n```\n\n```\nB\n```",
            "prose before\n```\ncode\n```\nprose after",
        ]
        let styler = MarkdownStyler()
        for source in sources {
            let storage = NSTextStorage(string: source)
            styler.restyle(storage: storage, source: source)
            #expect(storage.string == source, "Storage mutated for: \(source)")
        }
    }

    // MARK: - Unclosed fence regression

    @Test func unclosedFenceBodyIsNotClearPainted() {
        // An unclosed block: the parser extends the CodeBlock to end-of-doc.
        // Body lines must remain visible — not clear-painted — despite having
        // no closing fence.
        let source = "```\nhello\nworld\n\n\n"
        let storage = styledStorage(source)
        let ns = source as NSString

        let helloRange = ns.range(of: "hello")
        let helloColor = storage.attribute(.foregroundColor, at: helloRange.location, effectiveRange: nil) as? NSColor
        #expect(helloColor != NSColor.clear, "\"hello\" must not be clear-painted in an unclosed block")

        let worldRange = ns.range(of: "world")
        let worldColor = storage.attribute(.foregroundColor, at: worldRange.location, effectiveRange: nil) as? NSColor
        #expect(worldColor != NSColor.clear, "\"world\" must not be clear-painted in an unclosed block")
    }

    @Test func unclosedFenceBodyIsNotTaggedAsFenceLine() {
        let source = "```\nhello\nworld\n\n\n"
        let storage = styledStorage(source)
        let ns = source as NSString

        let helloRange = ns.range(of: "hello")
        let fenceVal = storage.attribute(.marcdownCodeFence, at: helloRange.location, effectiveRange: nil) as? Bool
        #expect(fenceVal != true, "\"hello\" must not be tagged as a fence marker in an unclosed block")

        let worldRange = ns.range(of: "world")
        let worldFence = storage.attribute(.marcdownCodeFence, at: worldRange.location, effectiveRange: nil) as? Bool
        #expect(worldFence != true, "\"world\" must not be tagged as a fence marker in an unclosed block")
    }

    @Test func unclosedFenceAfterMultipleEntersBodyIsVisible() {
        // Reproduces the specific user-reported bug: type ```, content, then
        // press Enter many times → content becomes invisible.
        let source = "```\na\n\n\n\n\n"
        let storage = styledStorage(source)
        let ns = source as NSString

        let aRange = ns.range(of: "a")
        let color = storage.attribute(.foregroundColor, at: aRange.location, effectiveRange: nil) as? NSColor
        #expect(color != NSColor.clear, "\"a\" must be visible after multiple Enter presses in an unclosed block")

        let fenceVal = storage.attribute(.marcdownCodeFence, at: aRange.location, effectiveRange: nil) as? Bool
        #expect(fenceVal != true)
    }
}
