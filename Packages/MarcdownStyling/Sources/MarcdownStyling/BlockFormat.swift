import Foundation

/// Line-level block types a command can set.
public enum BlockKind: Sendable, Equatable {
    case paragraph
    case heading(Int)
    case bullet
    case ordered
    case task
    case quote
}

/// Pure helpers for block commands. AppKit-free, UTF-16 offsets.
public enum BlockFormat {
    /// Rewrites every line touched by `selection` to `kind`, keeping leading
    /// indent. If every touched line already is `kind`, the marker is removed
    /// (toggle off). Ordered items are numbered from 1. A caret stays on its
    /// text (clamped to after the new marker); a multi-line selection ends
    /// up covering the rewritten lines.
    public static func toggleOutcome(buffer: String, selection: NSRange, kind: BlockKind) -> TextEditOutcome {
        let units = Array(buffer.utf16)
        guard selection.location >= 0, selection.location + selection.length <= units.count else { return .noOp }
        let (blockStart, blockEnd) = lineSpan(units: units, selection: selection)
        let lines = splitLines(units: units, from: blockStart, to: blockEnd)
        let prefixes = lines.map { LinePrefix.scan(line: $0) }
        let removing = kind == .paragraph || prefixes.allSatisfy { $0.kind == kind }

        var rebuilt: [String] = []
        var number = 1
        var firstNewPrefixLength = 0
        for (line, prefix) in zip(lines, prefixes) {
            // A line already of the target kind keeps its marker as typed
            // (`*` bullets, `[x]` tasks); only ordered items are rewritten
            // so the numbering stays consecutive.
            if !removing, prefix.kind == kind, kind != .ordered {
                if rebuilt.isEmpty { firstNewPrefixLength = prefix.prefixLength }
                rebuilt.append(String(decoding: line, as: UTF16.self))
                continue
            }
            let marker: String
            if removing {
                marker = ""
            } else {
                switch kind {
                case .paragraph: marker = ""
                case .heading(let level): marker = String(repeating: "#", count: max(1, min(6, level))) + " "
                case .bullet: marker = "- "
                case .ordered:
                    marker = "\(number). "
                    number += 1
                case .task: marker = "- [ ] "
                case .quote: marker = "> "
                }
            }
            if rebuilt.isEmpty { firstNewPrefixLength = prefix.indentLength + (marker as NSString).length }
            let indent = String(decoding: line[0..<prefix.indentLength], as: UTF16.self)
            let body = String(decoding: line[prefix.prefixLength...], as: UTF16.self)
            rebuilt.append(indent + marker + body)
        }
        let replacement = rebuilt.joined(separator: "\n")
        let original = String(decoding: units[blockStart..<blockEnd], as: UTF16.self)
        guard replacement != original else { return .noOp }

        let range = NSRange(location: blockStart, length: blockEnd - blockStart)
        let newSelection: NSRange
        if selection.length == 0 {
            let delta = firstNewPrefixLength - prefixes[0].prefixLength
            let location = max(blockStart + firstNewPrefixLength, selection.location + delta)
            newSelection = NSRange(location: location, length: 0)
        } else {
            newSelection = NSRange(location: blockStart, length: (replacement as NSString).length)
        }
        return .replace(range: range, replacement: replacement, selection: newSelection)
    }

    /// Fenced code block. With a selection: fence the touched lines and
    /// select their bodies. With a caret on an empty line: replace it with an
    /// empty block; on a non-empty line: open the block on the next line.
    public static func codeBlockOutcome(buffer: String, selection: NSRange) -> TextEditOutcome {
        let units = Array(buffer.utf16)
        guard selection.location >= 0, selection.location + selection.length <= units.count else { return .noOp }
        let (blockStart, blockEnd) = lineSpan(units: units, selection: selection)
        if selection.length > 0 {
            let body = String(decoding: units[blockStart..<blockEnd], as: UTF16.self)
            return .replace(
                range: NSRange(location: blockStart, length: blockEnd - blockStart),
                replacement: "```\n" + body + "\n```",
                selection: NSRange(location: blockStart + 4, length: blockEnd - blockStart)
            )
        }
        if blockEnd == blockStart {
            return .replace(
                range: NSRange(location: blockStart, length: 0),
                replacement: "```\n\n```",
                selection: NSRange(location: blockStart + 4, length: 0)
            )
        }
        return .replace(
            range: NSRange(location: blockEnd, length: 0),
            replacement: "\n```\n\n```",
            selection: NSRange(location: blockEnd + 5, length: 0)
        )
    }

    /// `---` on its own line. After text it is preceded by a blank line so
    /// CommonMark doesn't read it as a setext heading underline. A blank
    /// (empty or whitespace-only) line is replaced in place; if the line
    /// above it has text, the same blank line is inserted first.
    public static func dividerOutcome(buffer: String, selection: NSRange) -> TextEditOutcome {
        let units = Array(buffer.utf16)
        guard selection.location >= 0, selection.location + selection.length <= units.count else { return .noOp }
        let (blockStart, blockEnd) = lineSpan(units: units, selection: selection)
        if units[blockStart..<blockEnd].allSatisfy({ $0 == 0x20 || $0 == 0x09 }) {
            let underText = blockStart >= 2 && units[blockStart - 2] != 0x0A
            let replacement = underText ? "\n---" : "---"
            return .replace(
                range: NSRange(location: blockStart, length: blockEnd - blockStart),
                replacement: replacement,
                selection: NSRange(location: blockStart + (replacement as NSString).length, length: 0)
            )
        }
        return .replace(
            range: NSRange(location: blockEnd, length: 0),
            replacement: "\n\n---",
            selection: NSRange(location: blockEnd + 5, length: 0)
        )
    }

    // MARK: - Line prefix classification

    struct LinePrefix: Equatable {
        let indentLength: Int
        /// Indent + marker, i.e. where the body starts.
        let prefixLength: Int
        let kind: BlockKind?

        static func scan(line: [UInt16]) -> LinePrefix {
            let text = String(decoding: line, as: UTF16.self)
            var indent = 0
            while indent < line.count, line[indent] == 0x20 || line[indent] == 0x09 { indent += 1 }

            if case .complete(let indentLength, let bracket, _) = CheckboxLineScanner.scan(line: text) {
                var end = bracket + 3
                if end < line.count, line[end] == 0x20 { end += 1 }
                return LinePrefix(indentLength: indentLength, prefixLength: end, kind: .task)
            }
            if case .complete(let indentLength, let markerLength, let markerKind) = ListLineScanner.scan(line: text) {
                let prefixLength = indentLength + markerLength
                switch markerKind {
                case .bullet: return LinePrefix(indentLength: indentLength, prefixLength: prefixLength, kind: .bullet)
                case .ordered: return LinePrefix(indentLength: indentLength, prefixLength: prefixLength, kind: .ordered)
                }
            }
            var probe = indent
            var hashes = 0
            while probe < line.count, hashes < 6, line[probe] == 0x23 {
                hashes += 1
                probe += 1
            }
            if hashes > 0, probe < line.count, line[probe] == 0x20 {
                return LinePrefix(indentLength: indent, prefixLength: probe + 1, kind: .heading(hashes))
            }
            if indent < line.count, line[indent] == 0x3E {
                var end = indent + 1
                if end < line.count, line[end] == 0x20 { end += 1 }
                return LinePrefix(indentLength: indent, prefixLength: end, kind: .quote)
            }
            return LinePrefix(indentLength: indent, prefixLength: indent, kind: nil)
        }
    }

    // MARK: - Helpers

    /// Start of the first line and end (exclusive of `\n`) of the last line
    /// touched by `selection`.
    static func lineSpan(units: [UInt16], selection: NSRange) -> (Int, Int) {
        var start = selection.location
        while start > 0, units[start - 1] != 0x0A { start -= 1 }
        var end = selection.location + selection.length
        // A selection ending right after a newline does not touch the next line.
        if selection.length > 0, end > 0, units[end - 1] == 0x0A { end -= 1 }
        while end < units.count, units[end] != 0x0A { end += 1 }
        return (start, end)
    }

    static func splitLines(units: [UInt16], from: Int, to: Int) -> [[UInt16]] {
        var lines: [[UInt16]] = []
        var lineStart = from
        var probe = from
        while probe < to {
            if units[probe] == 0x0A {
                lines.append(Array(units[lineStart..<probe]))
                lineStart = probe + 1
            }
            probe += 1
        }
        lines.append(Array(units[lineStart..<to]))
        return lines
    }
}
