import Testing
@testable import MarcdownStyling

@Suite("CheckboxAutoExpansion")
struct CheckboxAutoExpansionTests {

    // MARK: - Triggers

    @Test func emptyLinePlusBracketExpands() {
        #expect(
            CheckboxAutoExpansion.expansionOnTypingCloseBracket(beforeCursorOnLine: "[")
            == "- [ ] "
        )
    }

    @Test func spaceIndentPreserved() {
        #expect(
            CheckboxAutoExpansion.expansionOnTypingCloseBracket(beforeCursorOnLine: "  [")
            == "  - [ ] "
        )
    }

    @Test func tabIndentPreserved() {
        #expect(
            CheckboxAutoExpansion.expansionOnTypingCloseBracket(beforeCursorOnLine: "\t[")
            == "\t- [ ] "
        )
    }

    @Test func mixedIndentPreserved() {
        #expect(
            CheckboxAutoExpansion.expansionOnTypingCloseBracket(beforeCursorOnLine: " \t [")
            == " \t - [ ] "
        )
    }

    // MARK: - Non-triggers

    @Test func noBracketReturnsNil() {
        #expect(
            CheckboxAutoExpansion.expansionOnTypingCloseBracket(beforeCursorOnLine: "")
            == nil
        )
    }

    @Test func contentBeforeBracketReturnsNil() {
        #expect(
            CheckboxAutoExpansion.expansionOnTypingCloseBracket(beforeCursorOnLine: "foo[")
            == nil
        )
    }

    @Test func bracketWithExtraReturnsNil() {
        #expect(
            CheckboxAutoExpansion.expansionOnTypingCloseBracket(beforeCursorOnLine: "[a")
            == nil
        )
    }

    @Test func existingDashBracketReturnsNil() {
        // Not the autoexpand trigger; this is a partial state handled by the scanner.
        #expect(
            CheckboxAutoExpansion.expansionOnTypingCloseBracket(beforeCursorOnLine: "- [")
            == nil
        )
    }
}
