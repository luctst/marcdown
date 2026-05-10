import Foundation
import Testing
@testable import MarcdownStyling

@Suite("TaskListContinuation")
struct TaskListContinuationTests {

    // MARK: - .noOp cases

    @Test func emptyBufferIsNoOp() {
        #expect(
            TaskListContinuation.enterOutcome(buffer: "", cursorOffset: 0)
            == .noOp
        )
    }

    @Test func plainTextIsNoOp() {
        #expect(
            TaskListContinuation.enterOutcome(buffer: "hello", cursorOffset: 5)
            == .noOp
        )
    }

    @Test func cursorOnBlankLineAfterPlainTextIsNoOp() {
        // `"hello\n"` with cursor on the blank trailing paragraph — no task above.
        #expect(
            TaskListContinuation.enterOutcome(buffer: "hello\n", cursorOffset: 6)
            == .noOp
        )
    }

    @Test func cursorBeforeMarkerIsNoOp() {
        // Cursor before the marker — Enter falls through to AppKit.
        #expect(
            TaskListContinuation.enterOutcome(buffer: "- [ ] foo", cursorOffset: 0)
            == .noOp
        )
    }

    @Test func cursorInsideMarkerIsNoOp() {
        // Cursor inside the marker brackets — fall through.
        #expect(
            TaskListContinuation.enterOutcome(buffer: "- [ ] foo", cursorOffset: 3)
            == .noOp
        )
    }

    @Test func partialMarkerIsNoOp() {
        // `.partial` shape (e.g. user mid-typing `- [`) — Enter falls through
        // to AppKit. This locks in the `.partial` branch in enterOutcome.
        #expect(
            TaskListContinuation.enterOutcome(buffer: "- [", cursorOffset: 3)
            == .noOp
        )
    }

    // MARK: - Continuation (non-empty task) cases

    @Test func endOfNonEmptyTaskLineSplits() {
        let buffer = "- [ ] foo"
        #expect(
            TaskListContinuation.enterOutcome(buffer: buffer, cursorOffset: 9)
            == .replace(
                range: NSRange(location: 9, length: 0),
                replacement: "\n- [ ] ",
                cursorOffsetInBuffer: 16
            )
        )
    }

    @Test func endOfCheckedNonEmptyTaskInsertsUnchecked() {
        let buffer = "- [x] done"
        #expect(
            TaskListContinuation.enterOutcome(buffer: buffer, cursorOffset: 10)
            == .replace(
                range: NSRange(location: 10, length: 0),
                replacement: "\n- [ ] ",
                cursorOffsetInBuffer: 17
            )
        )
    }

    @Test func midNonEmptyTaskSplits() {
        // Existing tail " world" stays where it is; helper inserts marker before it.
        let buffer = "- [ ] hello world"
        #expect(
            TaskListContinuation.enterOutcome(buffer: buffer, cursorOffset: 11)
            == .replace(
                range: NSRange(location: 11, length: 0),
                replacement: "\n- [ ] ",
                cursorOffsetInBuffer: 18
            )
        )
    }

    @Test func indentedNonEmptyTaskContinuationPreservesIndent() {
        let buffer = "  - [ ] foo"
        #expect(
            TaskListContinuation.enterOutcome(buffer: buffer, cursorOffset: 11)
            == .replace(
                range: NSRange(location: 11, length: 0),
                replacement: "\n  - [ ] ",
                cursorOffsetInBuffer: 20
            )
        )
    }

    // MARK: - Empty-task exit cases

    // Enter on an empty marker exits the list: strip the marker, leave the
    // (now-blank) line in place so the user can type plain markdown there.
    // Subsequent Enter on the resulting blank line just inserts `\n`
    // (the `.none` branch returns `.noOp`).

    @Test func emptyTaskAtStartOfBufferRemovesMarker() {
        let buffer = "- [ ] "
        #expect(
            TaskListContinuation.enterOutcome(buffer: buffer, cursorOffset: 6)
            == .replace(
                range: NSRange(location: 0, length: 6),
                replacement: "",
                cursorOffsetInBuffer: 0
            )
        )
    }

    @Test func emptyTaskAfterTaskLineRemovesMarker() {
        let buffer = "- [ ] foo\n- [ ] "
        #expect(
            TaskListContinuation.enterOutcome(buffer: buffer, cursorOffset: 16)
            == .replace(
                range: NSRange(location: 10, length: 6),
                replacement: "",
                cursorOffsetInBuffer: 10
            )
        )
    }

    @Test func emptyTaskAfterPlainTextRemovesMarker() {
        let buffer = "hello\n- [ ] "
        #expect(
            TaskListContinuation.enterOutcome(buffer: buffer, cursorOffset: 12)
            == .replace(
                range: NSRange(location: 6, length: 6),
                replacement: "",
                cursorOffsetInBuffer: 6
            )
        )
    }

    @Test func cursorAtMarkerEndOnEmptyTaskMidBufferRemovesMarker() {
        // Mid-buffer empty task; remove just the marker. The trailing `\nworld`
        // stays at its new offset after the removal.
        let buffer = "hello\n- [ ] \nworld"
        #expect(
            TaskListContinuation.enterOutcome(buffer: buffer, cursorOffset: 12)
            == .replace(
                range: NSRange(location: 6, length: 6),
                replacement: "",
                cursorOffsetInBuffer: 6
            )
        )
    }

    @Test func emptyIndentedTaskRemovesMarkerIncludingIndent() {
        let buffer = "  - [ ] "
        #expect(
            TaskListContinuation.enterOutcome(buffer: buffer, cursorOffset: 8)
            == .replace(
                range: NSRange(location: 0, length: 8),
                replacement: "",
                cursorOffsetInBuffer: 0
            )
        )
    }

    // MARK: - Blank line after task line (orphan trailing paragraph)

    // After exiting a task list (Enter on empty marker) the cursor lands on
    // a blank line that follows a non-empty task. Pressing Enter there must
    // be a no-op so AppKit inserts a plain `\n` — it must NOT re-enter the
    // task list. The atomic-Backspace handler covers the "user backspaced
    // through a row and wants continuation" case directly, so this helper
    // is no longer needed and would otherwise misfire on the exit-list flow.

    @Test func cursorOnBlankLineAfterTaskIsNoOp() {
        let buffer = "- [ ] foo\n"
        #expect(
            TaskListContinuation.enterOutcome(buffer: buffer, cursorOffset: 10)
            == .noOp
        )
    }

    @Test func cursorOnBlankLineAfterCheckedTaskIsNoOp() {
        let buffer = "- [x] done\n"
        #expect(
            TaskListContinuation.enterOutcome(buffer: buffer, cursorOffset: 11)
            == .noOp
        )
    }

    @Test func cursorOnBlankLineAfterIndentedTaskIsNoOp() {
        let buffer = "  - [ ] foo\n"
        #expect(
            TaskListContinuation.enterOutcome(buffer: buffer, cursorOffset: 12)
            == .noOp
        )
    }
}
