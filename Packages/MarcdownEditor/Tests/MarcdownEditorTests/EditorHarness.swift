import AppKit
import SwiftUI

@testable import MarcdownEditor

/// Real TextKit 1 stack + Coordinator, mirroring the private harness in
/// `ListIndentCommandTests`. New command tests share this one.
@MainActor
struct EditorHarness {
    let storage: NSTextStorage
    let textView: NSTextView
    let coordinator: NoteEditorView.Coordinator

    static func make(buffer: String) -> EditorHarness {
        let storage = NSTextStorage(string: buffer)
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        layoutManager.addTextContainer(container)
        let textView = UndoableTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 400), textContainer: container)
        textView.allowsUndo = true
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true

        var sink = buffer
        let coordinator = NoteEditorView.Coordinator(text: Binding(get: { sink }, set: { sink = $0 }))
        textView.delegate = coordinator
        coordinator.install(textView: textView, storage: storage)
        coordinator.restyle()
        return EditorHarness(storage: storage, textView: textView, coordinator: coordinator)
    }

    func setCaret(_ location: Int) {
        textView.setSelectedRange(NSRange(location: location, length: 0))
    }

    func select(_ location: Int, _ length: Int) {
        textView.setSelectedRange(NSRange(location: location, length: length))
    }

    func send(_ selector: Selector) -> Bool {
        coordinator.textView(textView, doCommandBy: selector)
    }
}

/// The real editor gets its undo manager from the panel window. A windowless
/// test view has none, so `shouldChangeText` would register nothing to undo.
private final class UndoableTextView: NSTextView {
    private let ownUndoManager = UndoManager()

    override var undoManager: UndoManager? { ownUndoManager }
}
