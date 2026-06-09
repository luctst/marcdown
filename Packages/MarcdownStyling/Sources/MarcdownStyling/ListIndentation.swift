import Foundation

/// Outcome of pressing Tab / Shift-Tab on a buffer where the cursor sits on
/// a list line. Mirrors the shape of `ListContinuation.ListEnterOutcome`:
/// pure helper, buffer-relative, UTF-16 throughout, AppKit-free.
public enum ListIndentOutcome: Sendable, Equatable {
    /// Caller should fall through to AppKit. On a non-list line this means
    /// Tab inserts a literal tab (the spec deliberately diverges from Bear's
    /// "Tab on non-list line creates a code block" behaviour — see Spec §19).
    case noOp

    /// Replace `range` with `replacement`, then place the cursor at
    /// `cursorOffsetInBuffer` (absolute UTF-16 offset).
    case replace(range: NSRange, replacement: String, cursorOffsetInBuffer: Int)
}

/// Pure helper that decides Tab / Shift-Tab outcomes for a list (or task)
/// line. Implements Spec §4.4 / §4.5 and the corresponding ordered/task
/// variants. The indent unit is exactly 2 ASCII spaces — tabs are accepted
/// as legacy input on outdent but new indents always emit spaces so the
/// exported markdown is CommonMark-valid.
public enum ListIndentation {

    /// Tab on a list/task line: prepend `"  "` (2 spaces) at lineStart.
    /// Returns `.noOp` on a non-list line so the caller can fall through to
    /// AppKit's default tab insertion.
    public static func indentOutcome(buffer: String, cursorOffset: Int) -> ListIndentOutcome {
        let units = Array(buffer.utf16)
        let length = units.count
        guard cursorOffset >= 0, cursorOffset <= length else { return .noOp }

        let (lineStart, lineEnd) = lineRange(units: units, cursor: cursorOffset)
        guard lineEnd > lineStart else { return .noOp }

        let lineContent = substring(units: units, from: lineStart, to: lineEnd)
        guard isListOrTaskLine(line: lineContent) else { return .noOp }

        return .replace(
            range: NSRange(location: lineStart, length: 0),
            replacement: "  ",
            cursorOffsetInBuffer: cursorOffset + 2
        )
    }

    /// Shift-Tab on a list/task line: strip up to one indent unit at lineStart.
    /// - Two leading spaces → strip both.
    /// - One leading tab → strip the tab.
    /// - One leading space → strip just that space (defensive — preserves
    ///   the user's odd indent rather than refusing).
    /// Returns `.noOp` if there is no leading whitespace, or on a non-list line.
    public static func outdentOutcome(buffer: String, cursorOffset: Int) -> ListIndentOutcome {
        let units = Array(buffer.utf16)
        let length = units.count
        guard cursorOffset >= 0, cursorOffset <= length else { return .noOp }

        let (lineStart, lineEnd) = lineRange(units: units, cursor: cursorOffset)
        guard lineEnd > lineStart else { return .noOp }

        let lineContent = substring(units: units, from: lineStart, to: lineEnd)
        guard isListOrTaskLine(line: lineContent) else { return .noOp }

        // Determine how many leading whitespace units to strip.
        let stripLength: Int
        if lineEnd - lineStart >= 1, units[lineStart] == 0x09 {
            stripLength = 1
        } else if lineEnd - lineStart >= 2,
            units[lineStart] == 0x20, units[lineStart + 1] == 0x20
        {
            stripLength = 2
        } else if lineEnd - lineStart >= 1, units[lineStart] == 0x20 {
            stripLength = 1
        } else {
            return .noOp
        }

        // Cursor adjustment: subtract however much of the stripped range lies
        // before the cursor.
        let cursorOffsetInLine = cursorOffset - lineStart
        let removedBeforeCursor = min(stripLength, max(0, cursorOffsetInLine))
        return .replace(
            range: NSRange(location: lineStart, length: stripLength),
            replacement: "",
            cursorOffsetInBuffer: cursorOffset - removedBeforeCursor
        )
    }

    // MARK: - Helpers

    /// Returns true if the line is a bullet/ordered list (`ListLineScanner`
    /// reports `.complete` or `.partial`) OR a task list (`CheckboxLineScanner`
    /// reports `.complete` or `.partial`). Empty / plain lines return false.
    private static func isListOrTaskLine(line: String) -> Bool {
        switch CheckboxLineScanner.scan(line: line) {
        case .complete, .partial:
            return true
        case .none:
            break
        }
        switch ListLineScanner.scan(line: line) {
        case .complete, .partial:
            return true
        case .none:
            return false
        }
    }

    /// Locate the `\n` boundaries surrounding the cursor.
    private static func lineRange(units: [UInt16], cursor: Int) -> (Int, Int) {
        var lineStart = cursor
        while lineStart > 0, units[lineStart - 1] != 0x0A {
            lineStart -= 1
        }
        var lineEnd = cursor
        while lineEnd < units.count, units[lineEnd] != 0x0A {
            lineEnd += 1
        }
        return (lineStart, lineEnd)
    }

    private static func substring(units: [UInt16], from: Int, to: Int) -> String {
        let slice = Array(units[from..<to])
        if slice.isEmpty { return "" }
        return slice.withUnsafeBufferPointer {
            String(utf16CodeUnits: $0.baseAddress!, count: $0.count)
        }
    }
}
