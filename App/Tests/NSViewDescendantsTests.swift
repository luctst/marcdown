import AppKit
import Testing

@testable import Marcdown

/// Locks down `NSView.firstDescendant(ofType:)`, the depth-first tree walk
/// `triggerFind()` relies on to dispatch `performFindPanelAction(_:)` directly
/// to the editor's `NSTextView`. The previous implementation used
/// `NSApp.sendAction(... to: nil)` which silently no-op'd once the SwiftUI
/// overlay tore down and the text view dropped out of the responder chain
/// (see fix/panel-action-bugs). If anyone breaks this helper — most plausibly
/// by removing the recursive call or short-circuiting the self-check — the
/// find action and any future direct-dispatch site break with it.
@MainActor
@Suite("NSView.firstDescendant(ofType:)")
struct NSViewDescendantsTests {
    @Test("Self-match returns the receiver itself")
    func selfMatchReturnsSelf() {
        let textView = NSTextView()

        let result = textView.firstDescendant(ofType: NSTextView.self)

        #expect(result === textView)
    }

    @Test("Direct child of matching type is returned")
    func directChildMatch() {
        let parent = NSView()
        let textView = NSTextView()
        parent.addSubview(textView)

        let result = parent.firstDescendant(ofType: NSTextView.self)

        #expect(result === textView)
    }

    @Test("Deeply nested descendant is found via recursion")
    func nestedDescendantFound() {
        // NSView -> NSScrollView -> NSClipView -> NSTextView mimics the real
        // editor hierarchy that `triggerFind()` walks from the panel content view.
        let root = NSView()
        let scrollView = NSScrollView()
        let clipView = NSClipView()
        let textView = NSTextView()
        clipView.addSubview(textView)
        scrollView.addSubview(clipView)
        root.addSubview(scrollView)

        let result = root.firstDescendant(ofType: NSTextView.self)

        #expect(result === textView)
    }

    @Test("Depth-first ordering: leftmost subtree wins even when deeper than siblings")
    func depthFirstOrdering() {
        // Branch A: depth 3 textview. Branch B: depth 1 textview.
        // Depth-first traversal must visit branch A in full before branch B,
        // so the deeper-but-earlier match should win.
        let root = NSView()

        let branchA = NSView()
        let aMid = NSView()
        let aInner = NSView()
        let deepTextView = NSTextView()
        aInner.addSubview(deepTextView)
        aMid.addSubview(aInner)
        branchA.addSubview(aMid)

        let branchB = NSView()
        let shallowTextView = NSTextView()
        branchB.addSubview(shallowTextView)

        root.addSubview(branchA)
        root.addSubview(branchB)

        let result = root.firstDescendant(ofType: NSTextView.self)

        #expect(result === deepTextView)
        #expect(result !== shallowTextView)
    }

    @Test("Tree with no matching type returns nil")
    func noMatchReturnsNil() {
        let root = NSView()
        let child = NSView()
        let grandchild = NSButton()
        child.addSubview(grandchild)
        root.addSubview(child)

        let result = root.firstDescendant(ofType: NSTextView.self)

        #expect(result == nil)
    }

    @Test("Bare view with no subviews returns nil for non-self type")
    func emptySubviewsReturnsNil() {
        let view = NSView()

        let result = view.firstDescendant(ofType: NSTextView.self)

        #expect(result == nil)
    }

    @Test("Type filter discriminates between sibling types in the tree")
    func typeFilterDiscriminates() {
        // The same tree must return a button when asked for NSButton, and nil
        // when asked for NSTextView — proving the cast (`as? T`) gates results
        // by type rather than by mere presence of any subview.
        let root = NSView()
        let button = NSButton()
        root.addSubview(button)

        let buttonResult = root.firstDescendant(ofType: NSButton.self)
        let textViewResult = root.firstDescendant(ofType: NSTextView.self)

        #expect(buttonResult === button)
        #expect(textViewResult == nil)
    }
}
