import AppKit
import Testing

@testable import MarcdownEditor

@MainActor
@Suite("Block formatting commands")
struct BlockCommandTests {
    @Test func headingOneOnCaretLine() {
        let harness = EditorHarness.make(buffer: "hello")
        harness.setCaret(5)
        #expect(harness.coordinator.perform(.heading(1)) == true)
        #expect(harness.storage.string == "# hello")
        #expect(harness.textView.selectedRange() == NSRange(location: 7, length: 0))
    }

    @Test func paragraphCommandStripsHeading() {
        let harness = EditorHarness.make(buffer: "## hello")
        harness.setCaret(8)
        harness.coordinator.perform(.heading(0))
        #expect(harness.storage.string == "hello")
    }

    @Test func orderedListOverSelectionRenumbersWithNeighbours() {
        let harness = EditorHarness.make(buffer: "1. a\nb\nc")
        harness.select(5, 3)
        harness.coordinator.perform(.orderedList)
        #expect(harness.storage.string == "1. a\n2. b\n3. c")
    }

    @Test func taskQuoteAndDivider() {
        let harness = EditorHarness.make(buffer: "x")
        harness.setCaret(1)
        harness.coordinator.perform(.taskList)
        #expect(harness.storage.string == "- [ ] x")
        harness.coordinator.perform(.quote)
        #expect(harness.storage.string == "> x")
        harness.coordinator.perform(.divider)
        #expect(harness.storage.string == "> x\n\n---")
    }
}
