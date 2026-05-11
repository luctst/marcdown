import Foundation

/// Pure helper that detects the "user just typed a third `\`` at the start of
/// an empty line" auto-expand trigger and returns the expanded code block
/// scaffold.
///
/// AppKit-free. The editor coordinator owns the actual NSTextStorage edit.
public enum CodeBlockAutoExpansion {
    /// If `beforeCursorOnLine` is exactly two backticks (no leading whitespace,
    /// no other chars) — i.e. the user is about to land the third backtick at
    /// the very start of an empty line — returns a `CodeBlockExpansion` whose
    /// replacement is a full fenced-block scaffold (` ```\n\n``` `) and whose
    /// cursor offset lands on the blank body line. Otherwise returns nil.
    ///
    /// Note: input is the line content *up to but not including* the just-typed
    /// `\``, so the helper sees `` `` `` (two backticks) rather than ` ``` `.
    public static func expansionOnTypingThirdBacktick(
        beforeCursorOnLine: String
    ) -> CodeBlockExpansion? {
        let units = Array(beforeCursorOnLine.utf16)
        // Exactly two backticks (0x60), nothing else, nothing leading.
        guard units.count == 2,
            units[0] == 0x60,
            units[1] == 0x60
        else { return nil }

        // Scaffold: opening fence, blank body line, closing fence.
        // The cursor lands at the start of the blank body line (offset 4):
        // `\`` `\`` `\`` `\n` <- offset 4 here
        return CodeBlockExpansion(
            replacement: "```\n\n```",
            cursorOffsetInReplacement: 4
        )
    }
}

/// Result of a code-block auto-expansion: a fenced-block scaffold to splice
/// into the buffer plus the cursor offset within that replacement where the
/// caret should land.
public struct CodeBlockExpansion: Sendable, Equatable {
    /// The full replacement to substitute for the line prefix + the typed `\``.
    /// e.g., "```\n\n```" — opening fence, blank body line, closing fence.
    public let replacement: String
    /// Offset within the replacement where the cursor should land.
    /// For "```\n\n```" with cursor on the middle blank line, this is 4.
    public let cursorOffsetInReplacement: Int

    public init(replacement: String, cursorOffsetInReplacement: Int) {
        self.replacement = replacement
        self.cursorOffsetInReplacement = cursorOffsetInReplacement
    }
}
