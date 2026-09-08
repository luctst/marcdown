import Foundation

/// Pure helpers for inline formatting commands. AppKit-free, UTF-16 offsets.
public enum InlineFormat {
    /// Toggle `delimiter` (`**`, `*`, `` ` ``, `~~`, `==`) around `selection`.
    /// - Caret: `**|**` removes the empty pair; otherwise inserts a pair and
    ///   parks the caret inside.
    /// - Selection already wrapped (either side of, or inside, the selection):
    ///   unwrap.
    /// - Otherwise wrap the whitespace-trimmed selection (`**foo **` is not
    ///   strong) and select the inner text.
    public static func toggleOutcome(buffer: String, selection: NSRange, delimiter: String) -> TextEditOutcome {
        let units = Array(buffer.utf16)
        let delim = Array(delimiter.utf16)
        let dl = delim.count
        guard dl > 0, selection.location >= 0, selection.location + selection.length <= units.count else {
            return .noOp
        }

        if selection.length == 0 {
            let caret = selection.location
            if caret >= dl, caret + dl <= units.count,
                Array(units[(caret - dl)..<caret]) == delim,
                Array(units[caret..<(caret + dl)]) == delim
            {
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

        if lower >= dl, upper + dl <= units.count,
            Array(units[(lower - dl)..<lower]) == delim,
            Array(units[upper..<(upper + dl)]) == delim
        {
            return .replace(
                range: NSRange(location: lower - dl, length: upper - lower + 2 * dl),
                replacement: String(decoding: units[lower..<upper], as: UTF16.self),
                selection: NSRange(location: lower - dl, length: upper - lower)
            )
        }
        if upper - lower >= 2 * dl,
            Array(units[lower..<(lower + dl)]) == delim,
            Array(units[(upper - dl)..<upper]) == delim
        {
            return .replace(
                range: NSRange(location: lower, length: upper - lower),
                replacement: String(decoding: units[(lower + dl)..<(upper - dl)], as: UTF16.self),
                selection: NSRange(location: lower, length: upper - lower - 2 * dl)
            )
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
}
