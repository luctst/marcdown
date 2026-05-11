import Testing

@testable import MarcdownStyling

@MainActor
@Suite("CodeBlockAutoExpansion")
struct CodeBlockAutoExpansionTests {

    // MARK: - Triggers

    /// The single happy path: the user is at the start of an otherwise empty
    /// line with exactly two backticks already typed, and is about to commit
    /// the third backtick. Expansion produces a full scaffold with a blank
    /// body line, and reports the cursor offset (4 = after the opening
    /// ```` ```\n ````) so the caller can position the caret on the empty
    /// middle line.
    @Test func twoBacktickPrefixAtLineStartProducesExpansion() {
        let result = CodeBlockAutoExpansion.expansionOnTypingThirdBacktick(beforeCursorOnLine: "``")
        #expect(result != nil)
        #expect(result?.replacement == "```\n\n```")
        #expect(result?.cursorOffsetInReplacement == 4)
    }

    // MARK: - Non-triggers

    @Test func emptyPrefixDoesNotExpand() {
        #expect(CodeBlockAutoExpansion.expansionOnTypingThirdBacktick(beforeCursorOnLine: "") == nil)
    }

    @Test func singleBacktickDoesNotExpand() {
        #expect(CodeBlockAutoExpansion.expansionOnTypingThirdBacktick(beforeCursorOnLine: "`") == nil)
    }

    /// Trigger is strictly at the start of the line — any leading whitespace
    /// disqualifies. This matches the checkbox auto-expansion's
    /// "start-of-line only" stance for non-list triggers and avoids firing
    /// inside indented contexts where ``` is more likely intentional prose.
    @Test func leadingWhitespaceDoesNotExpand() {
        #expect(CodeBlockAutoExpansion.expansionOnTypingThirdBacktick(beforeCursorOnLine: " ``") == nil)
        #expect(CodeBlockAutoExpansion.expansionOnTypingThirdBacktick(beforeCursorOnLine: "\t``") == nil)
    }

    @Test func prosePrecedingBackticksDoesNotExpand() {
        // Mid-line ``: prose, then ``.
        #expect(CodeBlockAutoExpansion.expansionOnTypingThirdBacktick(beforeCursorOnLine: "hello ``") == nil)
        #expect(CodeBlockAutoExpansion.expansionOnTypingThirdBacktick(beforeCursorOnLine: "x``") == nil)
    }

    /// Already at three or more backticks — user is typing a 4th, not the
    /// 3rd. Expanding here would clobber an existing in-progress fence.
    @Test func moreThanTwoBackticksDoesNotExpand() {
        #expect(CodeBlockAutoExpansion.expansionOnTypingThirdBacktick(beforeCursorOnLine: "```") == nil)
    }
}
