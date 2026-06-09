import Foundation
import Testing

@testable import MarcdownStyling

// MARK: - Expected production API (to be implemented by guy)
//
// `OrderedListRenumber` is a pure helper invoked by the editor after any edit
// that may have changed the ordering of an ordered-list run (Enter, Backspace,
// Tab, Shift-Tab on an ordered item). It walks the buffer from the anchor line
// outward to find the contiguous run at the same indent depth, then rewrites
// each item's number so the sequence is consecutive starting from the run's
// first item.
//
//   public enum RenumberOutcome: Sendable, Equatable {
//       case noOp
//       case rewrite(newBuffer: String, newCursorOffset: Int)
//   }
//
//   public enum OrderedListRenumber {
//       public static func renumberRun(
//           buffer: String,
//           anchorOffset: Int,
//           cursorOffset: Int
//       ) -> RenumberOutcome
//   }
//
// Contract notes:
// - The run is the maximal consecutive sequence of lines whose `ListLineScanner`
//   shape is `.complete(.ordered)` AND share the same `indentLength` as the
//   anchor line.
// - The first number of the run is preserved (so a list "5. a / 6. b" that
//   gets a new item inserted between renumbers consistently from 5).
// - Cursor offset is adjusted by the net byte delta of the rewrite. If the
//   cursor lies in a digit run that grows/shrinks (e.g. "9. foo" → "10. foo"),
//   it lands at the body-start of that item.
// - Different indent depths are independent runs. Renumbering only touches the
//   anchor's depth; nested ordered sub-lists are NOT affected.

@Suite("OrderedListRenumber")
struct OrderedListRenumberTests {

    // MARK: - Anchor not in an ordered run

    @Test func anchorOnPlainLineIsNoOp() {
        #expect(
            OrderedListRenumber.renumberRun(
                buffer: "hello",
                anchorOffset: 0,
                cursorOffset: 5
            ) == .noOp
        )
    }

    @Test func anchorOnBulletLineIsNoOp() {
        #expect(
            OrderedListRenumber.renumberRun(
                buffer: "- foo",
                anchorOffset: 0,
                cursorOffset: 5
            ) == .noOp
        )
    }

    @Test func anchorOnSingleOrderedItemDoesNothing() {
        // Run is just "1. foo" — already consecutive. Helper still returns
        // `.rewrite` with an identical buffer (idempotent rewrite) OR `.noOp`.
        // We require idempotence: same content out = `.noOp` to avoid undo
        // bloat.
        #expect(
            OrderedListRenumber.renumberRun(
                buffer: "1. foo",
                anchorOffset: 0,
                cursorOffset: 6
            ) == .noOp
        )
    }

    // MARK: - Renumber after insertion (Section 5.3 acceptance #4)

    @Test func runAfterInsertionRenumbersDownstream() {
        // Buffer reflects state immediately after Enter continuation produced
        // "1. a\n2. \n2. b" (the new "2. " was inserted, but the old "2. b"
        // wasn't renumbered yet). Renumber pass turns it into:
        //   "1. a\n2. \n3. b"
        let buffer = "1. a\n2. \n2. b"
        let outcome = OrderedListRenumber.renumberRun(
            buffer: buffer,
            anchorOffset: 5,        // start of the new "2. " line
            cursorOffset: 8         // cursor at end of marker on the new line
        )
        #expect(
            outcome == .rewrite(
                newBuffer: "1. a\n2. \n3. b",
                newCursorOffset: 8
            )
        )
    }

    @Test func runStartingMidDocumentPreservesFirstNumber() {
        // First item is "5." — renumber must continue from 5, not reset to 1.
        let buffer = "preamble\n\n5. a\n7. b\n9. c"
        let outcome = OrderedListRenumber.renumberRun(
            buffer: buffer,
            anchorOffset: 10,       // anchor on "5. a"
            cursorOffset: 14
        )
        #expect(
            outcome == .rewrite(
                newBuffer: "preamble\n\n5. a\n6. b\n7. c",
                newCursorOffset: 14
            )
        )
    }

    // MARK: - Renumber after deletion (Section 5.4 acceptance #5)

    @Test func runAfterDeletionRenumbersDownstream() {
        // After Backspace consumed "2. |" item, buffer is "1. a\n3. c".
        // Renumber pass should turn it into "1. a\n2. c".
        let buffer = "1. a\n3. c"
        let outcome = OrderedListRenumber.renumberRun(
            buffer: buffer,
            anchorOffset: 0,        // anchor on the still-existing first item
            cursorOffset: 4         // cursor at end of "1. a"
        )
        #expect(
            outcome == .rewrite(
                newBuffer: "1. a\n2. c",
                newCursorOffset: 4
            )
        )
    }

    // MARK: - Indent-depth isolation

    @Test func nestedOrderedRunIsIndependentOfParent() {
        // Parent run: "1. a", "2. d" at depth 0.
        // Nested run under "1. a": "  1. b", "  2. c" at depth 2.
        // Anchoring on the parent run only renumbers depth-0 items.
        let buffer = "1. a\n  1. b\n  2. c\n5. d"
        let outcome = OrderedListRenumber.renumberRun(
            buffer: buffer,
            anchorOffset: 0,        // anchor at depth 0
            cursorOffset: 0
        )
        #expect(
            outcome == .rewrite(
                newBuffer: "1. a\n  1. b\n  2. c\n2. d",
                newCursorOffset: 0
            )
        )
    }

    @Test func anchoringOnNestedRunOnlyRenumbersThatDepth() {
        // Same buffer; anchor on the nested "  3. c" (which is wrong — should
        // be 2). Parent items keep their existing numbers.
        let buffer = "1. a\n  1. b\n  3. c\n5. d"
        let outcome = OrderedListRenumber.renumberRun(
            buffer: buffer,
            anchorOffset: 5,        // anchor at depth 2 (the "  1. b" line)
            cursorOffset: 5
        )
        #expect(
            outcome == .rewrite(
                newBuffer: "1. a\n  1. b\n  2. c\n5. d",
                newCursorOffset: 5
            )
        )
    }

    // MARK: - Digit-width changes ripple cursor offset

    @Test func renumberAcrossDigitWidthBoundaryShiftsCursor() {
        // Items "8. a", "9. b", "1. c" (broken — needs renumber).
        // Renumber rewrites to "8. a", "9. b", "10. c". The third line grows
        // by one digit. Cursor on line 3 at end shifts +1.
        let buffer = "8. a\n9. b\n1. c"
        // Line 3 starts at offset 10. Cursor at end of "1. c" = offset 14.
        let outcome = OrderedListRenumber.renumberRun(
            buffer: buffer,
            anchorOffset: 0,
            cursorOffset: 14
        )
        #expect(
            outcome == .rewrite(
                newBuffer: "8. a\n9. b\n10. c",
                newCursorOffset: 15
            )
        )
    }

    @Test func renumberShrinkingDigitsShiftsCursor() {
        // "9. a", "11. b", "12. c" — renumber should give 9/10/11.
        // Line 2 shrinks from "11. b" to "10. b" (no change in width).
        // Line 3 shrinks from "12. c" to "11. c" (no change in width).
        // Cursor on line 3 stays put.
        let buffer = "9. a\n11. b\n12. c"
        let outcome = OrderedListRenumber.renumberRun(
            buffer: buffer,
            anchorOffset: 0,
            cursorOffset: 16
        )
        #expect(
            outcome == .rewrite(
                newBuffer: "9. a\n10. b\n11. c",
                newCursorOffset: 16
            )
        )
    }

    // MARK: - Run boundary detection

    @Test func runBreaksOnPlainLineGap() {
        // "1. a\nplain\n3. b" — the plain line splits this into two runs of
        // length 1 each. Anchoring on the first does nothing (single-item
        // run, already consecutive). Anchoring on "3. b" likewise no-ops.
        let buffer = "1. a\nplain\n3. b"
        #expect(
            OrderedListRenumber.renumberRun(
                buffer: buffer,
                anchorOffset: 0,
                cursorOffset: 0
            ) == .noOp
        )
    }

    @Test func runBreaksOnBulletLine() {
        // "1. a\n- b\n3. c" — the bullet splits the ordered run.
        let buffer = "1. a\n- b\n3. c"
        #expect(
            OrderedListRenumber.renumberRun(
                buffer: buffer,
                anchorOffset: 0,
                cursorOffset: 0
            ) == .noOp
        )
    }
}
