import Testing

@testable import MarcdownStyling

@Suite("CheckboxLineScanner")
struct CheckboxLineScannerTests {

    // MARK: - .none cases

    @Test func emptyLineIsNone() {
        #expect(CheckboxLineScanner.scan(line: "") == .none)
    }

    @Test func plainTextIsNone() {
        #expect(CheckboxLineScanner.scan(line: "hello") == .none)
    }

    @Test func noLeadingDashIsNone() {
        #expect(CheckboxLineScanner.scan(line: "[ ] foo") == .none)
    }

    @Test func dashWithoutSpaceIsNone() {
        #expect(CheckboxLineScanner.scan(line: "-[ ]") == .none)
    }

    @Test func dashSpaceNonBracketIsNone() {
        // Plain unordered list, not a task.
        #expect(CheckboxLineScanner.scan(line: "- foo") == .none)
    }

    // MARK: - .partial cases

    @Test func dashOnlyIsPartial() {
        #expect(
            CheckboxLineScanner.scan(line: "-")
                == .partial(indentLength: 0, concealLength: 1)
        )
    }

    @Test func dashSpaceIsPartial() {
        #expect(
            CheckboxLineScanner.scan(line: "- ")
                == .partial(indentLength: 0, concealLength: 2)
        )
    }

    @Test func dashSpaceOpenBracketIsPartial() {
        #expect(
            CheckboxLineScanner.scan(line: "- [")
                == .partial(indentLength: 0, concealLength: 3)
        )
    }

    @Test func dashSpaceOpenBracketSpaceIsPartial() {
        #expect(
            CheckboxLineScanner.scan(line: "- [ ")
                == .partial(indentLength: 0, concealLength: 4)
        )
    }

    @Test func dashSpaceLowercaseXNoCloseIsPartial() {
        #expect(
            CheckboxLineScanner.scan(line: "- [x")
                == .partial(indentLength: 0, concealLength: 4)
        )
    }

    @Test func dashSpaceUppercaseXNoCloseIsPartial() {
        #expect(
            CheckboxLineScanner.scan(line: "- [X")
                == .partial(indentLength: 0, concealLength: 4)
        )
    }

    @Test func emptyBracketsIsPartial() {
        // No inner char — treat as partial; auto-expand will fill it.
        #expect(
            CheckboxLineScanner.scan(line: "- []")
                == .partial(indentLength: 0, concealLength: 4)
        )
    }

    @Test func indentedPartialPreservesIndent() {
        #expect(
            CheckboxLineScanner.scan(line: "  - [")
                == .partial(indentLength: 2, concealLength: 3)
        )
    }

    // MARK: - .complete cases

    @Test func completeUncheckedIsComplete() {
        #expect(
            CheckboxLineScanner.scan(line: "- [ ]")
                == .complete(indentLength: 0, bracketLocation: 2, state: .unchecked)
        )
    }

    @Test func completeCheckedLowercaseIsComplete() {
        #expect(
            CheckboxLineScanner.scan(line: "- [x]")
                == .complete(indentLength: 0, bracketLocation: 2, state: .checked)
        )
    }

    @Test func completeCheckedUppercaseIsComplete() {
        #expect(
            CheckboxLineScanner.scan(line: "- [X]")
                == .complete(indentLength: 0, bracketLocation: 2, state: .checked)
        )
    }

    @Test func completeWithBodyIsComplete() {
        #expect(
            CheckboxLineScanner.scan(line: "- [ ] foo")
                == .complete(indentLength: 0, bracketLocation: 2, state: .unchecked)
        )
    }

    @Test func indentedCompletePreservesIndent() {
        #expect(
            CheckboxLineScanner.scan(line: "  - [ ] foo")
                == .complete(indentLength: 2, bracketLocation: 4, state: .unchecked)
        )
    }

    @Test func tabIndentedCompletePreservesIndent() {
        #expect(
            CheckboxLineScanner.scan(line: "\t- [x]")
                == .complete(indentLength: 1, bracketLocation: 3, state: .checked)
        )
    }

    @Test func garbageAfterCompleteIsStillComplete() {
        // Body content after `- [ ] ` doesn't disturb classification.
        #expect(
            CheckboxLineScanner.scan(line: "- [ ] foo bar baz")
                == .complete(indentLength: 0, bracketLocation: 2, state: .unchecked)
        )
    }
}
