import Foundation
import Testing

@testable import MarcdownStyling

@Suite("BlockFormat")
struct BlockFormatTests {
    private func toggled(_ buffer: String, _ location: Int, _ kind: BlockKind) -> (String, NSRange)? {
        toggled(buffer, location, 0, kind)
    }

    private func toggled(_ buffer: String, _ location: Int, _ length: Int, _ kind: BlockKind) -> (String, NSRange)? {
        guard
            case .replace(let range, let replacement, let selection) = BlockFormat.toggleOutcome(
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
        #expect(
            BlockFormat.toggleOutcome(buffer: "plain", selection: NSRange(location: 0, length: 0), kind: .paragraph)
                == .noOp)
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

    @Test func mixedConversionKeepsLinesAlreadyOfTargetKind() {
        #expect(toggled("- [x] a\nb", 0, 9, .task)?.0 == "- [x] a\n- [ ] b")
        #expect(toggled("* a\nb", 0, 5, .bullet)?.0 == "* a\n- b")
    }

    @Test func taskAndQuotePreserveIndent() {
        #expect(toggled("  - a", 5, .task)?.0 == "  - [ ] a")
        #expect(toggled("  x", 3, .quote)?.0 == "  > x")
    }

    @Test func codeBlockWrapsSelectedLines() {
        guard
            case .replace(let range, let replacement, let selection) = BlockFormat.codeBlockOutcome(
                buffer: "a\nb", selection: NSRange(location: 0, length: 3))
        else {
            Issue.record("expected replace")
            return
        }
        #expect(range == NSRange(location: 0, length: 3))
        #expect(replacement == "```\na\nb\n```")
        #expect(selection == NSRange(location: 4, length: 3))
    }

    @Test func codeBlockOnEmptyLineParksCaretInside() {
        #expect(
            BlockFormat.codeBlockOutcome(buffer: "", selection: NSRange(location: 0, length: 0))
                == .replace(
                    range: NSRange(location: 0, length: 0), replacement: "```\n\n```",
                    selection: NSRange(location: 4, length: 0)))
    }

    @Test func codeBlockAfterTextGoesOnNextLine() {
        #expect(
            BlockFormat.codeBlockOutcome(buffer: "x", selection: NSRange(location: 1, length: 0))
                == .replace(
                    range: NSRange(location: 1, length: 0), replacement: "\n```\n\n```",
                    selection: NSRange(location: 6, length: 0)))
    }

    @Test func dividerOnEmptyLineAndAfterText() {
        #expect(
            BlockFormat.dividerOutcome(buffer: "", selection: NSRange(location: 0, length: 0))
                == .replace(
                    range: NSRange(location: 0, length: 0), replacement: "---",
                    selection: NSRange(location: 3, length: 0)))
        #expect(
            BlockFormat.dividerOutcome(buffer: "x", selection: NSRange(location: 1, length: 0))
                == .replace(
                    range: NSRange(location: 1, length: 0), replacement: "\n\n---",
                    selection: NSRange(location: 6, length: 0)))
    }

    @Test func dividerOnEmptyLineUnderTextAddsBlankLine() {
        #expect(
            BlockFormat.dividerOutcome(buffer: "a\n", selection: NSRange(location: 2, length: 0))
                == .replace(
                    range: NSRange(location: 2, length: 0), replacement: "\n---",
                    selection: NSRange(location: 6, length: 0)))
        #expect(
            BlockFormat.dividerOutcome(buffer: "a\n\n", selection: NSRange(location: 3, length: 0))
                == .replace(
                    range: NSRange(location: 3, length: 0), replacement: "---",
                    selection: NSRange(location: 6, length: 0)))
    }

    @Test func dividerReplacesWhitespaceOnlyLine() {
        #expect(
            BlockFormat.dividerOutcome(buffer: "  ", selection: NSRange(location: 2, length: 0))
                == .replace(
                    range: NSRange(location: 0, length: 2), replacement: "---",
                    selection: NSRange(location: 3, length: 0)))
    }
}
