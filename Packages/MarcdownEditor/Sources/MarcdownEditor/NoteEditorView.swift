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

        // The concealment delegate suppresses glyphs whose characters are
        // tagged `.marcdownConcealed`. NSLayoutManager.delegate is `weak`, so
        // the Coordinator owns the strong reference.
        layoutManager.delegate = context.coordinator.layoutDelegate

        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)

        let textView = FocusOnAttachTextView(frame: .zero, textContainer: container)
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

        // First-responder is claimed exactly once by `FocusOnAttachTextView`
        // when it first attaches to a window. This avoids stealing focus
        // every time SwiftUI recreates the representable.

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
            // Document was replaced — any cached "currently revealed line"
            // refers to a different document and must be invalidated.
            context.coordinator.resetRevealCache()
            context.coordinator.restyle()
        }
    }

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>
        private weak var textView: NSTextView?
        private weak var storage: NSTextStorage?
        private let styler = MarkdownStyler()
        /// Held strongly because `NSLayoutManager.delegate` is `weak`.
        let layoutDelegate = ConcealmentLayoutDelegate()
        /// The line range whose syntax markers are currently revealed (the
        /// caret's line). `nil` means "no line revealed". Invalidated when
        /// the document is replaced.
        private var lastRevealedLineRange: NSRange?

        init(text: Binding<String>) {
            self.text = text
        }

        func install(textView: NSTextView, storage: NSTextStorage) {
            self.textView = textView
            self.storage = storage
        }

        func restyle() {
            guard let storage else { return }
            styler.restyle(
                storage: storage,
                source: storage.string,
                revealedLineRange: lastRevealedLineRange
            )
        }

        func resetRevealCache() {
            lastRevealedLineRange = nil
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

            // Re-derive the revealed line range from the *current* caret —
            // a keystroke can shift line boundaries (e.g. inserting a newline
            // splits a line in two), so a cached range from before the edit
            // is potentially stale. Falling back to the cache is safe because
            // the styler clamps internally.
            let revealed = currentCaretLineRange(in: storage, textView: textView)
                ?? lastRevealedLineRange
            lastRevealedLineRange = revealed

            // Restyle first so the attributed buffer is up to date, then
            // propagate the plain string to the binding for the view model's
            // debounced save to pick up.
            styler.restyle(
                storage: storage,
                source: storage.string,
                revealedLineRange: revealed
            )
            text.wrappedValue = storage.string
        }

        public func textViewDidChangeSelection(_ notification: Notification) {
            guard
                let textView = notification.object as? NSTextView,
                let storage = textView.textStorage
            else { return }

            // Same IME guard as textDidChange — restyling during composition
            // eats marked text.
            if textView.hasMarkedText() { return }

            guard let lineRange = currentCaretLineRange(in: storage, textView: textView) else {
                return
            }

            // No-op if the caret is still on the same line. This is the hot
            // path on every cursor key press.
            if let cached = lastRevealedLineRange,
               NSEqualRanges(cached, lineRange) {
                return
            }

            lastRevealedLineRange = lineRange
            styler.restyle(
                storage: storage,
                source: storage.string,
                revealedLineRange: lineRange
            )
        }

        /// Returns the line range containing the caret's primary insertion
        /// point. Returns `nil` if there's no usable selection (rare — only
        /// during teardown).
        private func currentCaretLineRange(
            in storage: NSTextStorage,
            textView: NSTextView
        ) -> NSRange? {
            guard let primary = textView.selectedRanges.first else { return nil }
            let selection = primary.rangeValue
            // Use only the location — `lineRange(for:)` already expands a
            // zero-length range correctly, but a multi-line selection should
            // reveal the line where the caret is, not span every selected
            // line.
            let caret = NSRange(location: selection.location, length: 0)
            let nsString = storage.string as NSString
            // Defensive bound: caret can briefly equal storage length on append.
            guard caret.location >= 0, caret.location <= nsString.length else { return nil }
            return nsString.lineRange(for: caret)
        }
    }
}

/// `NSTextView` that claims first responder exactly once on first window
/// attach. SwiftUI may recreate the `NSViewRepresentable` mid-session; doing
/// the focus dance unconditionally in `makeNSView` would steal focus from
/// wherever the user was working.
private final class FocusOnAttachTextView: NSTextView {
    private var didClaimFocus = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !didClaimFocus, let window else { return }
        didClaimFocus = true
        window.makeFirstResponder(self)
    }
}
