import AppKit
import Testing

@testable import MarcdownEditor

@MainActor
@Suite("Slash menu plumbing")
struct SlashMenuTests {
    @Test func commandNotificationIsPerformed() {
        let harness = EditorHarness.make(buffer: "hi")
        harness.select(0, 2)
        NotificationCenter.default.post(
            name: .marcdownEditorPerformCommand,
            object: nil,
            userInfo: [EditorCommandNotification.key: EditorCommand.bold]
        )
        #expect(harness.storage.string == "**hi**")
    }

    @Test func loneSlashIsConsumedByABlockCommand() {
        let harness = EditorHarness.make(buffer: "a\n/")
        harness.setCaret(3)
        harness.coordinator.perform(.heading(2))
        #expect(harness.storage.string == "a\n## ")
        #expect(harness.textView.selectedRange() == NSRange(location: 5, length: 0))
    }

    @Test func slashInsideTextIsKept() {
        let harness = EditorHarness.make(buffer: "a/b")
        harness.setCaret(3)
        harness.coordinator.perform(.bold)
        #expect(harness.storage.string == "a/b****")
    }

    @Test func slashOnEmptyLineIsInsertedAndSignals() {
        let harness = EditorHarness.make(buffer: "")
        harness.setCaret(0)
        let allow = harness.coordinator.textView(
            harness.textView, shouldChangeTextIn: NSRange(location: 0, length: 0), replacementString: "/")
        #expect(allow == true)
        #expect(harness.coordinator.didRequestSlashMenu == true)
    }

    @Test func slashAfterTextDoesNotSignal() {
        let harness = EditorHarness.make(buffer: "ab")
        harness.setCaret(2)
        _ = harness.coordinator.textView(
            harness.textView, shouldChangeTextIn: NSRange(location: 2, length: 0), replacementString: "/")
        #expect(harness.coordinator.didRequestSlashMenu == false)
    }
}
