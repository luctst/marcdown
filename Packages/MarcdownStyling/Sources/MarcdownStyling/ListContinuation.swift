import Foundation

/// Outcome of pressing Return inside (or at the end of) a plain list-marker
/// line (bullet `- text` / `* text` / `+ text` or ordered `N. text`).
public enum ListEnterOutcome: Sendable, Equatable {
    /// Caller should let AppKit handle Return normally.
    case noOp

    /// Replace `range` (UTF-16 units, absolute in the buffer) with `replacement`,
    /// then place the cursor at `cursorOffsetInBuffer` (absolute UTF-16 offset).
    case replace(range: NSRange, replacement: String, cursorOffsetInBuffer: Int)
}

/// Outcome of pressing Backspace inside a buffer that may contain a plain
/// list-marker.
public enum ListBackspaceOutcome: Sendable, Equatable {
    /// Caller should let AppKit handle Backspace normally.
    case standard
    /// Replace `range` with `""`, then place the cursor at `cursorOffsetInBuffer`.
    case replace(range: NSRange, cursorOffsetInBuffer: Int)
}

/// Pure helper that decides Enter and Backspace outcomes for plain list-item
/// lines (`-`, `*`, `+`, or `N.` markers). Mirrors `TaskListContinuation` /
/// `BackspaceContinuation` exactly — buffer-relative API, manual `\n`
/// boundary scan (never `NSString.paragraphRange(for:)`), UTF-16 throughout.
///
/// Checkbox lines (`- [ ] task`) are NOT handled here: `ListLineScanner`
/// returns `.none` for those, so this helper will return `.noOp` / `.standard`
/// and the caller can fall through to the task-list helpers.
public enum ListContinuation {
    /// Decide the Enter outcome for `buffer` with `cursorOffset`.
    ///
    /// - `buffer`: the entire NSTextStorage string.
    /// - `cursorOffset`: absolute UTF-16 cursor position.
    public static func enterOutcome(buffer: String, cursorOffset: Int) -> ListEnterOutcome {
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

        switch ListLineScanner.scan(line: lineContent) {
        case .none, .partial:
            // Plain line or partially-typed marker — let AppKit insert a
            // normal newline. Mirrors `TaskListContinuation`'s behaviour.
            return .noOp

        case .complete(let indentLength, let markerLength, let kind):
            // `bodyStart` is the line-relative offset where body content
            // begins — right after the marker's trailing space.
            let bodyStart = indentLength + markerLength
            let lineLength = lineEnd - lineStart
            let bodyLength = lineLength - bodyStart

            // Cursor before / inside the marker — fall through.
            if cursorOffsetInLine < bodyStart {
                return .noOp
            }

            // Empty body → exit the list. Strip indent + marker entirely and
            // land the cursor on a blank paragraph (same shape as the
            // empty-task branch in `TaskListContinuation`).
            //
            // Spec §4.3 / acceptance #6: if any content precedes this line,
            // also insert a blank-line separator (CommonMark requires it for
            // subsequent text not to be parsed as part of the list).
            if bodyLength <= 0 {
                if lineStart > 0 {
                    return .replace(
                        range: NSRange(location: lineStart, length: bodyStart),
                        replacement: "\n",
                        cursorOffsetInBuffer: lineStart + 1
                    )
                }
                return .replace(
                    range: NSRange(location: lineStart, length: bodyStart),
                    replacement: "",
                    cursorOffsetInBuffer: lineStart
                )
            }

            // Non-empty body — insert continuation at cursor.
            let indent = asciiWhitespacePrefix(
                units: units,
                from: lineStart,
                count: indentLength
            )
            let continuation: String
            switch kind {
            case .bullet:
                // Preserve the original marker char (`-`, `*`, or `+`) verbatim
                // by reading it back from the source.
                let markerCharUnit = units[lineStart + indentLength]
                let markerChar = Character(Unicode.Scalar(markerCharUnit)!)
                continuation = "\n" + indent + String(markerChar) + " "
            case .ordered(let number, _):
                continuation = "\n" + indent + "\(number + 1). "
            }

            let replacementUTF16Count = continuation.utf16.count
            return .replace(
                range: NSRange(location: cursorOffset, length: 0),
                replacement: continuation,
                cursorOffsetInBuffer: cursorOffset + replacementUTF16Count
            )
        }
    }

    /// Decide the Backspace outcome for `buffer` with `cursorOffset`.
    ///
    /// - `buffer`: the entire NSTextStorage string.
    /// - `cursorOffset`: absolute UTF-16 cursor position.
    public static func backspaceOutcome(buffer: String, cursorOffset: Int) -> ListBackspaceOutcome {
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

        switch ListLineScanner.scan(line: lineContent) {
        case .none:
            return .standard

        case .partial(let indentLength, let markerLength):
            // Atomic delete only when cursor sits at the end of the partial
            // marker AND nothing else follows on the line.
            let partialEnd = indentLength + markerLength
            guard
                cursorOffsetInLine == partialEnd,
                lineLength == partialEnd
            else { return .standard }
            return atomicDelete(lineStart: lineStart, lineEnd: lineEnd)

        case .complete(let indentLength, let markerLength, _):
            // Atomic delete when cursor is at the end of an empty-body marker.
            let bodyStart = indentLength + markerLength
            if cursorOffsetInLine == bodyStart, lineLength == bodyStart {
                return atomicDelete(lineStart: lineStart, lineEnd: lineEnd)
            }

            // Thomas §8 push-back / acceptance: cursor at marker-start
            // (right before the `-` / digit) on a non-first line joins the
            // current line into the previous line and strips the indent +
            // marker. Otherwise we'd leave a stray `- ` mid-paragraph.
            if cursorOffsetInLine == indentLength, lineStart > 0 {
                // Delete `\n` + indent + marker (length: 1 + indentLength + markerLength).
                let deleteStart = lineStart - 1
                let deleteLength = 1 + indentLength + markerLength
                return .replace(
                    range: NSRange(location: deleteStart, length: deleteLength),
                    cursorOffsetInBuffer: deleteStart
                )
            }

            return .standard
        }
    }

    /// Atomic delete of the entire line content. If a preceding `\n` exists
    /// just before `lineStart`, eat it too so the cursor lands at the end of
    /// the previous line.
    private static func atomicDelete(lineStart: Int, lineEnd: Int) -> ListBackspaceOutcome {
        if lineStart > 0 {
            let range = NSRange(location: lineStart - 1, length: lineEnd - lineStart + 1)
            return .replace(range: range, cursorOffsetInBuffer: lineStart - 1)
        }
        let range = NSRange(location: 0, length: lineEnd)
        return .replace(range: range, cursorOffsetInBuffer: 0)
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
