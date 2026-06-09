import Foundation

/// Outcome of pressing Return inside a buffer that may contain a blockquote
/// marker. Mirrors `ListContinuation.ListEnterOutcome`.
public enum BlockquoteEnterOutcome: Sendable, Equatable {
    case noOp
    case replace(range: NSRange, replacement: String, cursorOffsetInBuffer: Int)
}

/// Outcome of pressing Backspace on a blockquote line.
public enum BlockquoteBackspaceOutcome: Sendable, Equatable {
    case standard
    case replace(range: NSRange, cursorOffsetInBuffer: Int)
}

/// Pure helper that decides Enter / Backspace outcomes for blockquote lines.
/// Spec §9: lines starting with one or more `> ` markers get continuation on
/// Enter (preserving depth) and atomic strip on Enter/Backspace when the
/// marker line is empty.
public enum BlockquoteContinuation {

    /// Decide the Enter outcome.
    public static func enterOutcome(buffer: String, cursorOffset: Int) -> BlockquoteEnterOutcome {
        let units = Array(buffer.utf16)
        let length = units.count
        guard cursorOffset >= 0, cursorOffset <= length else { return .noOp }

        let (lineStart, lineEnd) = lineRange(units: units, cursor: cursorOffset)
        guard let prefix = scanBlockquotePrefix(units: units, lineStart: lineStart, lineEnd: lineEnd) else {
            return .noOp
        }

        let lineLength = lineEnd - lineStart
        let cursorOffsetInLine = cursorOffset - lineStart

        // Cursor before / inside the marker prefix → fall through.
        if cursorOffsetInLine < prefix.prefixLength { return .noOp }

        let bodyLength = lineLength - prefix.prefixLength
        if bodyLength > 0 {
            // Non-empty body — continue with the same prefix.
            let prefixString = substring(units: units, from: lineStart, to: lineStart + prefix.prefixLength)
            let continuation = "\n" + prefixString
            let replacementUTF16Count = continuation.utf16.count
            return .replace(
                range: NSRange(location: cursorOffset, length: 0),
                replacement: continuation,
                cursorOffsetInBuffer: cursorOffset + replacementUTF16Count
            )
        }

        // Empty body. If nested (`>> `, `>>> `, …) strip one level only;
        // otherwise strip the entire prefix.
        if prefix.depth > 1 {
            // Strip one `>` and possibly a trailing space. The exact bytes to
            // strip: the FIRST `>` of the prefix plus an immediately-following
            // space if present.
            // Simpler: the new prefix is the existing prefix minus one level.
            let newPrefix = buildPrefix(depth: prefix.depth - 1)
            return .replace(
                range: NSRange(location: lineStart, length: prefix.prefixLength),
                replacement: newPrefix,
                cursorOffsetInBuffer: lineStart + (newPrefix as NSString).length
            )
        }

        // Top-level empty blockquote → strip entire prefix.
        return .replace(
            range: NSRange(location: lineStart, length: prefix.prefixLength),
            replacement: "",
            cursorOffsetInBuffer: lineStart
        )
    }

    /// Decide the Backspace outcome.
    public static func backspaceOutcome(buffer: String, cursorOffset: Int) -> BlockquoteBackspaceOutcome {
        let units = Array(buffer.utf16)
        let length = units.count
        guard cursorOffset >= 0, cursorOffset <= length else { return .standard }

        let (lineStart, lineEnd) = lineRange(units: units, cursor: cursorOffset)
        guard let prefix = scanBlockquotePrefix(units: units, lineStart: lineStart, lineEnd: lineEnd) else {
            return .standard
        }

        let lineLength = lineEnd - lineStart
        let cursorOffsetInLine = cursorOffset - lineStart

        // Atomic delete only when cursor is at the end of an empty-body prefix.
        let bodyLength = lineLength - prefix.prefixLength
        guard cursorOffsetInLine == prefix.prefixLength, bodyLength == 0 else {
            return .standard
        }

        if lineStart > 0 {
            let range = NSRange(location: lineStart - 1, length: lineEnd - lineStart + 1)
            return .replace(range: range, cursorOffsetInBuffer: lineStart - 1)
        }
        let range = NSRange(location: 0, length: lineEnd)
        return .replace(range: range, cursorOffsetInBuffer: 0)
    }

    // MARK: - Prefix scanning

    private struct BlockquotePrefix {
        /// Total UTF-16 length of the prefix (`>` chars plus any single
        /// trailing space).
        let prefixLength: Int
        /// Number of `>` characters in the prefix (i.e. nesting depth).
        let depth: Int
    }

    /// If the line at `lineStart..<lineEnd` starts with `>` (optionally
    /// followed by more `>` for nesting and a single trailing space), return
    /// the prefix length and depth. Otherwise return nil.
    private static func scanBlockquotePrefix(
        units: [UInt16],
        lineStart: Int,
        lineEnd: Int
    ) -> BlockquotePrefix? {
        var i = lineStart
        guard i < lineEnd, units[i] == 0x3E else { return nil }  // '>'

        // Bear and most editors only treat `>` runs without intervening
        // characters as multi-level (`>>`, `>>>`). A `>` followed by ` >` is
        // a single-level quote whose body happens to be another quote.
        var depth = 0
        while i < lineEnd, units[i] == 0x3E {
            depth += 1
            i += 1
        }
        // Allow a single trailing space (CommonMark canonical form).
        if i < lineEnd, units[i] == 0x20 {
            i += 1
        }
        return BlockquotePrefix(prefixLength: i - lineStart, depth: depth)
    }

    /// Build a prefix string like `> `, `>> `, `>>> ` for `depth >= 1`.
    private static func buildPrefix(depth: Int) -> String {
        guard depth >= 1 else { return "" }
        return String(repeating: ">", count: depth) + " "
    }

    // MARK: - Boundaries

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
