import Foundation
import Testing

@testable import MarcdownStyling

// Thomas §8 push-back: when Backspace joins a list line into the line above,
// the joined-in marker characters must be stripped — leaving them in the
// middle of the resulting line is a known-bad experience.
//
// MARK: - Expected production API (to be implemented by guy)
//
// The contract lives in `ListContinuation.backspaceOutcome`. We add a new
// trigger position: cursor at `lineStart + indentLength` (i.e. just before
// the marker character) on a complete list line, with the previous line
// being non-empty. The outcome is a replace that deletes:
//   - the preceding `\n`
//   - the leading indent of the current line
//   - the marker characters (e.g. `- ` or `1. `) of the current line
//
// Cursor lands at the end of the previous line's content.
//
// Today's helper returns `.standard` from this position (it only triggers on
// empty-body lines and at-end-of-partial-marker). The new behaviour expands
// the trigger.

@Suite("List item join via backspace strips joined marker")
struct ListJoinTests {

    @Test func backspaceAtMarkerStartOfBulletWithPreviousBulletStripsMarker() {
        // Buffer:    "- foo\n- bar"
        // Offsets:    0     5 6 7   10
        // Cursor at start of "- bar" line's MARKER (offset 6).
        // Pressing Backspace from this position joins the two list lines into
        // "- foobar" (the second item's `- ` marker is dropped).
        let buffer = "- foo\n- bar"
        #expect(
            ListContinuation.backspaceOutcome(buffer: buffer, cursorOffset: 6)
                == .replace(
                    range: NSRange(location: 5, length: 3),  // `\n- `
                    cursorOffsetInBuffer: 5
                )
        )
    }

    @Test func backspaceAtMarkerStartOfOrderedWithPreviousOrderedStripsMarker() {
        // Buffer:    "1. foo\n2. bar"
        // Offsets:    0      6 7  11  ...
        // Cursor at start of "2. bar" marker (offset 7) → join.
        let buffer = "1. foo\n2. bar"
        #expect(
            ListContinuation.backspaceOutcome(buffer: buffer, cursorOffset: 7)
                == .replace(
                    range: NSRange(location: 6, length: 4),  // `\n2. `
                    cursorOffsetInBuffer: 6
                )
        )
    }

    @Test func backspaceAtMarkerStartOfIndentedBulletStripsIndentAndMarker() {
        // Buffer:    "- foo\n  - bar"
        // Offsets:    0     5 6 7 8 9   12
        // Cursor at start of the indented marker (offset 8 — just before `-`).
        // The join strips the `\n`, the 2-space indent, and the marker `- `.
        let buffer = "- foo\n  - bar"
        #expect(
            ListContinuation.backspaceOutcome(buffer: buffer, cursorOffset: 8)
                == .replace(
                    range: NSRange(location: 5, length: 5),  // `\n  - `
                    cursorOffsetInBuffer: 5
                )
        )
    }

    @Test func backspaceAtMarkerStartWithPlainPreviousLineStillStripsMarker() {
        // Even when the line above isn't a list line, the marker characters of
        // the current list line should be stripped on join — otherwise the
        // user gets a stray `- ` mid-paragraph. (Bear behaviour per Thomas.)
        let buffer = "hello\n- bar"
        #expect(
            ListContinuation.backspaceOutcome(buffer: buffer, cursorOffset: 6)
                == .replace(
                    range: NSRange(location: 5, length: 3),  // `\n- `
                    cursorOffsetInBuffer: 5
                )
        )
    }

    @Test func backspaceMidMarkerStaysStandard() {
        // Cursor in the middle of the marker (offset 7 in "- foo\n- bar",
        // which is between `-` and ` ` on the second line). This is NOT the
        // join trigger; standard char delete runs.
        let buffer = "- foo\n- bar"
        #expect(
            ListContinuation.backspaceOutcome(buffer: buffer, cursorOffset: 7)
                == .standard
        )
    }

    @Test func backspaceAtBodyStartOfNonEmptyBulletStaysStandard() {
        // Cursor right after the marker (offset 8 = body start of "- bar").
        // Standard single-char delete (lands at offset 7, between marker char
        // and space). The join only triggers AT the marker start.
        let buffer = "- foo\n- bar"
        #expect(
            ListContinuation.backspaceOutcome(buffer: buffer, cursorOffset: 8)
                == .standard
        )
    }

    @Test func backspaceAtMarkerStartOfFirstLineIsStandard() {
        // No preceding `\n` → cannot join → standard char delete.
        // (Cursor at offset 0 of "- foo" — there is no previous line to merge
        // into. AppKit's default delete-before-start is a no-op.)
        let buffer = "- foo"
        #expect(
            ListContinuation.backspaceOutcome(buffer: buffer, cursorOffset: 0)
                == .standard
        )
    }
}
