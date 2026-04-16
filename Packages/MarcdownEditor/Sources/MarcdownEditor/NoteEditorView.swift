import AppKit
import MarcdownStyling
import SwiftUI

/// SwiftUI wrapper around an `NSTextView` for editing markdown notes with
/// live, Typora/Obsidian-style inline styling.
///
/// The view owns its own TextKit 1 stack (`NSTextStorage` → `NSLayoutManager`
/// → `NSTextContainer` → `NSTextView`) so the `NSTextStorage` is injectable
/// and can be restyled in place on every keystroke without disrupting the
/// user's cursor or selection.
///
/// There are no formatting hotkeys. The user types raw markdown; the styler
/// reacts.
public struct NoteEditorView: NSViewRepresentable {
    @Binding private var text: String

    public init(text: Binding<String>) {
        self._text = text
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        // Build the TextKit 1 stack manually so we own the NSTextStorage.
        let storage = NSTextStorage(string: text)
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)

        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)

        let textView = NSTextView(frame: .zero, textContainer: container)
        textView.delegate = context.coordinator
        textView.allowsUndo = true
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [NSView.AutoresizingMask.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 16, height: 16)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView

        context.coordinator.install(textView: textView, storage: storage)
        // Initial styling pass.
        context.coordinator.restyle()

        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard
            let textView = nsView.documentView as? NSTextView,
            let storage = textView.textStorage
        else { return }

        // Only replace the storage contents if the binding diverged from the
        // buffer (e.g. the note was reloaded from disk). Don't touch it on
        // every keystroke — that would fight the user's selection.
        if storage.string != text {
            let selected = textView.selectedRanges
            storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: text)
            textView.selectedRanges = selected
            context.coordinator.restyle()
        }
    }

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>
        private weak var textView: NSTextView?
        private weak var storage: NSTextStorage?
        private let styler = MarkdownStyler()

        init(text: Binding<String>) {
            self.text = text
        }

        func install(textView: NSTextView, storage: NSTextStorage) {
            self.textView = textView
            self.storage = storage
        }

        func restyle() {
            guard let storage else { return }
            styler.restyle(storage: storage, source: storage.string)
        }

        public func textDidChange(_ notification: Notification) {
            guard
                let textView = notification.object as? NSTextView,
                let storage = textView.textStorage
            else { return }

            // During IME composition (e.g. CJK input) the textStorage briefly
            // contains marked text that shouldn't be restyled — doing so eats
            // the composition. Skip and wait for the next change.
            if textView.hasMarkedText() { return }

            // Restyle first so the attributed buffer is up to date, then
            // propagate the plain string to the binding for the view model's
            // debounced save to pick up.
            styler.restyle(storage: storage, source: storage.string)
            text.wrappedValue = storage.string
        }
    }
}
