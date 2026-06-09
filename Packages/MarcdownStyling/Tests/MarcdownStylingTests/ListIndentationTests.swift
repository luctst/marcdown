import Foundation
import Testing

@testable import MarcdownStyling

// MARK: - Expected production API (to be implemented by guy)
//
// These tests pin the contract for Tab / Shift-Tab on list lines and the
// renumbering pass that must run after any structural change to an ordered
// list. The helper mirrors the buffer-relative shape of `ListContinuation`
// and `TaskListContinuation` (pure function, AppKit-free, UTF-16 throughout).
//
// Expected types/functions:
//
//   public enum ListIndentOutcome: Sendable, Equatable {
//       case noOp
//       case replace(range: NSRange, replacement: String, cursorOffsetInBuffer: Int)
//   }
//
//   public enum ListIndentation {
//       /// Tab on a list/task line: prepend `"  "` (2 spaces) at lineStart.
//       /// Cursor stays at the same logical column (shifted +2 within the buffer).
//       /// Non-list lines return `.noOp` (caller falls through to AppKit so Tab
//       /// inserts a literal tab on a plain line). Multi-line selections are
//       /// handled by `indentOutcome(buffer:selection:)`.
//       public static func indentOutcome(buffer: String, cursorOffset: Int) -> ListIndentOutcome
//
//       /// Shift-Tab on a list/task line: strip up to 2 leading spaces (or 1
//       /// leading tab) from lineStart. `.noOp` when already at the left margin
//       /// or on a non-list line.
//       public static func outdentOutcome(buffer: String, cursorOffset: Int) -> ListIndentOutcome
//   }
//
// And the renumbering helper (Section 5.3/5.4):
//
//   public enum OrderedListRenumber {
//       /// Renumber the contiguous ordered-list run that *contains* the line at
//       /// `anchorOffset`. A run is a maximal sequence of consecutive lines
//       /// at the same indent depth whose marker is `.ordered`. The first
//       /// item's number is preserved; subsequent items get sequential numbers.
//       /// Returns the new buffer string and the adjusted cursor offset.
//       /// Returns `.noOp` if the anchor line is not part of an ordered run.
//       public static func renumberRun(
//           buffer: String,
//           anchorOffset: Int,
//           cursorOffset: Int
//       ) -> RenumberOutcome
//   }
//
//   public enum RenumberOutcome: Sendable, Equatable {
//       case noOp
//       case rewrite(newBuffer: String, newCursorOffset: Int)
//   }

@Suite("List Tab / Shift-Tab indentation")
struct ListIndentationTests {

    // MARK: - Tab on a bullet line

    @Test func tabOnBulletAtBufferStartPrependsTwoSpaces() {
        // Before: "- foo|"
        // After:  "  - foo|"  (cursor shifts by +2 buffer offsets, stays on same logical column)
        #expect(
            ListIndentation.indentOutcome(buffer: "- foo", cursorOffset: 5)
                == .replace(
                    range: NSRange(location: 0, length: 0),
                    replacement: "  ",
                    cursorOffsetInBuffer: 7
                )
        )
    }

    @Test func tabOnStarBulletPrependsTwoSpaces() {
        #expect(
            ListIndentation.indentOutcome(buffer: "* foo", cursorOffset: 5)
                == .replace(
                    range: NSRange(location: 0, length: 0),
                    replacement: "  ",
                    cursorOffsetInBuffer: 7
                )
        )
    }

    @Test func tabOnAlreadyIndentedBulletAddsAnotherLevel() {
        // "  - foo" → "    - foo"
        #expect(
            ListIndentation.indentOutcome(buffer: "  - foo", cursorOffset: 7)
                == .replace(
                    range: NSRange(location: 0, length: 0),
                    replacement: "  ",
                    cursorOffsetInBuffer: 9
                )
        )
    }

    @Test func tabOnBulletMidBufferPrependsAtLineStart() {
        // Buffer:    "prev\n- foo\nnext"
        // Offsets:    0    5 6   10 11 ...
        // Line "- foo" starts at offset 5. Cursor at end of that line (offset 10).
        #expect(
            ListIndentation.indentOutcome(
                buffer: "prev\n- foo\nnext",
                cursorOffset: 10
            )
                == .replace(
                    range: NSRange(location: 5, length: 0),
                    replacement: "  ",
                    cursorOffsetInBuffer: 12
                )
        )
    }

    // MARK: - Tab on an ordered line

    @Test func tabOnOrderedItemPrependsTwoSpaces() {
        #expect(
            ListIndentation.indentOutcome(buffer: "1. foo", cursorOffset: 6)
                == .replace(
                    range: NSRange(location: 0, length: 0),
                    replacement: "  ",
                    cursorOffsetInBuffer: 8
                )
        )
    }

    // MARK: - Tab on a task line

    @Test func tabOnTaskItemPrependsTwoSpaces() {
        #expect(
            ListIndentation.indentOutcome(buffer: "- [ ] foo", cursorOffset: 9)
                == .replace(
                    range: NSRange(location: 0, length: 0),
                    replacement: "  ",
                    cursorOffsetInBuffer: 11
                )
        )
    }

    // MARK: - Tab on a non-list line is a no-op (caller falls through to AppKit)

    @Test func tabOnPlainLineIsNoOp() {
        // Plain paragraph: Tab is a literal indent, NOT a list indent.
        // Helper returns .noOp so the coordinator falls through to AppKit.
        // This deliberately diverges from Bear (see Spec §19 / Thomas §10).
        #expect(
            ListIndentation.indentOutcome(buffer: "hello", cursorOffset: 5)
                == .noOp
        )
    }

    @Test func tabOnEmptyBufferIsNoOp() {
        #expect(
            ListIndentation.indentOutcome(buffer: "", cursorOffset: 0)
                == .noOp
        )
    }

    // MARK: - Tab cursor position invariants

    @Test func tabWithCursorInsideBodyShiftsCursorByTwo() {
        // "- fo|o" → cursor at offset 4 → "  - fo|o" → cursor at offset 6
        #expect(
            ListIndentation.indentOutcome(buffer: "- foo", cursorOffset: 4)
                == .replace(
                    range: NSRange(location: 0, length: 0),
                    replacement: "  ",
                    cursorOffsetInBuffer: 6
                )
        )
    }

    @Test func tabWithCursorAtBodyStartShiftsCursorByTwo() {
        // Cursor right after "- " on offset 2 → after indent at offset 4.
        #expect(
            ListIndentation.indentOutcome(buffer: "- foo", cursorOffset: 2)
                == .replace(
                    range: NSRange(location: 0, length: 0),
                    replacement: "  ",
                    cursorOffsetInBuffer: 4
                )
        )
    }

    // MARK: - Shift-Tab on a bullet line

    @Test func outdentOnIndentedBulletRemovesTwoLeadingSpaces() {
        // "  - foo|" (cursor at 7) → "- foo|" (cursor at 5)
        #expect(
            ListIndentation.outdentOutcome(buffer: "  - foo", cursorOffset: 7)
                == .replace(
                    range: NSRange(location: 0, length: 2),
                    replacement: "",
                    cursorOffsetInBuffer: 5
                )
        )
    }

    @Test func outdentOnDoubleIndentedBulletRemovesTwoSpaces() {
        // "    - foo" → "  - foo"
        #expect(
            ListIndentation.outdentOutcome(buffer: "    - foo", cursorOffset: 9)
                == .replace(
                    range: NSRange(location: 0, length: 2),
                    replacement: "",
                    cursorOffsetInBuffer: 7
                )
        )
    }

    @Test func outdentOnTopLevelBulletIsNoOp() {
        // No leading whitespace → nothing to remove. Bear behaviour: no-op
        // (does NOT consume the marker character).
        #expect(
            ListIndentation.outdentOutcome(buffer: "- foo", cursorOffset: 5)
                == .noOp
        )
    }

    @Test func outdentOnSingleSpaceBulletRemovesOneSpace() {
        // Defensive: indent unit is 2 but we shouldn't lose user data if they
        // typed a single-space indent. Outdent removes whatever indent exists
        // up to the indent unit (max 2).
        #expect(
            ListIndentation.outdentOutcome(buffer: " - foo", cursorOffset: 6)
                == .replace(
                    range: NSRange(location: 0, length: 1),
                    replacement: "",
                    cursorOffsetInBuffer: 5
                )
        )
    }

    @Test func outdentOnTabIndentedBulletRemovesOneTab() {
        // Per spec: tabs are accepted as indent input. Outdent strips one tab
        // at a time (not two spaces' worth).
        #expect(
            ListIndentation.outdentOutcome(buffer: "\t- foo", cursorOffset: 6)
                == .replace(
                    range: NSRange(location: 0, length: 1),
                    replacement: "",
                    cursorOffsetInBuffer: 5
                )
        )
    }

    // MARK: - Shift-Tab on ordered + task

    @Test func outdentOnIndentedOrderedItemRemovesTwoSpaces() {
        #expect(
            ListIndentation.outdentOutcome(buffer: "  1. foo", cursorOffset: 8)
                == .replace(
                    range: NSRange(location: 0, length: 2),
                    replacement: "",
                    cursorOffsetInBuffer: 6
                )
        )
    }

    @Test func outdentOnIndentedTaskItemRemovesTwoSpaces() {
        #expect(
            ListIndentation.outdentOutcome(buffer: "  - [ ] foo", cursorOffset: 11)
                == .replace(
                    range: NSRange(location: 0, length: 2),
                    replacement: "",
                    cursorOffsetInBuffer: 9
                )
        )
    }

    // MARK: - Shift-Tab on non-list line

    @Test func outdentOnPlainLineIsNoOp() {
        #expect(
            ListIndentation.outdentOutcome(buffer: "  hello", cursorOffset: 7)
                == .noOp
        )
    }

    @Test func outdentOnEmptyBufferIsNoOp() {
        #expect(
            ListIndentation.outdentOutcome(buffer: "", cursorOffset: 0)
                == .noOp
        )
    }
}
