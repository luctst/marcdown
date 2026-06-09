import AppKit
import SwiftUI
import Testing

@testable import MarcdownEditor

// Coordinator-level test for Spec §8.2 acceptance criterion #9:
//   "On `# |`, press Backspace. Result is an empty plain line `|`."
//
// The coordinator must consult `HeadingContinuation.backspaceOutcome` in
// `handleDeleteBackward` after the task-list and list helpers decline.

@MainActor
@Suite("Heading backspace command routing")
struct HeadingBackspaceCommandTests {

    @Test func backspaceAtEndOfEmptyH1AtomicallyStripsMarker() {
        let harness = makeHarness(buffer: "# ")
        harness.setCaret(2)

        let handled = harness.send(#selector(NSResponder.deleteBackward(_:)))

        #expect(handled == true)
        #expect(harness.storage.string == "")
        #expect(harness.textView.selectedRange() == NSRange(location: 0, length: 0))
    }

    @Test func backspaceAtEndOfEmptyHeadingAfterContentEatsPrecedingNewline() {
        let harness = makeHarness(buffer: "hello\n# ")
        harness.setCaret(8)

        let handled = harness.send(#selector(NSResponder.deleteBackward(_:)))

        #expect(handled == true)
        #expect(harness.storage.string == "hello")
        #expect(harness.textView.selectedRange() == NSRange(location: 5, length: 0))
    }

    @Test func backspaceOnNonEmptyHeadingFallsThroughToAppKit() {
        // The coordinator must NOT hijack a backspace on a non-empty heading
        // body — that's a normal char delete handled by AppKit.
        let harness = makeHarness(buffer: "# Hello")
        harness.setCaret(7)

        let handled = harness.send(#selector(NSResponder.deleteBackward(_:)))

        #expect(handled == false)
        // Storage unchanged because the coordinator did not perform an edit
        // and AppKit's default is not dispatched through our synthetic path.
        #expect(harness.storage.string == "# Hello")
    }

    // MARK: - Harness

    private func makeHarness(buffer: String) -> Harness {
        let storage = NSTextStorage(string: buffer)
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(
            size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        )
        layoutManager.addTextContainer(container)

        let textView = NSTextView(
            frame: NSRect(x: 0, y: 0, width: 400, height: 400),
            textContainer: container
        )
        textView.allowsUndo = true
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true

        var sink = buffer
        let binding = Binding<String>(get: { sink }, set: { sink = $0 })
        let coordinator = NoteEditorView.Coordinator(text: binding)
        textView.delegate = coordinator
        coordinator.install(textView: textView, storage: storage)
        coordinator.restyle()

        return Harness(storage: storage, textView: textView, coordinator: coordinator)
    }

    @MainActor
    private struct Harness {
        let storage: NSTextStorage
        let textView: NSTextView
        let coordinator: NoteEditorView.Coordinator

        func setCaret(_ location: Int) {
            textView.setSelectedRange(NSRange(location: location, length: 0))
        }

        func send(_ selector: Selector) -> Bool {
            coordinator.textView(textView, doCommandBy: selector)
        }
    }
}
