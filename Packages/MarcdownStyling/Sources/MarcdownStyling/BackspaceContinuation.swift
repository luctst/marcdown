import Foundation

/// Outcome of pressing Backspace inside a buffer that may contain a task-list
/// marker.
public enum BackspaceOutcome: Sendable, Equatable {
    /// Caller should let AppKit handle Backspace normally.
    case standard
    /// Replace `range` with `""`, then place the cursor at `cursorOffsetInBuffer`.
    case replace(range: NSRange, cursorOffsetInBuffer: Int)
}

/// Pure helper that decides whether a Backspace keystroke should atomically
/// remove an empty task-list marker (or a partially-typed marker) instead of
/// chipping away one UTF-16 unit at a time.
///
/// Buffer-relative API mirrors `TaskListContinuation` — caller passes the
/// entire NSTextStorage string and absolute cursor offset, gets back either
/// `.standard` or a single absolute-range edit. Implementation must NOT use
/// `NSString.paragraphRange(for:)` for the same reason: the cursor-after-`\n`
/// case returns a zero-length range and masks the line we want to inspect.
public enum BackspaceContinuation {
    /// Decide the Backspace outcome for `buffer` with `cursorOffset`.
    ///
    /// - `buffer`: the entire NSTextStorage string.
    /// - `cursorOffset`: absolute UTF-16 cursor position.
    public static func deleteOutcome(buffer: String, cursorOffset: Int) -> BackspaceOutcome {
        let units = Array(buffer.utf16)
        let length = units.count
        guard cursorOffset >= 0, cursorOffset <= length else { return .standard }

        // Compute lineStart / lineEnd by scanning `\n` boundaries manually.
        var lineStart = cursorOffset
        while lineStart > 0, units[lineStart - 1] != 0x0A {
            lineStart -= 1
        }
        var lineEnd = cursorOffset
        while lineEnd < length, units[lineEnd] != 0x0A {
            lineEnd += 1
        }

        let lineLength = lineEnd - lineStart
        let lineContent = substring(units: units, from: lineStart, to: lineEnd)
        let cursorOffsetInLine = cursorOffset - lineStart

        switch CheckboxLineScanner.scan(line: lineContent) {
        case .none:
            return .standard

        case .partial(let indentLength, let concealLength):
            // Total partial extent in line-relative offsets.
            let partialEnd = indentLength + concealLength
            // Atomic delete only when cursor sits at the end of the partial
            // AND nothing follows on the line.
            guard
                cursorOffsetInLine == partialEnd,
                lineLength == partialEnd
            else { return .standard }
            return atomicDelete(lineStart: lineStart, lineEnd: lineEnd)

        case .complete(_, let bracketLocation, _):
            let bodyStart = bracketLocation + 4 // past "[X] "
            let bodyLength = lineLength - bodyStart
            // Atomic delete only when cursor is at the end of an empty marker.
            guard
                cursorOffsetInLine == bodyStart,
                bodyLength == 0
            else { return .standard }
            return atomicDelete(lineStart: lineStart, lineEnd: lineEnd)
        }
    }

    /// Atomic delete of the entire line content. If a preceding `\n` exists
    /// just before `lineStart`, eat it too so the cursor lands at the end of
    /// the previous line.
    private static func atomicDelete(lineStart: Int, lineEnd: Int) -> BackspaceOutcome {
        if lineStart > 0 {
            let range = NSRange(location: lineStart - 1, length: lineEnd - lineStart + 1)
            return .replace(range: range, cursorOffsetInBuffer: lineStart - 1)
        }
        let range = NSRange(location: 0, length: lineEnd)
        return .replace(range: range, cursorOffsetInBuffer: 0)
    }

    /// Builds a String from `units[from..<to]` for line classification.
    /// UTF-16 round-trip is safe — line content can include any character.
    private static func substring(units: [UInt16], from: Int, to: Int) -> String {
        let slice = Array(units[from..<to])
        if slice.isEmpty { return "" }
        return slice.withUnsafeBufferPointer {
            String(utf16CodeUnits: $0.baseAddress!, count: $0.count)
        }
    }
}
