import AppKit
import Testing

@testable import MarcdownEditor

@MainActor
@Suite("Inline formatting commands")
struct InlineFormatCommandTests {
    @Test func boldWrapsSelection() {
        let harness = EditorHarness.make(buffer: "hello world")
        harness.select(0, 5)

        #expect(harness.coordinator.perform(.bold) == true)
        #expect(harness.storage.string == "**hello** world")
        #expect(harness.textView.selectedRange() == NSRange(location: 2, length: 5))
    }

    @Test func boldTwiceRoundTrips() {
        let harness = EditorHarness.make(buffer: "hello")
        harness.select(0, 5)
        harness.coordinator.perform(.bold)
        harness.coordinator.perform(.bold)
        #expect(harness.storage.string == "hello")
        #expect(harness.textView.selectedRange() == NSRange(location: 0, length: 5))
    }

    @Test func italicCaretInsertsPair() {
        let harness = EditorHarness.make(buffer: "")
        harness.setCaret(0)
        harness.coordinator.perform(.italic)
        #expect(harness.storage.string == "**")
        #expect(harness.textView.selectedRange() == NSRange(location: 1, length: 0))
    }

    @Test func highlightAndStrikethroughAndCode() {
        let harness = EditorHarness.make(buffer: "abc")
        harness.select(0, 3)
        harness.coordinator.perform(.highlight)
        #expect(harness.storage.string == "==abc==")
        harness.coordinator.perform(.highlight)
        harness.coordinator.perform(.strikethrough)
        #expect(harness.storage.string == "~~abc~~")
        harness.coordinator.perform(.strikethrough)
        harness.coordinator.perform(.inlineCode)
        #expect(harness.storage.string == "`abc`")
    }

    @Test func undoRestoresBuffer() {
        let harness = EditorHarness.make(buffer: "hello")
        harness.select(0, 5)
        harness.coordinator.perform(.bold)
        harness.textView.undoManager?.undo()
        #expect(harness.storage.string == "hello")
    }
}
