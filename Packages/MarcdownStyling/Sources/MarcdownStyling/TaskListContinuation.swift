import Foundation

/// Outcome of pressing Return inside (or at the end of) a task-list line.
public enum TaskListEnterOutcome: Sendable, Equatable {
    /// Caller should let AppKit handle Return normally.
    case noOp

    /// Replace `range` (UTF-16 units, absolute in the buffer) with `replacement`,
    /// then place the cursor at `cursorOffsetInBuffer` (absolute UTF-16 offset).
    case replace(range: NSRange, replacement: String, cursorOffsetInBuffer: Int)
}

/// Pure helper that decides what to do when Return is pressed in a buffer that
/// may or may not contain task-list markers.
///
/// Buffer-relative API: caller passes the entire NSTextStorage string and the
/// absolute cursor offset, gets back either `.noOp` or a single absolute-range
/// edit. Implementation must NOT use `NSString.paragraphRange(for:)` — v1's
/// orphan-trailing-paragraph bug came from `paragraphRange` returning
/// `{N, 0}` past a trailing `\n`.
public enum TaskListContinuation {
    /// Decide the Enter outcome for `buffer` with `cursorOffset`.
    ///
    /// - `buffer`: the entire NSTextStorage string.
    /// - `cursorOffset`: absolute UTF-16 cursor position.
    public static func enterOutcome(buffer: String, cursorOffset: Int) -> TaskListEnterOutcome {
        let units = Array(buffer.utf16)
        let length = units.count
        guard cursorOffset >= 0, cursorOffset <= length else { return .noOp }

        // 1. Compute lineStart / lineEnd by scanning `\n` boundaries manually.
        var lineStart = cursorOffset
        while lineStart > 0, units[lineStart - 1] != 0x0A {
            lineStart -= 1
        }
        var lineEnd = cursorOffset
        while lineEnd < length, units[lineEnd] != 0x0A {
            lineEnd += 1
        }

        let lineContent = substring(units: units, from: lineStart, to: lineEnd)
        let cursorOffsetInLine = cursorOffset - lineStart

        let shape = CheckboxLineScanner.scan(line: lineContent)

        switch shape {
        case .none:
            // Plain line — let AppKit insert a normal newline. We deliberately
            // do NOT scan back for a previous task line: after the empty-task
            // exit branch below strips a marker, the user lands on a blank
            // paragraph and the *next* Enter must produce a plain newline,
            // not re-enter the list. Continuation from a previous task line
            // is reachable via the atomic-Backspace handler instead.
            return .noOp
        case .partial:
            return .noOp
        case .complete(let indentLength, let bracketLocation, _):
            let bodyStart = bracketLocation + 4 // past "[X] "
            let lineLength = lineEnd - lineStart
            let bodyLength = lineLength - bodyStart

            // Cursor before / inside the marker — fall through.
            if cursorOffsetInLine < bodyStart {
                return .noOp
            }

            // Empty marker → exit the list. Strip the marker (indent + "- [X] ")
            // but keep the line itself so the user lands on a blank paragraph
            // and can type plain markdown. Subsequent Enter keystrokes on the
            // resulting blank line just insert plain `\n` (the `.none` branch
            // returns `.noOp`, which we deliberately keep helper-free).
            if bodyLength <= 0 {
                return .replace(
                    range: NSRange(location: lineStart, length: bodyStart),
                    replacement: "",
                    cursorOffsetInBuffer: lineStart
                )
            }

            // Non-empty marker — insert continuation at cursor.
            let indent = asciiWhitespacePrefix(units: units, from: lineStart, count: indentLength)
            let replacement = "\n" + indent + "- [ ] "
            let replacementUTF16Count = replacement.utf16.count
            return .replace(
                range: NSRange(location: cursorOffset, length: 0),
                replacement: replacement,
                cursorOffsetInBuffer: cursorOffset + replacementUTF16Count
            )
        }
    }

    /// Builds a String from `units[from..<to]`. Used to extract a single line
    /// for scanner classification. UTF-16 round-trip is safe — line content
    /// can include any character.
    private static func substring(units: [UInt16], from: Int, to: Int) -> String {
        let slice = Array(units[from..<to])
        if slice.isEmpty { return "" }
        return slice.withUnsafeBufferPointer {
            String(utf16CodeUnits: $0.baseAddress!, count: $0.count)
        }
    }

    /// Reads `count` ASCII whitespace units (space / tab) starting at `from`
    /// into a String. Indents are guaranteed by the scanner to be 0x20 / 0x09
    /// only, so this is a safe Unicode.Scalar construction.
    private static func asciiWhitespacePrefix(units: [UInt16], from: Int, count: Int) -> String {
        var indent = ""
        indent.reserveCapacity(count)
        for k in 0..<count {
            indent.append(Character(Unicode.Scalar(units[from + k])!))
        }
        return indent
    }
}
