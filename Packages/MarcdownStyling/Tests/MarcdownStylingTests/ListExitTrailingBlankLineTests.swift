import Foundation
import Testing

@testable import MarcdownStyling

// Spec §4.3 / §20 acceptance #6:
//   Pressing Enter on an empty list-item line strips the marker AND inserts
//   a trailing blank line so subsequent text does not fuse into the list per
//   CommonMark. Today `ListContinuation.enterOutcome` strips the marker but
//   does not emit the blank line. These tests pin the future contract.
//
// This is the single behavioural change to existing helpers in this slice.
// `ListContinuationTests` already covers the strip-only behaviour; once guy
// adds the blank line, the tests there will need an update. We intentionally
// keep this regression in a separate suite so the diff is easy to review.
//
// Expected outcome shape (already in `ListContinuation.swift`):
//   .replace(range: <line-prefix>, replacement: "\n", cursorOffsetInBuffer: <newCursor>)
//
// The replacement gains a `\n` so the line becomes blank AND a blank line
// follows. Cursor lands at the start of the blank line that follows.

@Suite("List exit inserts trailing blank line")
struct ListExitTrailingBlankLineTests {

    @Test func emptyBulletAfterContentEmitsBlankLineSeparator() {
        // Before:  "- foo\n- |" (cursor at 8)
        // After:   "- foo\n\n|"  (the empty marker line becomes blank, plus
        //                       an extra `\n` so a blank line follows)
        // The strip range is the marker `- ` at line offsets [6..<8], and the
        // replacement is `\n` (a single newline) so the line collapses and a
        // separator newline is inserted in its place. Cursor lands at offset 7.
        let buffer = "- foo\n- "
        #expect(
            ListContinuation.enterOutcome(buffer: buffer, cursorOffset: 8)
                == .replace(
                    range: NSRange(location: 6, length: 2),
                    replacement: "\n",
                    cursorOffsetInBuffer: 7
                )
        )
    }

    @Test func emptyOrderedAfterContentEmitsBlankLineSeparator() {
        // Before:  "1. foo\n2. |" (cursor at 10)
        // After:   "1. foo\n\n|"
        let buffer = "1. foo\n2. "
        #expect(
            ListContinuation.enterOutcome(buffer: buffer, cursorOffset: 10)
                == .replace(
                    range: NSRange(location: 7, length: 3),
                    replacement: "\n",
                    cursorOffsetInBuffer: 8
                )
        )
    }

    @Test func emptyBulletAtBufferStartStillStripsWithoutLeadingNewline() {
        // No preceding content → no preceding `\n` → no blank line needed,
        // the marker simply strips. The cursor lands at offset 0.
        // (CommonMark's blank-line requirement is for separating consecutive
        // blocks; with no block above there's nothing to separate from.)
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
}
