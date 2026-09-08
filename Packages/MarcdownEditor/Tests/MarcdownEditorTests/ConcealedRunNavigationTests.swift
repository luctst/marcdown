import AppKit
import SwiftUI
import Testing

@testable import MarcdownEditor

// Thomas §1c (the "arrowing through a concealed link URL" pain point):
// when arrow-key navigation encounters a `.marcdownConcealed` run, the
// cursor should jump the entire run in one keypress instead of crawling
// character by character. This makes long link URLs traversable.
//
// Expected coordinator routing:
//   `#selector(NSResponder.moveLeft(_:))`  → handle concealed-run skip leftward
//   `#selector(NSResponder.moveRight(_:))` → handle concealed-run skip rightward
//   `#selector(NSResponder.moveLeftAndModifySelection(_:))`
//   `#selector(NSResponder.moveRightAndModifySelection(_:))`
//
// Contract:
// - If the character immediately adjacent (in the motion direction) carries
//   `.marcdownConcealed = true`, the cursor jumps to the FAR side of the
//   maximal concealed run in one motion.
// - If there is no concealed run adjacent, return `false` so AppKit's default
//   single-char motion runs.
// - With Option held, fall back to char-by-char motion. (Future work; for
//   now we don't test that path — guy should keep the helper restricted to
//   the unmodified arrow keys.)
//
// Note: the styler must have run a restyle pass so `.marcdownConcealed`
// attributes are present.

@MainActor
@Suite("Concealed-run arrow navigation")
struct ConcealedRunNavigationTests {

    @Test func rightArrowJumpsOverConcealedClosingLinkSyntax() {
        // Buffer: "[a](b)" — label "a" at offset 1, closing `](b)` at offsets
        // 2..<6 is one big concealed run. Cursor right after the label (at
        // offset 2) should jump to offset 6 (past the URL) in one keypress.
        let harness = makeHarness(buffer: "[a](b)")
        harness.setCaret(2)

        let handled = harness.send(#selector(NSResponder.moveRight(_:)))

        #expect(handled == true)
        #expect(harness.textView.selectedRange() == NSRange(location: 6, length: 0))
    }

    @Test func leftArrowJumpsOverConcealedClosingLinkSyntax() {
        // Same buffer, cursor at end (offset 6). Left arrow jumps to offset 2
        // (start of the concealed `](b)` run).
        let harness = makeHarness(buffer: "[a](b)")
        harness.setCaret(6)

        let handled = harness.send(#selector(NSResponder.moveLeft(_:)))

        #expect(handled == true)
        #expect(harness.textView.selectedRange() == NSRange(location: 2, length: 0))
    }

    @Test func rightArrowJumpsOverBoldOpeningDelimiter() {
        // "**foo**" — concealed `**` at 0..<2, then body "foo", then `**` at 5..<7.
        // Cursor at offset 0, right arrow should jump to offset 2.
        let harness = makeHarness(buffer: "**foo**")
        harness.setCaret(0)

        let handled = harness.send(#selector(NSResponder.moveRight(_:)))

        #expect(handled == true)
        #expect(harness.textView.selectedRange() == NSRange(location: 2, length: 0))
    }

    @Test func rightArrowOnPlainCharFallsThroughToAppKit() {
        // On body text, the coordinator returns `false` so AppKit's default
        // single-char motion runs. Cursor stays put because our synthetic
        // path doesn't dispatch AppKit's default action.
        let harness = makeHarness(buffer: "hello")
        harness.setCaret(0)

        let handled = harness.send(#selector(NSResponder.moveRight(_:)))

        #expect(handled == false)
    }

    @Test func leftArrowOnPlainCharFallsThroughToAppKit() {
        let harness = makeHarness(buffer: "hello")
        harness.setCaret(5)

        let handled = harness.send(#selector(NSResponder.moveLeft(_:)))

        #expect(handled == false)
    }

    @Test func rightArrowAtEndOfBufferIsNoOp() {
        // Cursor at end → no character to the right → nothing to skip → false.
        let harness = makeHarness(buffer: "[a](b)")
        harness.setCaret(6)

        let handled = harness.send(#selector(NSResponder.moveRight(_:)))

        #expect(handled == false)
    }

    @Test func leftArrowAtBufferStartIsNoOp() {
        let harness = makeHarness(buffer: "[a](b)")
        harness.setCaret(0)

        let handled = harness.send(#selector(NSResponder.moveLeft(_:)))

        #expect(handled == false)
    }

    @Test func shiftRightExtendsOverConcealedClosingLinkSyntax() {
        let harness = makeHarness(buffer: "[a](b) x")
        harness.textView.setSelectedRange(NSRange(location: 1, length: 1))

        let handled = harness.send(#selector(NSResponder.moveRightAndModifySelection(_:)))

        #expect(handled == true)
        #expect(harness.textView.selectedRange() == NSRange(location: 1, length: 5))
    }

    @Test func shiftLeftExtendsOverConcealedOpeningDelimiter() {
        let harness = makeHarness(buffer: "**foo**")
        harness.textView.setSelectedRange(NSRange(location: 2, length: 3))

        let handled = harness.send(#selector(NSResponder.moveLeftAndModifySelection(_:)))

        #expect(handled == true)
        #expect(harness.textView.selectedRange() == NSRange(location: 0, length: 5))
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
        // Restyle so .marcdownConcealed attributes are present.
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
