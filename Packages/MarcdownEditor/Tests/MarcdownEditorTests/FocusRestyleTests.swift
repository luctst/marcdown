import AppKit
import MarcdownStyling
import SwiftUI
import Testing

@testable import MarcdownEditor

@MainActor
@Suite("Focus-line restyle guard")
struct FocusRestyleTests {
    @Test func movingWithinALineKeepsRevealAndMovingLinesUpdatesIt() {
        let storage = NSTextStorage(string: "**a**\n**b**")
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        layoutManager.addTextContainer(container)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 400), textContainer: container)
        var sink = ""
        let coordinator = NoteEditorView.Coordinator(text: Binding(get: { sink }, set: { sink = $0 }))
        textView.delegate = coordinator
        coordinator.install(textView: textView, storage: storage)

        textView.setSelectedRange(NSRange(location: 1, length: 0))
        coordinator.textViewDidChangeSelection(Notification(name: NSText.didChangeNotification, object: textView))
        #expect(coordinator.revealedFocusLine == FocusLine(lineStart: 0, lineLength: 5))
        #expect(storage.attribute(.marcdownConcealed, at: 0, effectiveRange: nil) as? Bool != true)

        textView.setSelectedRange(NSRange(location: 3, length: 0))
        coordinator.textViewDidChangeSelection(Notification(name: NSText.didChangeNotification, object: textView))
        #expect(coordinator.revealedFocusLine == FocusLine(lineStart: 0, lineLength: 5))

        textView.setSelectedRange(NSRange(location: 8, length: 0))
        coordinator.textViewDidChangeSelection(Notification(name: NSText.didChangeNotification, object: textView))
        #expect(coordinator.revealedFocusLine == FocusLine(lineStart: 6, lineLength: 5))
        #expect(storage.attribute(.marcdownConcealed, at: 0, effectiveRange: nil) as? Bool == true)
        #expect(storage.attribute(.marcdownConcealed, at: 6, effectiveRange: nil) as? Bool != true)
    }
}
