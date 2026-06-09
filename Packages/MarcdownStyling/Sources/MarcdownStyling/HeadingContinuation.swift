import Foundation

/// Outcome of pressing Backspace on a buffer that may contain an ATX heading
/// marker. Spec §8.2 / acceptance #9: pressing Backspace at the end of an
/// empty heading line (`# |`) strips the marker, leaving an empty plain line.
public enum HeadingBackspaceOutcome: Sendable, Equatable {
    case standard
    case replace(range: NSRange, cursorOffsetInBuffer: Int)
}

/// Pure helper for ATX heading marker handling on Backspace. All other
/// keystrokes (Enter, character insertion) on heading lines remain the
/// AppKit default — they already produce the right behaviour.
public enum HeadingContinuation {

    /// If the cursor sits at the end of an ATX marker (`#`…`# `) with no
    /// body content, atomically strip the marker. Otherwise return `.standard`.
    public static func backspaceOutcome(buffer: String, cursorOffset: Int) -> HeadingBackspaceOutcome {
        let units = Array(buffer.utf16)
        let length = units.count
        guard cursorOffset >= 0, cursorOffset <= length else { return .standard }

        let (lineStart, lineEnd) = lineRange(units: units, cursor: cursorOffset)
        let lineLength = lineEnd - lineStart
        guard lineLength > 0 else { return .standard }

        // Scan an ATX marker: 1-6 leading `#` chars + a single trailing space.
        var hashCount = 0
        var probe = lineStart
        while probe < lineEnd, hashCount < 6, units[probe] == 0x23 {
            hashCount += 1
            probe += 1
        }
        guard hashCount >= 1 else { return .standard }
        // Trailing space required for an empty heading we'd strip.
        guard probe < lineEnd, units[probe] == 0x20 else { return .standard }
        probe += 1

        let markerLength = probe - lineStart
        // Atomic strip only when cursor is right after the marker AND the
        // line ends there.
        guard cursorOffset - lineStart == markerLength, lineLength == markerLength else {
            return .standard
        }

        if lineStart > 0 {
            let range = NSRange(location: lineStart - 1, length: lineEnd - lineStart + 1)
            return .replace(range: range, cursorOffsetInBuffer: lineStart - 1)
        }
        let range = NSRange(location: 0, length: lineEnd)
        return .replace(range: range, cursorOffsetInBuffer: 0)
    }

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
}
