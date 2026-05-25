import AppKit
import SwiftUI
import Testing

@testable import MarcdownEditor

/// Regression tests for `Coordinator.textView(_:doCommandBy:)` handling of
/// line-scoped delete and move commands. The fix introduces a private
/// `lineStartOffset(in:cursor:)` helper that scans back to `\n` so these
/// commands respect the *storage* line start rather than letting AppKit's
/// default behavior consume a concealed heading marker, or worse, fall off
/// the previous line.
///
/// We exercise the coordinator through its public `textView(_:doCommandBy:)`
/// entry point. The `Coordinator` is constructed directly and wired to an
/// in-memory `NSTextView` + `NSTextStorage` via the package-internal
/// `install(textView:storage:)` method (made reachable via `@testable`).
@MainActor
@Suite("Line-scoped delete / move commands")
struct LineScopedCommandTests {

    // MARK: - deleteToBeginningOfLine (CMD+Delete)

    @Test func deleteToBeginningOfLine_concealedHeading_deletesEntireLine() {
        let harness = makeHarness(buffer: "# Hello")
        harness.setCaret(7)

        let handled = harness.send(#selector(NSResponder.deleteToBeginningOfLine(_:)))

        #expect(handled == true)
        #expect(harness.storage.string == "")
        #expect(harness.textView.selectedRange() == NSRange(location: 0, length: 0))
    }

    @Test func deleteToBeginningOfLine_multilineBuffer_deletesOnlyCurrentLine() {
        let source = "first\n# Hello"
        let harness = makeHarness(buffer: source)
        harness.setCaret((source as NSString).length)  // 13

        let handled = harness.send(#selector(NSResponder.deleteToBeginningOfLine(_:)))

        #expect(handled == true)
        #expect(harness.storage.string == "first\n")
        // Caret lands at the start of the (now-empty) second line — right
        // after the newline, offset 6.
        #expect(harness.textView.selectedRange() == NSRange(location: 6, length: 0))
    }

    @Test func deleteToBeginningOfLine_atLineStart_bailsAndKeepsNewline() {
        let source = "first\nsecond"
        let harness = makeHarness(buffer: source)
        // Caret at offset 6 = start of "second", immediately after the `\n`.
        harness.setCaret(6)

        let handled = harness.send(#selector(NSResponder.deleteToBeginningOfLine(_:)))

        // Coordinator should bail (return false) so AppKit's default — which
        // would NOT eat the newline — runs. Critically, the storage must not
        // have the preceding `\n` consumed by our handler.
        #expect(handled == false)
        #expect(harness.storage.string == "first\nsecond")
    }

    // MARK: - deleteWordBackward (Option+Delete)

    @Test func deleteWordBackward_concealedHeadingWithSingleWord_deletesEntireLine() {
        let harness = makeHarness(buffer: "# foo")
        harness.setCaret(5)

        let handled = harness.send(#selector(NSResponder.deleteWordBackward(_:)))

        #expect(handled == true)
        #expect(harness.storage.string == "")
        #expect(harness.textView.selectedRange() == NSRange(location: 0, length: 0))
    }

    @Test func deleteWordBackward_keepsConcealedMarkerWhenVisibleContentRemains() {
        // After typing `# foo bar` and hitting ⌥+Delete at end, only `bar`
        // (and the space before it) should go. The concealed `# ` marker
        // stays because there is visible content (`foo `) between it and
        // the deleted word — the rangeIsAllConcealed check fails.
        let harness = makeHarness(buffer: "# foo bar")
        harness.setCaret(9)

        let handled = harness.send(#selector(NSResponder.deleteWordBackward(_:)))

        #expect(handled == true)
        // AppKit's word-back from end of "bar" lands at the `b` (offset 6),
        // so we delete "bar". The trailing space stays.
        #expect(harness.storage.string == "# foo ")
    }

    // MARK: - moveToBeginningOfLine (CMD+Left / Home)

    @Test func moveToBeginningOfLine_concealedHeading_cursorGoesToTrueLineStart() {
        let harness = makeHarness(buffer: "# Hello")
        harness.setCaret(7)

        let handled = harness.send(#selector(NSResponder.moveToBeginningOfLine(_:)))

        #expect(handled == true)
        // The fix: cursor lands at offset 0 (storage line start), NOT at
        // offset 2 after the concealed `# ` marker.
        #expect(harness.textView.selectedRange() == NSRange(location: 0, length: 0))
        // Storage is untouched by a move command.
        #expect(harness.storage.string == "# Hello")
    }

    @Test func moveToBeginningOfLineAndModifySelection_selectsFromTrueLineStart() {
        let harness = makeHarness(buffer: "# Hello")
        harness.setCaret(7)

        let handled = harness.send(
            #selector(NSResponder.moveToBeginningOfLineAndModifySelection(_:))
        )

        #expect(handled == true)
        // The whole line (including the concealed marker) is selected.
        #expect(harness.textView.selectedRange() == NSRange(location: 0, length: 7))
        #expect(harness.storage.string == "# Hello")
    }

    // MARK: - Harness

    /// Minimal in-memory wiring: an `NSTextStorage`, an `NSTextView`, and a
    /// `Coordinator` joined via the same `install(textView:storage:)` call
    /// the production `NSViewRepresentable` uses. We restyle once so
    /// concealment attributes are present on heading markers — the
    /// `rangeIsAllConcealed` branch in `handleDeleteWordBackward` requires
    /// real `.marcdownConcealed` attrs.
    private func makeHarness(buffer: String) -> Harness {
        let storage = NSTextStorage(string: buffer)
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(
            size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        )
        layoutManager.addTextContainer(container)

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 400), textContainer: container)
        textView.allowsUndo = true
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true

        // Bind to a throwaway state; the coordinator only writes back to the
        // binding from `textDidChange`, which we don't invoke here.
        var sink = buffer
        let binding = Binding<String>(get: { sink }, set: { sink = $0 })
        let coordinator = NoteEditorView.Coordinator(text: binding)
        textView.delegate = coordinator
        coordinator.install(textView: textView, storage: storage)

        // Apply real concealment attributes so the word-back-through-marker
        // path can detect the concealed prefix.
        coordinator.restyle()

        return Harness(
            storage: storage,
            textView: textView,
            coordinator: coordinator
        )
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
