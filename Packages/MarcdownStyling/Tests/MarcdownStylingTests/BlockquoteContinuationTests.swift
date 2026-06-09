import Foundation
import Testing

@testable import MarcdownStyling

// MARK: - Expected production API (to be implemented by guy)
//
// `BlockquoteContinuation` mirrors `ListContinuation` / `TaskListContinuation`
// shape: pure helper, buffer-relative, UTF-16 throughout, AppKit-free. Drives
// the Enter / Backspace behaviour for lines starting with `>` markers.
//
//   public enum BlockquoteEnterOutcome: Sendable, Equatable {
//       case noOp
//       case replace(range: NSRange, replacement: String, cursorOffsetInBuffer: Int)
//   }
//
//   public enum BlockquoteBackspaceOutcome: Sendable, Equatable {
//       case standard
//       case replace(range: NSRange, cursorOffsetInBuffer: Int)
//   }
//
//   public enum BlockquoteContinuation {
//       public static func enterOutcome(buffer: String, cursorOffset: Int) -> BlockquoteEnterOutcome
//       public static func backspaceOutcome(buffer: String, cursorOffset: Int) -> BlockquoteBackspaceOutcome
//   }
//
// Contract (Spec §9):
// - On non-empty `> body` Enter, insert "\n> " continuation at cursor.
// - On empty `> ` Enter, strip the entire `> ` prefix from the line.
// - On nested `>> ` Enter (empty), strip ONE level only (`>> ` → `> `).
// - On empty `> ` Backspace, atomic delete (line + preceding newline).
// - Plain lines / lines without `>` return `.noOp` / `.standard`.

@Suite("BlockquoteContinuation")
struct BlockquoteContinuationTests {

    // MARK: - Enter on non-empty blockquote

    @Test func endOfBlockquoteLineSplits() {
        // "> hello|"
        let buffer = "> hello"
        #expect(
            BlockquoteContinuation.enterOutcome(buffer: buffer, cursorOffset: 7)
                == .replace(
                    range: NSRange(location: 7, length: 0),
                    replacement: "\n> ",
                    cursorOffsetInBuffer: 10
                )
        )
    }

    @Test func midBlockquoteSplits() {
        // "> hel|lo" — split mid-body. Continuation inserted at cursor, tail
        // "lo" carries down to the new line after the marker.
        let buffer = "> hello"
        #expect(
            BlockquoteContinuation.enterOutcome(buffer: buffer, cursorOffset: 5)
                == .replace(
                    range: NSRange(location: 5, length: 0),
                    replacement: "\n> ",
                    cursorOffsetInBuffer: 8
                )
        )
    }

    @Test func nestedBlockquoteContinuationPreservesDepth() {
        // ">> hello" — Enter continues with ">> ".
        let buffer = ">> hello"
        #expect(
            BlockquoteContinuation.enterOutcome(buffer: buffer, cursorOffset: 8)
                == .replace(
                    range: NSRange(location: 8, length: 0),
                    replacement: "\n>> ",
                    cursorOffsetInBuffer: 12
                )
        )
    }

    // MARK: - Enter on empty blockquote (exit one level)

    @Test func emptyBlockquoteAtBufferStartStripsPrefix() {
        // "> " — Enter strips the entire prefix.
        let buffer = "> "
        #expect(
            BlockquoteContinuation.enterOutcome(buffer: buffer, cursorOffset: 2)
                == .replace(
                    range: NSRange(location: 0, length: 2),
                    replacement: "",
                    cursorOffsetInBuffer: 0
                )
        )
    }

    @Test func emptyBlockquoteAfterContentStripsPrefix() {
        // "> foo\n> |" — Enter strips just the prefix of the empty line.
        let buffer = "> foo\n> "
        #expect(
            BlockquoteContinuation.enterOutcome(buffer: buffer, cursorOffset: 8)
                == .replace(
                    range: NSRange(location: 6, length: 2),
                    replacement: "",
                    cursorOffsetInBuffer: 6
                )
        )
    }

    @Test func emptyNestedBlockquoteStripsOneLevelOnly() {
        // ">> " — Enter strips one level, leaving "> " (Spec §9.6).
        let buffer = ">> "
        #expect(
            BlockquoteContinuation.enterOutcome(buffer: buffer, cursorOffset: 3)
                == .replace(
                    range: NSRange(location: 0, length: 3),
                    replacement: "> ",
                    cursorOffsetInBuffer: 2
                )
        )
    }

    // MARK: - Enter falls through

    @Test func cursorBeforeMarkerIsNoOp() {
        #expect(
            BlockquoteContinuation.enterOutcome(buffer: "> foo", cursorOffset: 0)
                == .noOp
        )
    }

    @Test func plainTextLineIsNoOp() {
        #expect(
            BlockquoteContinuation.enterOutcome(buffer: "hello", cursorOffset: 5)
                == .noOp
        )
    }

    @Test func emptyBufferIsNoOp() {
        #expect(
            BlockquoteContinuation.enterOutcome(buffer: "", cursorOffset: 0)
                == .noOp
        )
    }

    // MARK: - Backspace on empty blockquote (atomic)

    @Test func backspaceAtEndOfEmptyBlockquoteAtBufferStartRemovesPrefix() {
        // "> " — Backspace atomically deletes the marker.
        #expect(
            BlockquoteContinuation.backspaceOutcome(buffer: "> ", cursorOffset: 2)
                == .replace(
                    range: NSRange(location: 0, length: 2),
                    cursorOffsetInBuffer: 0
                )
        )
    }

    @Test func backspaceAtEndOfEmptyBlockquoteAfterContentEatsPrecedingNewline() {
        // "line1\n> " — Backspace eats `\n` + `> `.
        #expect(
            BlockquoteContinuation.backspaceOutcome(buffer: "line1\n> ", cursorOffset: 8)
                == .replace(
                    range: NSRange(location: 5, length: 3),
                    cursorOffsetInBuffer: 5
                )
        )
    }

    // MARK: - Backspace standard cases

    @Test func backspaceOnNonEmptyBlockquoteBodyIsStandard() {
        #expect(
            BlockquoteContinuation.backspaceOutcome(buffer: "> foo", cursorOffset: 5)
                == .standard
        )
    }

    @Test func backspaceOnPlainLineIsStandard() {
        #expect(
            BlockquoteContinuation.backspaceOutcome(buffer: "hello", cursorOffset: 5)
                == .standard
        )
    }
}
