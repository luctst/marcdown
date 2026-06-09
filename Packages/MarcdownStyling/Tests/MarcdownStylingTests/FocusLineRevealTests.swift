import AppKit
import Foundation
import Testing

@testable import MarcdownStyling

// MARK: - Expected production API (to be implemented by guy)
//
// Focus-line reveal is the headline feature (Spec §3, Thomas §1). When the
// cursor sits on a line, all `.marcdownConcealed` ranges on that line must
// be revealed: concealment cleared and the dim foreground color applied so
// the syntax becomes visible (but visually dim) instead of zero-width.
//
// The styler must accept a "current focus line" parameter and apply the
// reveal during its restyle pass:
//
//   public final class MarkdownStyler {
//       public func restyle(
//           storage: NSTextStorage,
//           source: String,
//           focusLine: FocusLine? = nil
//       )
//   }
//
//   public struct FocusLine: Sendable, Equatable {
//       /// UTF-16 offset of the start of the focused line in `source`.
//       public let lineStart: Int
//       /// UTF-16 length of the focused line content (excluding any trailing `\n`).
//       public let lineLength: Int
//       public init(lineStart: Int, lineLength: Int)
//   }
//
// Reveal contract:
// - All characters in the focus line that previously carried
//   `.marcdownConcealed = true` have the attribute removed.
// - Those same characters get `.foregroundColor = theme.dim` (so they appear
//   as dim text rather than zero-width glyphs).
// - Non-focus lines retain their existing conceal/clear-paint treatment.
// - Block markers that are already dim (blockquote `>`, fence ```) are not
//   affected by reveal (they are not concealed; reveal is a no-op for them).
// - Bullet / ordered / task markers (clear-painted, not concealed) ALSO
//   reveal when the cursor sits on them: foreground flips from `.clear`
//   to `theme.dim` and the `.marcdownListMarker` / `.marcdownCheckbox`
//   tags are REMOVED so the layout manager skips its overlay.
//
// The test selection-extension case below is the "either end of selection"
// rule from §3.1; for now a single focus line is enough — guy can extend to
// a selection range later.

@MainActor
@Suite("Focus-line reveal")
struct FocusLineRevealTests {

    private func restyle(_ source: String, focus: FocusLine? = nil) -> NSTextStorage {
        let styler = MarkdownStyler()
        let storage = NSTextStorage(string: source)
        styler.restyle(storage: storage, source: source, focusLine: focus)
        return storage
    }

    // MARK: - Inline conceal: bold delimiters

    @Test func boldDelimitersConcealedWhenCursorOnDifferentLine() {
        // No focus → existing behaviour: `**` concealed.
        let storage = restyle("**foo**")
        let leftConcealed = storage.attribute(.marcdownConcealed, at: 0, effectiveRange: nil) as? Bool
        let rightConcealed = storage.attribute(.marcdownConcealed, at: 5, effectiveRange: nil) as? Bool
        #expect(leftConcealed == true)
        #expect(rightConcealed == true)
    }

    @Test func boldDelimitersRevealedWhenCursorOnSameLine() {
        // Focus on the only line — `**` reveals.
        let storage = restyle("**foo**", focus: FocusLine(lineStart: 0, lineLength: 7))
        // Concealment must be cleared on the delimiter characters.
        for index in [0, 1, 5, 6] {
            let concealed = storage.attribute(.marcdownConcealed, at: index, effectiveRange: nil) as? Bool
            #expect(concealed != true, "expected `**` at \(index) to be revealed")
        }
        // And the foreground must be the dim color.
        let dim = StylingTheme.system.dim
        let leftColor = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let rightColor = storage.attribute(.foregroundColor, at: 6, effectiveRange: nil) as? NSColor
        #expect(leftColor == dim)
        #expect(rightColor == dim)
    }

    @Test func boldBodyTextIsNotDimmedWhenLineFocused() {
        // Focus must dim only the syntax characters, not the body.
        let storage = restyle("**foo**", focus: FocusLine(lineStart: 0, lineLength: 7))
        let dim = StylingTheme.system.dim
        for index in 2...4 {
            let color = storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
            #expect(color != dim, "expected body char at \(index) to stay body-coloured, not dim")
        }
    }

    // MARK: - Multi-line: only the focus line reveals

    @Test func nonFocusLinesKeepConcealment() {
        // Two lines, both bold; focus on the first one only.
        let source = "**foo**\n**bar**"
        let storage = restyle(source, focus: FocusLine(lineStart: 0, lineLength: 7))

        // Focus line: revealed.
        let focusLeftConcealed = storage.attribute(.marcdownConcealed, at: 0, effectiveRange: nil) as? Bool
        #expect(focusLeftConcealed != true)

        // Non-focus line offsets: "\n" at 7, "**" starts at 8.
        let otherLeftConcealed = storage.attribute(.marcdownConcealed, at: 8, effectiveRange: nil) as? Bool
        let otherRightConcealed = storage.attribute(.marcdownConcealed, at: 13, effectiveRange: nil) as? Bool
        #expect(otherLeftConcealed == true)
        #expect(otherRightConcealed == true)
    }

    // MARK: - Heading marker reveal

    @Test func headingMarkerRevealedWhenFocused() {
        let storage = restyle("# Hello", focus: FocusLine(lineStart: 0, lineLength: 7))
        let dim = StylingTheme.system.dim
        // "# " at offsets 0..<2 — concealed when off-line, dim when focused.
        for index in 0...1 {
            let concealed = storage.attribute(.marcdownConcealed, at: index, effectiveRange: nil) as? Bool
            #expect(concealed != true, "expected `# ` at \(index) to be revealed")
            let color = storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
            #expect(color == dim, "expected `# ` at \(index) to be dim-coloured")
        }
    }

    @Test func headingMarkerConcealedWhenNotFocused() {
        // Multi-line buffer with heading on line 2; focus on line 1.
        let source = "first\n# Hello"
        let storage = restyle(source, focus: FocusLine(lineStart: 0, lineLength: 5))
        // Heading marker at offsets 6..<8.
        let leftConcealed = storage.attribute(.marcdownConcealed, at: 6, effectiveRange: nil) as? Bool
        #expect(leftConcealed == true)
    }

    // MARK: - Bullet marker reveal — overlay tag removed

    @Test func bulletMarkerLosesListMarkerTagWhenFocused() {
        // Spec §13: when focused, the bullet icon is NOT drawn — the raw `- `
        // is shown dim instead. The layout manager keys off
        // `.marcdownListMarker`, so removing the tag is how we tell it to
        // skip the overlay.
        let storage = restyle("- foo", focus: FocusLine(lineStart: 0, lineLength: 5))
        let marker = storage.attribute(.marcdownListMarker, at: 0, effectiveRange: nil)
        #expect(marker == nil, "expected list-marker tag to be stripped on focused line")
    }

    @Test func bulletMarkerKeepsTagWhenNotFocused() {
        // Two lines, both bullets; focus on line 2.
        let source = "- foo\n- bar"
        let storage = restyle(source, focus: FocusLine(lineStart: 6, lineLength: 5))
        // First line: tag intact.
        let marker = storage.attribute(.marcdownListMarker, at: 0, effectiveRange: nil) as? MarcdownListMarkerKind
        #expect(marker == .bullet)
    }

    @Test func bulletMarkerForegroundFlipsFromClearToDimWhenFocused() {
        let storage = restyle("- foo", focus: FocusLine(lineStart: 0, lineLength: 5))
        let dim = StylingTheme.system.dim
        for index in 0...1 {
            let color = storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
            #expect(color == dim, "expected `- ` at \(index) to be dim, not clear, when focused")
        }
    }

    // MARK: - Checkbox marker reveal — checkbox tag removed

    @Test func checkboxMarkerLosesTagWhenFocused() {
        // When focused, the checkbox icon is NOT drawn; the raw `- [ ]` is
        // shown dim instead. Tag removal disables the overlay.
        let storage = restyle("- [ ] task", focus: FocusLine(lineStart: 0, lineLength: 10))
        // Tag would normally be at offset 2 (the `[`).
        let state = storage.attribute(.marcdownCheckbox, at: 2, effectiveRange: nil)
        #expect(state == nil, "expected checkbox state tag to be stripped on focused line")
    }

    // MARK: - Link reveal

    @Test func linkSyntaxRevealedWhenFocused() {
        // "[a](b)" — without focus, `[`, `](b)` concealed and label "a" styled
        // as link. With focus, the whole syntax should be visible (dim) but
        // the label still wears the link color/underline.
        let source = "[a](b)"
        let storage = restyle(source, focus: FocusLine(lineStart: 0, lineLength: 6))
        // Opening `[` at offset 0 — revealed.
        let leftBracketConcealed = storage.attribute(.marcdownConcealed, at: 0, effectiveRange: nil) as? Bool
        #expect(leftBracketConcealed != true)
        // Closing `](b)` at offsets 2..<6 — revealed.
        for index in 2..<6 {
            let concealed = storage.attribute(.marcdownConcealed, at: index, effectiveRange: nil) as? Bool
            #expect(concealed != true, "expected link syntax at \(index) to be revealed")
        }
    }
}
