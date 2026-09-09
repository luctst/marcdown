import Foundation

/// Pure helpers for inline formatting commands. AppKit-free, UTF-16 offsets.
public enum InlineFormat {
    /// Toggle `delimiter` (`**`, `*`, `` ` ``, `~~`, `==`) around `selection`.
    /// Delimiters are homogeneous runs of one unit, so "wrapped" is decided
    /// by run length: a run pair counts as this delimiter when both runs are
    /// at least `delimiter` long and, for single-unit delimiters, both are
    /// odd (`**foo**` is strong, not two italics). Unwrapping removes exactly
    /// one delimiter per side.
    /// - Caret: an empty pair around the caret is removed; otherwise a pair
    ///   is inserted and the caret parked inside.
    /// - Selection already wrapped (either side of, or inside, the
    ///   whitespace-trimmed selection): unwrap.
    /// - Ambiguous shapes are `.noOp`: the trimmed selection is only delimiter
    ///   units, a boundary splits a delimiter run, or one edge is a delimiter
    ///   unit and the other is not.
    /// - Otherwise wrap the trimmed selection (`**foo **` is not strong) and
    ///   select the inner text.
    public static func toggleOutcome(buffer: String, selection: NSRange, delimiter: String) -> TextEditOutcome {
        let units = Array(buffer.utf16)
        let delim = Array(delimiter.utf16)
        let dl = delim.count
        guard let unit = delim.first, selection.location >= 0, selection.location + selection.length <= units.count
        else {
            return .noOp
        }

        if selection.length == 0 {
            let caret = selection.location
            let left = runLength(before: caret, of: unit, in: units, floor: 0)
            let right = runLength(from: caret, of: unit, in: units, ceiling: units.count)
            if isDelimiterPair(left: left, right: right, delimiterLength: dl) {
                return .replace(
                    range: NSRange(location: caret - dl, length: dl * 2),
                    replacement: "",
                    selection: NSRange(location: caret - dl, length: 0)
                )
            }
            return .replace(
                range: NSRange(location: caret, length: 0),
                replacement: delimiter + delimiter,
                selection: NSRange(location: caret + dl, length: 0)
            )
        }

        var lower = selection.location
        var upper = selection.location + selection.length
        while lower < upper, isSpace(units[lower]) { lower += 1 }
        while upper > lower, isSpace(units[upper - 1]) { upper -= 1 }
        guard upper > lower else { return .noOp }

        let startsWithUnit = units[lower] == unit
        let endsWithUnit = units[upper - 1] == unit
        if units[lower..<upper].allSatisfy({ $0 == unit }) { return .noOp }
        if startsWithUnit, lower > 0, units[lower - 1] == unit { return .noOp }
        if endsWithUnit, upper < units.count, units[upper] == unit { return .noOp }
        if startsWithUnit != endsWithUnit { return .noOp }

        let left = runLength(before: lower, of: unit, in: units, floor: 0)
        let right = runLength(from: upper, of: unit, in: units, ceiling: units.count)
        if isDelimiterPair(left: left, right: right, delimiterLength: dl) {
            return .replace(
                range: NSRange(location: lower - dl, length: upper - lower + 2 * dl),
                replacement: String(decoding: units[lower..<upper], as: UTF16.self),
                selection: NSRange(location: lower - dl, length: upper - lower)
            )
        }
        if startsWithUnit {
            let leading = runLength(from: lower, of: unit, in: units, ceiling: upper)
            let trailing = runLength(before: upper, of: unit, in: units, floor: lower)
            if isDelimiterPair(left: leading, right: trailing, delimiterLength: dl) {
                return .replace(
                    range: NSRange(location: lower, length: upper - lower),
                    replacement: String(decoding: units[(lower + dl)..<(upper - dl)], as: UTF16.self),
                    selection: NSRange(location: lower, length: upper - lower - 2 * dl)
                )
            }
        }
        let inner = String(decoding: units[lower..<upper], as: UTF16.self)
        return .replace(
            range: NSRange(location: lower, length: upper - lower),
            replacement: delimiter + inner + delimiter,
            selection: NSRange(location: lower + dl, length: upper - lower)
        )
    }

    /// `[selection](url)`. Caret lands after `)` when a URL is given, inside
    /// `()` when it is empty, and inside `[]` when there was no selection.
    public static func linkOutcome(buffer: String, selection: NSRange, url: String) -> TextEditOutcome {
        let units = Array(buffer.utf16)
        guard selection.location >= 0, selection.location + selection.length <= units.count else { return .noOp }
        let label = String(
            decoding: units[selection.location..<(selection.location + selection.length)], as: UTF16.self)
        let replacement = "[\(label)](\(url))"
        let start = selection.location
        let caret: Int
        if selection.length == 0 {
            caret = start + 1
        } else if url.isEmpty {
            caret = start + selection.length + 3
        } else {
            caret = start + (replacement as NSString).length
        }
        return .replace(range: selection, replacement: replacement, selection: NSRange(location: caret, length: 0))
    }

    /// True for a single `http`/`https` URL with a host and no interior whitespace.
    public static func isHTTPURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: { $0.isWhitespace }),
            let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            url.host != nil
        else { return false }
        return true
    }

    private static func isSpace(_ unit: UInt16) -> Bool { unit == 0x20 || unit == 0x09 }

    /// Consecutive `unit`s ending at `index`, never reaching below `floor`.
    private static func runLength(before index: Int, of unit: UInt16, in units: [UInt16], floor: Int) -> Int {
        var probe = index
        while probe > floor, units[probe - 1] == unit { probe -= 1 }
        return index - probe
    }

    /// Consecutive `unit`s starting at `index`, never reaching `ceiling`.
    private static func runLength(from index: Int, of unit: UInt16, in units: [UInt16], ceiling: Int) -> Int {
        var probe = index
        while probe < ceiling, units[probe] == unit { probe += 1 }
        return probe - index
    }

    /// Run parity: both runs hold at least one delimiter and, for single-unit
    /// delimiters, both are odd so `**` is never mistaken for `*` + `*`.
    private static func isDelimiterPair(left: Int, right: Int, delimiterLength: Int) -> Bool {
        guard left >= delimiterLength, right >= delimiterLength else { return false }
        return delimiterLength != 1 || (left % 2 == 1 && right % 2 == 1)
    }
}
