import Foundation
import Testing

@testable import MarcdownStyling

@Suite("SelectionWrap")
struct SelectionWrapTests {
    @Test func asteriskWrapsAndKeepsSelectionOnText() {
        #expect(
            SelectionWrap.outcome(buffer: "hi there", selection: NSRange(location: 0, length: 2), typed: "*")
                == .replace(
                    range: NSRange(location: 0, length: 2), replacement: "*hi*",
                    selection: NSRange(location: 1, length: 2)))
    }

    @Test func bracketsAndParensUseTheirCloser() {
        #expect(
            SelectionWrap.outcome(buffer: "x", selection: NSRange(location: 0, length: 1), typed: "[")
                == .replace(
                    range: NSRange(location: 0, length: 1), replacement: "[x]",
                    selection: NSRange(location: 1, length: 1)))
        #expect(
            SelectionWrap.outcome(buffer: "x", selection: NSRange(location: 0, length: 1), typed: "(")
                == .replace(
                    range: NSRange(location: 0, length: 1), replacement: "(x)",
                    selection: NSRange(location: 1, length: 1)))
    }

    @Test func nonWrappingCharacterAndEmptySelectionAreNoOp() {
        #expect(SelectionWrap.outcome(buffer: "x", selection: NSRange(location: 0, length: 1), typed: "a") == .noOp)
        #expect(SelectionWrap.outcome(buffer: "x", selection: NSRange(location: 0, length: 0), typed: "*") == .noOp)
    }
}
