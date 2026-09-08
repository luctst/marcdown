import AppKit
import Testing

@testable import MarcdownEditor

@MainActor
@Suite("shouldChangeText interception")
struct ShouldChangeTextTests {
    @Test func typingAsteriskOverSelectionWraps() {
        let harness = EditorHarness.make(buffer: "hello")
        harness.select(0, 5)
        let allow = harness.coordinator.textView(
            harness.textView, shouldChangeTextIn: NSRange(location: 0, length: 5), replacementString: "*")
        #expect(allow == false)
        #expect(harness.storage.string == "*hello*")
        #expect(harness.textView.selectedRange() == NSRange(location: 1, length: 5))
    }

    @Test func pastingURLOverSelectionMakesLink() {
        let harness = EditorHarness.make(buffer: "docs here")
        harness.select(0, 4)
        let allow = harness.coordinator.textView(
            harness.textView, shouldChangeTextIn: NSRange(location: 0, length: 4), replacementString: "https://x.y/")
        #expect(allow == false)
        #expect(harness.storage.string == "[docs](https://x.y/) here")
    }

    @Test func pastingPlainTextOverSelectionIsLeftToAppKit() {
        let harness = EditorHarness.make(buffer: "docs")
        harness.select(0, 4)
        let allow = harness.coordinator.textView(
            harness.textView, shouldChangeTextIn: NSRange(location: 0, length: 4), replacementString: "plain text")
        #expect(allow == true)
        #expect(harness.storage.string == "docs")
    }

    @Test func checkboxExpansionStillWorks() {
        let harness = EditorHarness.make(buffer: "[]")
        harness.setCaret(2)
        let allow = harness.coordinator.textView(
            harness.textView, shouldChangeTextIn: NSRange(location: 2, length: 0), replacementString: " ")
        #expect(allow == false)
        #expect(harness.storage.string == "- [ ] ")
    }
}
