import Foundation
import Testing
@testable import MarcdownStyling

@Suite("Backspace continuation")
struct BackspaceContinuationTests {

    // MARK: - .standard cases

    @Test func emptyBufferIsStandard() {
        #expect(
            BackspaceContinuation.deleteOutcome(buffer: "", cursorOffset: 0)
            == .standard
        )
    }

    @Test func plainTextIsStandard() {
        #expect(
            BackspaceContinuation.deleteOutcome(buffer: "hello", cursorOffset: 5)
            == .standard
        )
    }

    @Test func cursorBeforeMarkerIsStandard() {
        #expect(
            BackspaceContinuation.deleteOutcome(buffer: "- [ ] foo", cursorOffset: 0)
            == .standard
        )
    }

    @Test func cursorMidMarkerIsStandard() {
        // Mid-marker BS is normal AppKit behavior.
        #expect(
            BackspaceContinuation.deleteOutcome(buffer: "- [ ] foo", cursorOffset: 3)
            == .standard
        )
    }

    @Test func cursorOnNonEmptyTaskBodyIsStandard() {
        // Cursor at end of body — AppKit deletes the trailing 'o' normally.
        #expect(
            BackspaceContinuation.deleteOutcome(buffer: "- [ ] foo", cursorOffset: 9)
            == .standard
        )
    }

    @Test func cursorMidBodyOnNonEmptyTaskIsStandard() {
        // Cursor in middle of "hello" body — normal BS deletes 'l'.
        #expect(
            BackspaceContinuation.deleteOutcome(buffer: "- [ ] hello", cursorOffset: 8)
            == .standard
        )
    }

    @Test func cursorPastEndOfBufferIsStandard() {
        #expect(
            BackspaceContinuation.deleteOutcome(buffer: "- [ ] ", cursorOffset: 100)
            == .standard
        )
    }

    @Test func negativeCursorIsStandard() {
        #expect(
            BackspaceContinuation.deleteOutcome(buffer: "- [ ] ", cursorOffset: -1)
            == .standard
        )
    }

    // MARK: - Atomic delete on empty marker

    @Test func cursorAtEndOfMarkerOnEmptyTaskAtBufferStartDeletesWholeMarker() {
        // No preceding `\n`; remove entire line.
        #expect(
            BackspaceContinuation.deleteOutcome(buffer: "- [ ] ", cursorOffset: 6)
            == .replace(
                range: NSRange(location: 0, length: 6),
                cursorOffsetInBuffer: 0
            )
        )
    }

    @Test func cursorAtEndOfMarkerOnEmptyTaskAfterContentDeletesMarkerAndPrecedingNewline() {
        // Eats preceding `\n` at offset 9.
        #expect(
            BackspaceContinuation.deleteOutcome(buffer: "- [ ] foo\n- [ ] ", cursorOffset: 16)
            == .replace(
                range: NSRange(location: 9, length: 7),
                cursorOffsetInBuffer: 9
            )
        )
    }

    @Test func cursorAtEndOfMarkerOnEmptyTaskAfterPlainTextEatsPrecedingNewline() {
        #expect(
            BackspaceContinuation.deleteOutcome(buffer: "hello\n- [ ] ", cursorOffset: 12)
            == .replace(
                range: NSRange(location: 5, length: 7),
                cursorOffsetInBuffer: 5
            )
        )
    }

    @Test func cursorAtEndOfMarkerOnEmptyTaskMidBufferEatsPrecedingNewline() {
        // Delete `\n- [ ] ` (length 7); trailing `\nworld` stays.
        #expect(
            BackspaceContinuation.deleteOutcome(buffer: "hello\n- [ ] \nworld", cursorOffset: 12)
            == .replace(
                range: NSRange(location: 5, length: 7),
                cursorOffsetInBuffer: 5
            )
        )
    }

    // MARK: - Atomic delete on partial marker

    @Test func cursorAtEndOfPartialDeletesPartial() {
        // Partial shape "- [", no body, atomic delete.
        #expect(
            BackspaceContinuation.deleteOutcome(buffer: "- [", cursorOffset: 3)
            == .replace(
                range: NSRange(location: 0, length: 3),
                cursorOffsetInBuffer: 0
            )
        )
    }

    @Test func cursorAtEndOfPartialAfterContentEatsPrecedingNewline() {
        // Delete `\n- [` (length 4).
        #expect(
            BackspaceContinuation.deleteOutcome(buffer: "hello\n- [", cursorOffset: 9)
            == .replace(
                range: NSRange(location: 5, length: 4),
                cursorOffsetInBuffer: 5
            )
        )
    }

    // MARK: - Variants: checked + indented

    @Test func cursorAtEndOfMarkerOnEmptyCheckedTaskDeletes() {
        #expect(
            BackspaceContinuation.deleteOutcome(buffer: "- [x] ", cursorOffset: 6)
            == .replace(
                range: NSRange(location: 0, length: 6),
                cursorOffsetInBuffer: 0
            )
        )
    }

    @Test func cursorAtEndOfMarkerOnEmptyIndentedTaskDeletesIncludingIndent() {
        #expect(
            BackspaceContinuation.deleteOutcome(buffer: "  - [ ] ", cursorOffset: 8)
            == .replace(
                range: NSRange(location: 0, length: 8),
                cursorOffsetInBuffer: 0
            )
        )
    }

    @Test func cursorAtEndOfMarkerOnEmptyIndentedTaskAfterContentEatsNewline() {
        // Delete `\n` + indent + marker (length 9).
        #expect(
            BackspaceContinuation.deleteOutcome(buffer: "hello\n  - [ ] ", cursorOffset: 14)
            == .replace(
                range: NSRange(location: 5, length: 9),
                cursorOffsetInBuffer: 5
            )
        )
    }
}
