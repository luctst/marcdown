import AppKit
import SwiftUI
import Testing

@testable import MarcdownEditor

// Coordinator-level integration tests for Tab / Shift-Tab on list lines and
// Shift+Return on continuation lines. These exercise the full keystroke
// pipeline via `textView(_:doCommandBy:)`.
//
// Expected coordinator routing (to be implemented by guy in NoteEditorView):
// - `#selector(NSResponder.insertTab(_:))` → indent the current list line by
//   prepending "  ". On a non-list line, return `false` so AppKit's default
//   tab insertion runs.
// - `#selector(NSResponder.insertBacktab(_:))` → outdent the current list
//   line by stripping up to 2 leading spaces or 1 tab.
// - `#selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))` →
//   Shift+Return: insert a plain "\n" without list continuation. Currently
//   AppKit maps Shift+Return to this selector for `NSTextView`. Coordinator
//   handles by performing the raw insertion and returning `true`.

@MainActor
@Suite("List indent / Shift+Return command routing")
struct ListIndentCommandTests {

    // MARK: - Tab on list lines

    @Test func tabOnBulletLineIndentsByTwoSpaces() {
        let harness = makeHarness(buffer: "- foo")
        harness.setCaret(5)

        let handled = harness.send(#selector(NSResponder.insertTab(_:)))

        #expect(handled == true)
        #expect(harness.storage.string == "  - foo")
        #expect(harness.textView.selectedRange() == NSRange(location: 7, length: 0))
    }

    @Test func tabOnOrderedLineIndentsByTwoSpaces() {
        let harness = makeHarness(buffer: "1. foo")
        harness.setCaret(6)

        let handled = harness.send(#selector(NSResponder.insertTab(_:)))

        #expect(handled == true)
        #expect(harness.storage.string == "  1. foo")
        #expect(harness.textView.selectedRange() == NSRange(location: 8, length: 0))
    }

    @Test func tabOnTaskLineIndentsByTwoSpaces() {
        let harness = makeHarness(buffer: "- [ ] foo")
        harness.setCaret(9)

        let handled = harness.send(#selector(NSResponder.insertTab(_:)))

        #expect(handled == true)
        #expect(harness.storage.string == "  - [ ] foo")
        #expect(harness.textView.selectedRange() == NSRange(location: 11, length: 0))
    }

    @Test func tabOnPlainLineFallsThroughToAppKit() {
        // On a plain line, the coordinator returns false. AppKit then inserts
        // its default tab character. Spec §19 — explicitly NOT a code-block
        // conversion (we diverge from Bear here).
        let harness = makeHarness(buffer: "hello")
        harness.setCaret(5)

        let handled = harness.send(#selector(NSResponder.insertTab(_:)))

        // Coordinator did not claim → AppKit's default would have inserted
        // "\t" (or whatever NSTextView's tab semantics are). The storage is
        // unchanged because our synthetic NSTextView delegate path doesn't
        // dispatch the default tab insertion. The important assertion is
        // that the coordinator did not modify the buffer.
        #expect(handled == false)
        #expect(harness.storage.string == "hello")
    }

    // MARK: - Shift-Tab on list lines

    @Test func backtabOnIndentedBulletOutdentsByTwoSpaces() {
        let harness = makeHarness(buffer: "  - foo")
        harness.setCaret(7)

        let handled = harness.send(#selector(NSResponder.insertBacktab(_:)))

        #expect(handled == true)
        #expect(harness.storage.string == "- foo")
        #expect(harness.textView.selectedRange() == NSRange(location: 5, length: 0))
    }

    @Test func backtabOnTopLevelBulletIsNoOp() {
        let harness = makeHarness(buffer: "- foo")
        harness.setCaret(5)

        let handled = harness.send(#selector(NSResponder.insertBacktab(_:)))

        // Coordinator should not consume the keystroke when there is nothing
        // to outdent — let AppKit's default (typically nothing visible) run.
        #expect(handled == false)
        #expect(harness.storage.string == "- foo")
    }

    @Test func backtabOnIndentedOrderedItemOutdentsByTwoSpaces() {
        let harness = makeHarness(buffer: "  1. foo")
        harness.setCaret(8)

        let handled = harness.send(#selector(NSResponder.insertBacktab(_:)))

        #expect(handled == true)
        #expect(harness.storage.string == "1. foo")
        #expect(harness.textView.selectedRange() == NSRange(location: 6, length: 0))
    }

    // MARK: - Shift+Return: insertNewlineIgnoringFieldEditor

    @Test func shiftReturnOnBulletInsertsPlainNewline() {
        // Spec §4.10: Shift+Return inserts a plain `\n` without continuing
        // the list. Cursor lands on the new (plain) line.
        let harness = makeHarness(buffer: "- foo")
        harness.setCaret(5)

        let handled = harness.send(#selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)))

        #expect(handled == true)
        #expect(harness.storage.string == "- foo\n")
        #expect(harness.textView.selectedRange() == NSRange(location: 6, length: 0))
    }

    @Test func shiftReturnOnOrderedInsertsPlainNewline() {
        let harness = makeHarness(buffer: "1. foo")
        harness.setCaret(6)

        let handled = harness.send(#selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)))

        #expect(handled == true)
        #expect(harness.storage.string == "1. foo\n")
        #expect(harness.textView.selectedRange() == NSRange(location: 7, length: 0))
    }

    @Test func shiftReturnOnTaskInsertsPlainNewline() {
        let harness = makeHarness(buffer: "- [ ] foo")
        harness.setCaret(9)

        let handled = harness.send(#selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)))

        #expect(handled == true)
        #expect(harness.storage.string == "- [ ] foo\n")
        #expect(harness.textView.selectedRange() == NSRange(location: 10, length: 0))
    }

    @Test func shiftReturnOnBlockquoteInsertsPlainNewline() {
        let harness = makeHarness(buffer: "> hello")
        harness.setCaret(7)

        let handled = harness.send(#selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)))

        #expect(handled == true)
        #expect(harness.storage.string == "> hello\n")
        #expect(harness.textView.selectedRange() == NSRange(location: 8, length: 0))
    }

    // MARK: - Tab / Shift-Tab over a multi-line selection

    @Test func tabWithSelectionIndentsAllSelectedListLines() {
        let harness = makeHarness(buffer: "- a\n- b")
        harness.textView.setSelectedRange(NSRange(location: 0, length: 7))

        let handled = harness.send(#selector(NSResponder.insertTab(_:)))

        #expect(handled == true)
        #expect(harness.storage.string == "  - a\n  - b")
        #expect(harness.textView.selectedRange() == NSRange(location: 0, length: 11))
    }

    @Test func backtabWithSelectionOutdentsAllSelectedListLines() {
        let harness = makeHarness(buffer: "  - a\n  - b")
        harness.textView.setSelectedRange(NSRange(location: 0, length: 11))

        let handled = harness.send(#selector(NSResponder.insertBacktab(_:)))

        #expect(handled == true)
        #expect(harness.storage.string == "- a\n- b")
    }

    @Test func backtabWithSelectionKeepsSelectionAfterRenumber() {
        let harness = makeHarness(buffer: "1. a\n  1. x\n  2. y\n2. b")
        harness.textView.setSelectedRange(NSRange(location: 5, length: 12))

        let handled = harness.send(#selector(NSResponder.insertBacktab(_:)))

        #expect(handled == true)
        #expect(harness.storage.string == "1. a\n2. x\n3. y\n4. b")
        #expect(harness.textView.selectedRange() == NSRange(location: 5, length: 9))
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
