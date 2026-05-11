import Foundation
import Testing

@testable import MarcdownStyling

@Suite("ListContinuation")
struct ListContinuationTests {

    // MARK: - Enter: .replace cases (non-empty body, unordered)

    @Test func endOfUnorderedDashLineSplits() {
        let buffer = "- foo"
        #expect(
            ListContinuation.enterOutcome(buffer: buffer, cursorOffset: 5)
                == .replace(
                    range: NSRange(location: 5, length: 0),
                    replacement: "\n- ",
                    cursorOffsetInBuffer: 8
                )
        )
    }

    @Test func endOfUnorderedAsteriskLinePreservesMarker() {
        let buffer = "* foo"
        #expect(
            ListContinuation.enterOutcome(buffer: buffer, cursorOffset: 5)
                == .replace(
                    range: NSRange(location: 5, length: 0),
                    replacement: "\n* ",
                    cursorOffsetInBuffer: 8
                )
        )
    }

    @Test func endOfUnorderedPlusLinePreservesMarker() {
        let buffer = "+ foo"
        #expect(
            ListContinuation.enterOutcome(buffer: buffer, cursorOffset: 5)
                == .replace(
                    range: NSRange(location: 5, length: 0),
                    replacement: "\n+ ",
                    cursorOffsetInBuffer: 8
                )
        )
    }

    @Test func indentedUnorderedContinuationPreservesIndent() {
        let buffer = "  - foo"
        #expect(
            ListContinuation.enterOutcome(buffer: buffer, cursorOffset: 7)
                == .replace(
                    range: NSRange(location: 7, length: 0),
                    replacement: "\n  - ",
                    cursorOffsetInBuffer: 12
                )
        )
    }

    // MARK: - Enter: .replace cases (non-empty body, ordered)

    @Test func endOfOrderedLineIncrementsMarker() {
        let buffer = "1. foo"
        #expect(
            ListContinuation.enterOutcome(buffer: buffer, cursorOffset: 6)
                == .replace(
                    range: NSRange(location: 6, length: 0),
                    replacement: "\n2. ",
                    cursorOffsetInBuffer: 10
                )
        )
    }

    @Test func endOfOrderedLineIncrementsAcrossDigitBoundary() {
        let buffer = "9. foo"
        #expect(
            ListContinuation.enterOutcome(buffer: buffer, cursorOffset: 6)
                == .replace(
                    range: NSRange(location: 6, length: 0),
                    replacement: "\n10. ",
                    cursorOffsetInBuffer: 11
                )
        )
    }

    @Test func endOfOrderedLineWithMultiDigitMarkerIncrements() {
        let buffer = "42. bar"
        #expect(
            ListContinuation.enterOutcome(buffer: buffer, cursorOffset: 7)
                == .replace(
                    range: NSRange(location: 7, length: 0),
                    replacement: "\n43. ",
                    cursorOffsetInBuffer: 12
                )
        )
    }

    // MARK: - Enter: empty-body cases (strip marker, exit list)

    @Test func emptyUnorderedMarkerAtBufferStartRemovesMarker() {
        let buffer = "- "
        #expect(
            ListContinuation.enterOutcome(buffer: buffer, cursorOffset: 2)
                == .replace(
                    range: NSRange(location: 0, length: 2),
                    replacement: "",
                    cursorOffsetInBuffer: 0
                )
        )
    }

    @Test func emptyOrderedMarkerAtBufferStartRemovesMarker() {
        let buffer = "1. "
        #expect(
            ListContinuation.enterOutcome(buffer: buffer, cursorOffset: 3)
                == .replace(
                    range: NSRange(location: 0, length: 3),
                    replacement: "",
                    cursorOffsetInBuffer: 0
                )
        )
    }

    @Test func emptyIndentedUnorderedMarkerRemovesMarkerIncludingIndent() {
        let buffer = "  - "
        #expect(
            ListContinuation.enterOutcome(buffer: buffer, cursorOffset: 4)
                == .replace(
                    range: NSRange(location: 0, length: 4),
                    replacement: "",
                    cursorOffsetInBuffer: 0
                )
        )
    }

    // MARK: - Enter: .noOp cases

    @Test func cursorInsideUnorderedMarkerIsNoOp() {
        // Cursor between "-" and the trailing space — fall through.
        #expect(
            ListContinuation.enterOutcome(buffer: "- foo", cursorOffset: 1)
                == .noOp
        )
    }

    @Test func cursorBeforeUnorderedMarkerIsNoOp() {
        #expect(
            ListContinuation.enterOutcome(buffer: "- foo", cursorOffset: 0)
                == .noOp
        )
    }

    @Test func cursorInsideOrderedMarkerIsNoOp() {
        // Cursor between "0" and "." in "10. foo".
        #expect(
            ListContinuation.enterOutcome(buffer: "10. foo", cursorOffset: 2)
                == .noOp
        )
    }

    @Test func plainTextLineIsNoOp() {
        #expect(
            ListContinuation.enterOutcome(buffer: "hello", cursorOffset: 5)
                == .noOp
        )
    }

    @Test func partialUnorderedLineIsNoOp() {
        // Bare "-" with no trailing space is not a list marker.
        #expect(
            ListContinuation.enterOutcome(buffer: "-", cursorOffset: 1)
                == .noOp
        )
    }

    @Test func checkboxLineIsNoOp() {
        // Task-list markers belong to TaskListContinuation; ListContinuation
        // must fall through.
        #expect(
            ListContinuation.enterOutcome(buffer: "- [ ] task", cursorOffset: 10)
                == .noOp
        )
    }

    // MARK: - Enter: mid-buffer cursor

    @Test func endOfUnorderedLineMidBufferSplits() {
        // Buffer:    "line1\n- foo\nline3"
        // Offsets:    0     6 7   11 12
        // Cursor at end of "- foo" line (offset 11).
        let buffer = "line1\n- foo\nline3"
        #expect(
            ListContinuation.enterOutcome(buffer: buffer, cursorOffset: 11)
                == .replace(
                    range: NSRange(location: 11, length: 0),
                    replacement: "\n- ",
                    cursorOffsetInBuffer: 14
                )
        )
    }

    // MARK: - Backspace: atomic delete on empty marker

    @Test func backspaceAtEndOfEmptyUnorderedMarkerAtBufferStartDeletesWholeMarker() {
        #expect(
            ListContinuation.backspaceOutcome(buffer: "- ", cursorOffset: 2)
                == .replace(
                    range: NSRange(location: 0, length: 2),
                    cursorOffsetInBuffer: 0
                )
        )
    }

    @Test func backspaceAtEndOfEmptyOrderedMarkerAtBufferStartDeletesWholeMarker() {
        #expect(
            ListContinuation.backspaceOutcome(buffer: "1. ", cursorOffset: 3)
                == .replace(
                    range: NSRange(location: 0, length: 3),
                    cursorOffsetInBuffer: 0
                )
        )
    }

    @Test func backspaceAtEndOfEmptyUnorderedMarkerAfterContentEatsPrecedingNewline() {
        // Delete `\n- ` (length 3) starting at offset 5.
        #expect(
            ListContinuation.backspaceOutcome(buffer: "line1\n- ", cursorOffset: 8)
                == .replace(
                    range: NSRange(location: 5, length: 3),
                    cursorOffsetInBuffer: 5
                )
        )
    }

    @Test func backspaceAtEndOfEmptyOrderedMarkerAfterContentEatsPrecedingNewline() {
        // Delete `\n1. ` (length 4) starting at offset 5.
        #expect(
            ListContinuation.backspaceOutcome(buffer: "line1\n1. ", cursorOffset: 9)
                == .replace(
                    range: NSRange(location: 5, length: 4),
                    cursorOffsetInBuffer: 5
                )
        )
    }

    // MARK: - Backspace: .standard cases

    @Test func backspaceOnNonEmptyUnorderedBodyIsStandard() {
        // Cursor at end of body — AppKit deletes the trailing char normally.
        #expect(
            ListContinuation.backspaceOutcome(buffer: "- foo", cursorOffset: 5)
                == .standard
        )
    }

    @Test func backspaceMidMarkerIsStandard() {
        #expect(
            ListContinuation.backspaceOutcome(buffer: "- foo", cursorOffset: 1)
                == .standard
        )
    }

    @Test func backspaceOnPlainLineIsStandard() {
        #expect(
            ListContinuation.backspaceOutcome(buffer: "hello", cursorOffset: 5)
                == .standard
        )
    }

    @Test func backspaceAtStartOfEmptyBufferIsStandard() {
        #expect(
            ListContinuation.backspaceOutcome(buffer: "", cursorOffset: 0)
                == .standard
        )
    }
}
