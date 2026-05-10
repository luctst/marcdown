import Foundation

/// Pure helper that detects the "user just typed a closing `]` after a bare
/// `[`" auto-expand trigger and returns the expanded marker text.
///
/// AppKit-free. The editor coordinator owns the actual NSTextStorage edit.
public enum CheckboxAutoExpansion {
    /// If `beforeCursorOnLine` matches `^\s*\[$` (any leading whitespace then a
    /// single `[`), returns `<indent>- [ ] `. Otherwise returns nil.
    ///
    /// Note: input is the line content *up to but not including* the just-typed
    /// `]`, so the helper sees `[` rather than `[]`.
    public static func expansionOnTypingCloseBracket(beforeCursorOnLine: String) -> String? {
        let units = Array(beforeCursorOnLine.utf16)
        var i = 0
        let length = units.count

        // Walk leading whitespace (space / tab).
        while i < length, units[i] == 0x20 || units[i] == 0x09 {
            i += 1
        }

        // Need exactly one `[` (0x5B) after the indent and nothing else.
        guard i < length, units[i] == 0x5B else { return nil }
        guard i + 1 == length else { return nil }

        // Slice the indent back out preserving exact bytes (mixed spaces/tabs).
        // Indent units are guaranteed ASCII (0x20 / 0x09), so a per-unit
        // String construction is safe and avoids unsafe pointer juggling.
        var indent = ""
        indent.reserveCapacity(i)
        for k in 0..<i {
            indent.append(Character(Unicode.Scalar(units[k])!))
        }
        return indent + "- [ ] "
    }
}
