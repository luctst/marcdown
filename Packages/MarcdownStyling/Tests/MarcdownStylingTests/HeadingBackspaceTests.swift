import Foundation
import Testing

@testable import MarcdownStyling

// MARK: - Expected production API (to be implemented by guy)
//
// Spec §8.2: "Backspace at the start of an empty heading line (`# |`) should
// remove the marker characters and leave an empty plain line — analogous to
// exiting an empty list item."
//
// A pure helper mirrors the shape of the other continuation helpers so the
// editor coordinator can compose them without per-helper conditionals.
//
//   public enum HeadingBackspaceOutcome: Sendable, Equatable {
//       case standard
//       case replace(range: NSRange, cursorOffsetInBuffer: Int)
//   }
//
//   public enum HeadingContinuation {
//       /// Atomic strip of an empty ATX heading marker when Backspace is hit
//       /// at the marker end. All other positions return `.standard`.
//       public static func backspaceOutcome(buffer: String, cursorOffset: Int) -> HeadingBackspaceOutcome
//   }

@Suite("HeadingContinuation backspace")
struct HeadingBackspaceTests {

    // MARK: - Empty heading at marker end

    @Test func backspaceAtEndOfEmptyH1AtBufferStartStripsMarker() {
        // "# " (cursor at offset 2) — Backspace strips the marker. Cursor lands
        // at the start of the (now empty plain) line. Atomic delete also eats
        // the preceding `\n` if one exists, mirroring the list helpers.
        #expect(
            HeadingContinuation.backspaceOutcome(buffer: "# ", cursorOffset: 2)
                == .replace(
                    range: NSRange(location: 0, length: 2),
                    cursorOffsetInBuffer: 0
                )
        )
    }

    @Test func backspaceAtEndOfEmptyH2AtBufferStartStripsMarker() {
        #expect(
            HeadingContinuation.backspaceOutcome(buffer: "## ", cursorOffset: 3)
                == .replace(
                    range: NSRange(location: 0, length: 3),
                    cursorOffsetInBuffer: 0
                )
        )
    }

    @Test func backspaceAtEndOfEmptyH6AtBufferStartStripsMarker() {
        // "###### " — 7 chars total.
        #expect(
            HeadingContinuation.backspaceOutcome(buffer: "###### ", cursorOffset: 7)
                == .replace(
                    range: NSRange(location: 0, length: 7),
                    cursorOffsetInBuffer: 0
                )
        )
    }

    @Test func backspaceAtEndOfEmptyHeadingAfterContentEatsPrecedingNewline() {
        // "hello\n# " — Backspace at offset 8 eats `\n# ` (length 3).
        #expect(
            HeadingContinuation.backspaceOutcome(buffer: "hello\n# ", cursorOffset: 8)
                == .replace(
                    range: NSRange(location: 5, length: 3),
                    cursorOffsetInBuffer: 5
                )
        )
    }

    // MARK: - Non-empty heading → standard

    @Test func backspaceOnNonEmptyHeadingBodyIsStandard() {
        // Cursor at end of "# Hello" — standard char delete (deletes 'o').
        #expect(
            HeadingContinuation.backspaceOutcome(buffer: "# Hello", cursorOffset: 7)
                == .standard
        )
    }

    @Test func backspaceAtBodyStartOfNonEmptyHeadingIsStandard() {
        // Cursor right after "# " on a non-empty heading deletes one char of
        // the marker (the trailing space), per AppKit. Helper must not
        // hijack — this is the "user wants to demote" path.
        #expect(
            HeadingContinuation.backspaceOutcome(buffer: "# Hello", cursorOffset: 2)
                == .standard
        )
    }

    // MARK: - Non-headings

    @Test func backspaceOnPlainLineIsStandard() {
        #expect(
            HeadingContinuation.backspaceOutcome(buffer: "hello", cursorOffset: 5)
                == .standard
        )
    }

    @Test func backspaceOnBulletLineIsStandard() {
        // Bullet lines are handled by `ListContinuation`; the heading helper
        // must not touch them.
        #expect(
            HeadingContinuation.backspaceOutcome(buffer: "- foo", cursorOffset: 5)
                == .standard
        )
    }

    @Test func backspaceOnEmptyBufferIsStandard() {
        #expect(
            HeadingContinuation.backspaceOutcome(buffer: "", cursorOffset: 0)
                == .standard
        )
    }
}
