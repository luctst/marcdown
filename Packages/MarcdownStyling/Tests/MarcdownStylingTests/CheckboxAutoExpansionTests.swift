import Testing

@testable import MarcdownStyling

@Suite("CheckboxAutoExpansion")
struct CheckboxAutoExpansionTests {

    // MARK: - Triggers

    @Test func emptyLinePlusBracketExpands() {
        #expect(
            CheckboxAutoExpansion.expansionOnTypingSpace(beforeCursorOnLine: "[]")
                == "- [ ] "
        )
    }

    @Test func spaceIndentPreserved() {
        #expect(
            CheckboxAutoExpansion.expansionOnTypingSpace(beforeCursorOnLine: "  []")
                == "  - [ ] "
        )
    }

    @Test func tabIndentPreserved() {
        #expect(
            CheckboxAutoExpansion.expansionOnTypingSpace(beforeCursorOnLine: "\t[]")
                == "\t- [ ] "
        )
    }

    @Test func mixedIndentPreserved() {
        #expect(
            CheckboxAutoExpansion.expansionOnTypingSpace(beforeCursorOnLine: " \t []")
                == " \t - [ ] "
        )
    }

    // MARK: - Non-triggers

    @Test func noBracketReturnsNil() {
        #expect(
            CheckboxAutoExpansion.expansionOnTypingSpace(beforeCursorOnLine: "")
                == nil
        )
    }

    @Test func contentBeforeBracketReturnsNil() {
        #expect(
            CheckboxAutoExpansion.expansionOnTypingSpace(beforeCursorOnLine: "foo[")
                == nil
        )
    }

    @Test func bracketWithExtraReturnsNil() {
        #expect(
            CheckboxAutoExpansion.expansionOnTypingSpace(beforeCursorOnLine: "[a")
                == nil
        )
    }

    @Test func existingDashBracketReturnsNil() {
        // Not the autoexpand trigger; this is a partial state handled by the scanner.
        #expect(
            CheckboxAutoExpansion.expansionOnTypingSpace(beforeCursorOnLine: "- [")
                == nil
        )
    }

    // MARK: - Regressions

    @Test func typingCloseBracketAloneDoesNotExpand() {
        // Regression: the old trigger (`^\s*\[$`) must no longer fire on a lone `[`.
        #expect(
            CheckboxAutoExpansion.expansionOnTypingSpace(beforeCursorOnLine: "[")
                == nil
        )
    }

    @Test func linkEmptyLabelBracketsDoNotExpand() {
        // Regression: `[](` is the start of a Markdown link, not a checkbox.
        #expect(
            CheckboxAutoExpansion.expansionOnTypingSpace(beforeCursorOnLine: "[](")
                == nil
        )
    }
}
