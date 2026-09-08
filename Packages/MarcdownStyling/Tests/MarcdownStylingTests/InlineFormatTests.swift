import Foundation
import Testing

@testable import MarcdownStyling

@Suite("InlineFormat")
struct InlineFormatTests {
    @Test func wrapsSelection() {
        #expect(
            InlineFormat.toggleOutcome(
                buffer: "hello world", selection: NSRange(location: 0, length: 5), delimiter: "**")
                == .replace(
                    range: NSRange(location: 0, length: 5), replacement: "**hello**",
                    selection: NSRange(location: 2, length: 5)))
    }

    @Test func unwrapsWhenDelimitersSurroundSelection() {
        #expect(
            InlineFormat.toggleOutcome(buffer: "**hello**", selection: NSRange(location: 2, length: 5), delimiter: "**")
                == .replace(
                    range: NSRange(location: 0, length: 9), replacement: "hello",
                    selection: NSRange(location: 0, length: 5)
                ))
    }

    @Test func unwrapsWhenSelectionIncludesDelimiters() {
        #expect(
            InlineFormat.toggleOutcome(buffer: "a **b** c", selection: NSRange(location: 2, length: 5), delimiter: "**")
                == .replace(
                    range: NSRange(location: 2, length: 5), replacement: "b", selection: NSRange(location: 2, length: 1)
                ))
    }

    @Test func trimsWhitespaceBeforeWrapping() {
        #expect(
            InlineFormat.toggleOutcome(buffer: "hi there", selection: NSRange(location: 2, length: 6), delimiter: "*")
                == .replace(
                    range: NSRange(location: 3, length: 5), replacement: "*there*",
                    selection: NSRange(location: 4, length: 5)
                ))
    }

    @Test func caretInsertsPairAndParksInside() {
        #expect(
            InlineFormat.toggleOutcome(buffer: "ab", selection: NSRange(location: 1, length: 0), delimiter: "`")
                == .replace(
                    range: NSRange(location: 1, length: 0), replacement: "``",
                    selection: NSRange(location: 2, length: 0)))
    }

    @Test func caretInsideEmptyPairRemovesIt() {
        #expect(
            InlineFormat.toggleOutcome(buffer: "a****b", selection: NSRange(location: 3, length: 0), delimiter: "**")
                == .replace(
                    range: NSRange(location: 1, length: 4), replacement: "", selection: NSRange(location: 1, length: 0))
        )
    }

    @Test func whitespaceOnlySelectionIsNoOp() {
        #expect(
            InlineFormat.toggleOutcome(buffer: "a  b", selection: NSRange(location: 1, length: 2), delimiter: "*")
                == .noOp)
    }

    @Test func singleUnitDelimiterDoesNotUnwrapEvenRun() {
        #expect(
            InlineFormat.toggleOutcome(buffer: "**foo**", selection: NSRange(location: 2, length: 3), delimiter: "*")
                == .replace(
                    range: NSRange(location: 2, length: 3), replacement: "*foo*",
                    selection: NSRange(location: 3, length: 3)))
    }

    @Test func singleUnitDelimiterUnwrapsOddRun() {
        #expect(
            InlineFormat.toggleOutcome(buffer: "***foo***", selection: NSRange(location: 3, length: 3), delimiter: "*")
                == .replace(
                    range: NSRange(location: 2, length: 5), replacement: "foo",
                    selection: NSRange(location: 2, length: 3)))
    }

    @Test func doubleUnitDelimiterUnwrapsTripleRun() {
        #expect(
            InlineFormat.toggleOutcome(buffer: "***foo***", selection: NSRange(location: 3, length: 3), delimiter: "**")
                == .replace(
                    range: NSRange(location: 1, length: 7), replacement: "foo",
                    selection: NSRange(location: 1, length: 3)))
    }

    @Test func singleUnitDelimiterWrapsWholeStrongSpan() {
        #expect(
            InlineFormat.toggleOutcome(buffer: "**foo**", selection: NSRange(location: 0, length: 7), delimiter: "*")
                == .replace(
                    range: NSRange(location: 0, length: 7), replacement: "***foo***",
                    selection: NSRange(location: 1, length: 7)))
    }

    @Test func doubleUnitDelimiterUnwrapsWholeStrongSpan() {
        #expect(
            InlineFormat.toggleOutcome(buffer: "**foo**", selection: NSRange(location: 0, length: 7), delimiter: "**")
                == .replace(
                    range: NSRange(location: 0, length: 7), replacement: "foo",
                    selection: NSRange(location: 0, length: 3)))
    }

    @Test func caretInsideEvenRunInsertsSingleUnitPair() {
        #expect(
            InlineFormat.toggleOutcome(buffer: "a****b", selection: NSRange(location: 3, length: 0), delimiter: "*")
                == .replace(
                    range: NSRange(location: 3, length: 0), replacement: "**",
                    selection: NSRange(location: 4, length: 0)))
    }

    @Test func selectionStraddlingDelimitersIsNoOp() {
        #expect(
            InlineFormat.toggleOutcome(buffer: "**a** ", selection: NSRange(location: 2, length: 4), delimiter: "**")
                == .noOp)
        #expect(
            InlineFormat.toggleOutcome(buffer: "**foo**", selection: NSRange(location: 1, length: 5), delimiter: "**")
                == .noOp)
    }

    @Test func delimiterOnlySelectionIsNoOp() {
        #expect(
            InlineFormat.toggleOutcome(buffer: "**", selection: NSRange(location: 0, length: 2), delimiter: "**")
                == .noOp)
        #expect(
            InlineFormat.toggleOutcome(buffer: "**foo**", selection: NSRange(location: 0, length: 2), delimiter: "**")
                == .noOp)
    }

    @Test func linkWithSelectionAndURLPutsCaretAfter() {
        #expect(
            InlineFormat.linkOutcome(buffer: "see docs", selection: NSRange(location: 4, length: 4), url: "https://x.y")
                == .replace(
                    range: NSRange(location: 4, length: 4), replacement: "[docs](https://x.y)",
                    selection: NSRange(location: 23, length: 0)))
    }

    @Test func linkWithSelectionAndNoURLParksCaretInParens() {
        #expect(
            InlineFormat.linkOutcome(buffer: "docs", selection: NSRange(location: 0, length: 4), url: "")
                == .replace(
                    range: NSRange(location: 0, length: 4), replacement: "[docs]()",
                    selection: NSRange(location: 7, length: 0)
                ))
    }

    @Test func linkWithCaretParksInsideBrackets() {
        #expect(
            InlineFormat.linkOutcome(buffer: "", selection: NSRange(location: 0, length: 0), url: "")
                == .replace(
                    range: NSRange(location: 0, length: 0), replacement: "[]()",
                    selection: NSRange(location: 1, length: 0)))
    }

    @Test func detectsHTTPURLs() {
        #expect(InlineFormat.isHTTPURL("https://example.com/a?b=c"))
        #expect(InlineFormat.isHTTPURL("  http://x.io \n"))
        #expect(!InlineFormat.isHTTPURL("example.com"))
        #expect(!InlineFormat.isHTTPURL("https://a b"))
        #expect(!InlineFormat.isHTTPURL("mailto:a@b.c"))
    }
}
