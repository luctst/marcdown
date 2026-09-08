import AppKit
import MarcdownStyling
import SwiftUI

extension Notification.Name {
    /// Posted by the App target whenever an overlay is dismissed. The editor
    /// reclaims first responder so the user can resume typing without a
    /// pointer click. The name string must stay in sync with the App target's
    /// `Notification.Name.marcdownEditorShouldFocus` declaration — a string
    /// match is intentional here to avoid creating a dependency from the
    /// editor package back into the App target.
    static let marcdownEditorShouldFocus = Notification.Name("MarcdownEditorShouldFocus")
}

/// SwiftUI wrapper around an `NSTextView` for editing markdown notes with
/// live, Typora/Obsidian-style inline styling.
///
/// The view owns its own TextKit 1 stack (`NSTextStorage` → `NSLayoutManager`
/// → `NSTextContainer` → `NSTextView`) so the `NSTextStorage` is injectable
/// and can be restyled in place on every keystroke without disrupting the
/// user's cursor or selection.
///
/// Formatting commands (⌘B, ⌘I, …) are caught in `FocusOnAttachTextView.
/// performKeyEquivalent` and routed to `Coordinator.perform`, which is also
/// the entry point for the command palette and the `/` menu.
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
        let layoutManager = CheckboxIconLayoutManager()
        // Hand the layout manager the same code-block fill color the styler
        // uses so the rounded container matches the rest of the palette.
        // Passing the resolved color (rather than the theme) keeps the
        // layout manager free of `@MainActor` coupling for its draw path.
        layoutManager.codeBlockFillColor = context.coordinator.codeBlockFillColor
        layoutManager.quoteBarColor = context.coordinator.quoteBarColor
        layoutManager.ruleColor = context.coordinator.ruleColor
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
        textView.checkboxClickHandler = { [weak coordinator = context.coordinator] charIndex in
            coordinator?.toggleCheckbox(at: charIndex)
        }
        textView.commandHandler = { [weak coordinator = context.coordinator] command in
            coordinator?.perform(command) ?? false
        }
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
        textView.font = NSFont(name: "AvenirNext-Regular", size: 15) ?? NSFont.systemFont(ofSize: 15)
        textView.defaultParagraphStyle = context.coordinator.baseParagraphStyle
        textView.typingAttributes[.paragraphStyle] = context.coordinator.baseParagraphStyle
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
            context.coordinator.restyle()
        }
    }

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>
        private weak var textView: NSTextView?
        private weak var storage: NSTextStorage?
        private let styler = MarkdownStyler()
        /// The rounded code-block container fill color, sourced from the
        /// same theme the styler uses. Exposed so `makeNSView` can pass it
        /// to the layout manager without coupling the layout manager's
        /// `nonisolated` draw path to `@MainActor` types.
        var codeBlockFillColor: NSColor { styler.theme.codeBlockBackground }
        /// Blockquote bar colour, sourced from the same theme as the styler.
        var quoteBarColor: NSColor { styler.theme.quoteBar }
        /// Horizontal rule colour, sourced from the same theme as the styler.
        var ruleColor: NSColor { styler.theme.rule }
        /// Seeds the text view's default/typing paragraph style so the caret
        /// on an empty note is as tall as the styler's line boxes.
        var baseParagraphStyle: NSParagraphStyle { styler.baseParagraphStyle }
        /// Held strongly because `NSLayoutManager.delegate` is `weak`.
        let layoutDelegate = ConcealmentLayoutDelegate()
        /// Token for the focus-restore observer, removed on deinit. Mirrors
        /// the existing pattern used elsewhere for `NotificationCenter`
        /// subscriptions inside Coordinators. `nonisolated(unsafe)` so the
        /// nonisolated `deinit` can read the token to unregister; access from
        /// `init` and the observer block stays on `MainActor`.
        private nonisolated(unsafe) var focusObserver: NSObjectProtocol?
        /// The line the last restyle revealed. Caret moves inside that line
        /// don't change what is concealed, so `textViewDidChangeSelection`
        /// skips the full re-parse for them.
        private(set) var revealedFocusLine: FocusLine?

        init(text: Binding<String>) {
            self.text = text
            super.init()
            // Reclaim first responder whenever an overlay is dismissed.
            // Posted from `PanelRootView.dismissActiveOverlay()`. Using a
            // notification (instead of threading a callback through the
            // `NSViewRepresentable`) mirrors the `marcdownPanelDidHide`
            // pattern and keeps the wiring loosely coupled.
            focusObserver = NotificationCenter.default.addObserver(
                forName: .marcdownEditorShouldFocus,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reclaimFirstResponder()
                }
            }
        }

        deinit {
            if let focusObserver {
                NotificationCenter.default.removeObserver(focusObserver)
            }
        }

        private func reclaimFirstResponder() {
            guard let textView, let window = textView.window else { return }
            window.makeFirstResponder(textView)
        }

        func install(textView: NSTextView, storage: NSTextStorage) {
            self.textView = textView
            self.storage = storage
        }

        func restyle() {
            guard let storage else { return }
            restyle(storage: storage)
        }

        private func restyle(storage: NSTextStorage) {
            let focus = currentFocusLine()
            styler.restyle(storage: storage, source: storage.string, focusLine: focus)
            revealedFocusLine = focus
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
            restyle(storage: storage)
            text.wrappedValue = storage.string
            // Checkbox markers may have been added/removed by this edit;
            // refresh the pointing-hand hover rects so the cursor tracks
            // their current positions.
            textView.window?.invalidateCursorRects(for: textView)
        }

        public func textViewDidChangeSelection(_ notification: Notification) {
            guard
                let textView = notification.object as? NSTextView,
                let storage = textView.textStorage
            else { return }
            // Skip restyle while the user is composing IME — the marked text
            // is transient and styling would eat it.
            if textView.hasMarkedText() { return }
            // Focus-line reveal: restyle so the previously-focused line
            // re-conceals and the newly-focused line reveals.
            if currentFocusLine() == revealedFocusLine { return }
            restyle(storage: storage)
        }

        /// Compute a `FocusLine` for the current selection in the active
        /// text view. Multi-line selections currently focus only the line
        /// containing the active end (caret). A single caret returns its
        /// containing line.
        private func currentFocusLine() -> FocusLine? {
            guard let textView else { return nil }
            guard let storage = textView.textStorage else { return nil }
            let selection = textView.selectedRange()
            // For a selection, the "active end" is the caret — use `location`
            // for a simple caret and `location + length` (or `location`) for
            // an extended selection. Picking `location` matches what most
            // users perceive as the cursor.
            let cursor = selection.location
            let buffer = storage.string as NSString
            let upper = buffer.length
            guard cursor >= 0, cursor <= upper else { return nil }
            var lineStart = cursor
            while lineStart > 0, buffer.character(at: lineStart - 1) != 0x0A {
                lineStart -= 1
            }
            var lineEnd = cursor
            while lineEnd < upper, buffer.character(at: lineEnd) != 0x0A {
                lineEnd += 1
            }
            return FocusLine(lineStart: lineStart, lineLength: lineEnd - lineStart)
        }

        // MARK: - Task list keystroke handling

        public func textView(
            _ textView: NSTextView,
            doCommandBy selector: Selector
        ) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) {
                return handleInsertNewline(in: textView)
            }
            if selector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
                return handleShiftReturn(in: textView)
            }
            if selector == #selector(NSResponder.insertTab(_:)) {
                return handleInsertTab(in: textView)
            }
            if selector == #selector(NSResponder.insertBacktab(_:)) {
                return handleInsertBacktab(in: textView)
            }
            if selector == #selector(NSResponder.deleteBackward(_:)) {
                return handleDeleteBackward(in: textView)
            }
            if selector == #selector(NSResponder.deleteToBeginningOfLine(_:)) {
                return handleDeleteToBeginningOfLine(in: textView)
            }
            if selector == #selector(NSResponder.deleteWordBackward(_:)) {
                return handleDeleteWordBackward(in: textView)
            }
            if selector == #selector(NSResponder.moveToBeginningOfLine(_:)) {
                return handleMoveToBeginningOfLine(in: textView, extend: false)
            }
            if selector == #selector(NSResponder.moveToBeginningOfLineAndModifySelection(_:)) {
                return handleMoveToBeginningOfLine(in: textView, extend: true)
            }
            if selector == #selector(NSResponder.moveLeft(_:)) {
                return handleArrow(in: textView, direction: .left)
            }
            if selector == #selector(NSResponder.moveRight(_:)) {
                return handleArrow(in: textView, direction: .right)
            }
            return false
        }

        // MARK: - Tab / Shift-Tab / Shift-Return

        private func handleInsertTab(in textView: NSTextView) -> Bool {
            guard let storage = textView.textStorage else { return false }
            if textView.hasMarkedText() { return false }
            let selection = textView.selectedRange()
            // Selection-based indent (multiple lines) — TODO. For now, only
            // handle the caret case; with a selection, fall through.
            if selection.length > 0 { return false }
            let cursor = selection.location
            switch ListIndentation.indentOutcome(buffer: storage.string, cursorOffset: cursor) {
            case .noOp:
                return false
            case .replace(let range, let replacement, let cursorOffsetInBuffer):
                guard textView.shouldChangeText(in: range, replacementString: replacement) else {
                    return false
                }
                textView.undoManager?.setActionName("Indent List Item")
                storage.replaceCharacters(in: range, with: replacement)
                textView.didChangeText()
                textView.setSelectedRange(NSRange(location: cursorOffsetInBuffer, length: 0))
                // If the line is an ordered list item, the depth change may
                // require renumbering both the new and old depths.
                runRenumberPass(in: textView, around: cursorOffsetInBuffer)
                return true
            }
        }

        private func handleInsertBacktab(in textView: NSTextView) -> Bool {
            guard let storage = textView.textStorage else { return false }
            if textView.hasMarkedText() { return false }
            let selection = textView.selectedRange()
            if selection.length > 0 { return false }
            let cursor = selection.location
            switch ListIndentation.outdentOutcome(buffer: storage.string, cursorOffset: cursor) {
            case .noOp:
                return false
            case .replace(let range, let replacement, let cursorOffsetInBuffer):
                guard textView.shouldChangeText(in: range, replacementString: replacement) else {
                    return false
                }
                textView.undoManager?.setActionName("Outdent List Item")
                storage.replaceCharacters(in: range, with: replacement)
                textView.didChangeText()
                textView.setSelectedRange(NSRange(location: cursorOffsetInBuffer, length: 0))
                runRenumberPass(in: textView, around: cursorOffsetInBuffer)
                return true
            }
        }

        /// Shift+Return: insert a plain `\n` without any block continuation.
        /// Spec §4.10 / §5.7 / §9.5.
        private func handleShiftReturn(in textView: NSTextView) -> Bool {
            guard let storage = textView.textStorage else { return false }
            if textView.hasMarkedText() { return false }
            let selection = textView.selectedRange()
            let range = selection
            guard textView.shouldChangeText(in: range, replacementString: "\n") else {
                return false
            }
            textView.undoManager?.setActionName("Insert Newline")
            storage.replaceCharacters(in: range, with: "\n")
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: range.location + 1, length: 0))
            return true
        }

        // MARK: - Concealed-run arrow navigation

        private enum ArrowDirection { case left, right }

        /// If the character immediately adjacent (in the motion direction)
        /// carries `.marcdownConcealed`, jump the entire concealed run in
        /// one motion. Otherwise return `false` so AppKit's default single-
        /// character motion runs (Thomas §1c).
        private func handleArrow(in textView: NSTextView, direction: ArrowDirection) -> Bool {
            guard let storage = textView.textStorage else { return false }
            if textView.hasMarkedText() { return false }
            let selection = textView.selectedRange()
            if selection.length > 0 { return false }
            let cursor = selection.location
            let length = storage.length

            // Use the logical-concealment attribute (mirrored by the styler)
            // so the jump still triggers when the focused line has its
            // visible concealment stripped by the reveal pass.
            switch direction {
            case .right:
                guard cursor < length else { return false }
                guard
                    let flag = storage.attribute(.marcdownConcealedLogical, at: cursor, effectiveRange: nil) as? Bool,
                    flag
                else { return false }
                var effective = NSRange(location: 0, length: 0)
                _ = storage.attribute(
                    .marcdownConcealedLogical,
                    at: cursor,
                    longestEffectiveRange: &effective,
                    in: NSRange(location: 0, length: length)
                )
                let target = effective.location + effective.length
                textView.setSelectedRange(NSRange(location: target, length: 0))
                return true
            case .left:
                guard cursor > 0 else { return false }
                let probe = cursor - 1
                guard
                    let flag = storage.attribute(.marcdownConcealedLogical, at: probe, effectiveRange: nil) as? Bool,
                    flag
                else { return false }
                var effective = NSRange(location: 0, length: 0)
                _ = storage.attribute(
                    .marcdownConcealedLogical,
                    at: probe,
                    longestEffectiveRange: &effective,
                    in: NSRange(location: 0, length: length)
                )
                let target = effective.location
                textView.setSelectedRange(NSRange(location: target, length: 0))
                return true
            }
        }

        // MARK: - Renumber pass

        /// Run `OrderedListRenumber.renumberRun` on the line containing
        /// `cursor`. If the run is rewritten, apply the diff to storage and
        /// adjust the cursor. Safe to call after every list-affecting edit;
        /// non-ordered lines / single-item runs are `.noOp`.
        private func runRenumberPass(in textView: NSTextView, around cursor: Int) {
            guard let storage = textView.textStorage else { return }
            let buffer = storage.string
            let outcome = OrderedListRenumber.renumberRun(
                buffer: buffer,
                anchorOffset: cursor,
                cursorOffset: cursor
            )
            switch outcome {
            case .noOp:
                return
            case .rewrite(let newBuffer, let newCursorOffset):
                let fullRange = NSRange(location: 0, length: storage.length)
                guard textView.shouldChangeText(in: fullRange, replacementString: newBuffer) else {
                    return
                }
                storage.replaceCharacters(in: fullRange, with: newBuffer)
                textView.didChangeText()
                textView.setSelectedRange(NSRange(location: newCursorOffset, length: 0))
            }
        }

        // MARK: - Line-scoped navigation/delete

        /// Returns the UTF-16 offset of the start of the line containing
        /// `cursor`. Scans the storage string backward until a newline or the
        /// start of the buffer.
        private func lineStartOffset(in buffer: String, cursor: Int) -> Int {
            let nsString = buffer as NSString
            let upper = nsString.length
            guard cursor >= 0, cursor <= upper else { return cursor }
            var probe = cursor
            while probe > 0, nsString.character(at: probe - 1) != 0x0A {
                probe -= 1
            }
            return probe
        }

        private func handleDeleteToBeginningOfLine(in textView: NSTextView) -> Bool {
            guard let storage = textView.textStorage else { return false }
            if textView.hasMarkedText() { return false }

            let selection = textView.selectedRange()
            // A non-empty selection has a well-defined start; AppKit's default
            // deletion semantics for `deleteToBeginningOfLine:` with a
            // selection are fine. We only need to handle the caret case.
            if selection.length > 0 { return false }

            let cursor = selection.location
            let lineStart = lineStartOffset(in: storage.string, cursor: cursor)
            if cursor <= lineStart { return false }

            let range = NSRange(location: lineStart, length: cursor - lineStart)
            guard textView.shouldChangeText(in: range, replacementString: "") else {
                return false
            }
            textView.undoManager?.setActionName("Delete to Beginning of Line")
            storage.replaceCharacters(in: range, with: "")
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: lineStart, length: 0))
            return true
        }

        private func handleDeleteWordBackward(in textView: NSTextView) -> Bool {
            guard let storage = textView.textStorage else { return false }
            if textView.hasMarkedText() { return false }

            let selection = textView.selectedRange()
            if selection.length > 0 { return false }

            let cursor = selection.location
            let buffer = storage.string
            let lineStart = lineStartOffset(in: buffer, cursor: cursor)
            if cursor <= lineStart { return false }

            // Ask AppKit where its word-back motion would land.
            let proposed = NSRange(location: cursor, length: 0)
            let wordRange = textView.selectionRange(
                forProposedRange: proposed,
                granularity: .selectByWord
            )
            // `wordRange.location` is the start of the word containing the
            // caret. Clamp to the line so we never cross a newline.
            var wordStart = max(wordRange.location, lineStart)
            if wordStart >= cursor { return false }

            // If everything between the would-be word start and the start of
            // the line is concealed (markdown syntax like `# `, `- `, `[ ] `),
            // extend the deletion through to the true line start so the
            // entire visible word + its hidden marker go together.
            if wordStart > lineStart,
                rangeIsAllConcealed(
                    in: storage,
                    range: NSRange(location: lineStart, length: wordStart - lineStart)
                )
            {
                wordStart = lineStart
            }

            let range = NSRange(location: wordStart, length: cursor - wordStart)
            guard textView.shouldChangeText(in: range, replacementString: "") else {
                return false
            }
            textView.undoManager?.setActionName("Delete Word")
            storage.replaceCharacters(in: range, with: "")
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: wordStart, length: 0))
            return true
        }

        /// True if every character in `range` carries the
        /// `.marcdownConcealedLogical` attribute. An empty range returns
        /// false (no characters to extend through). We read the *logical*
        /// flag (not `.marcdownConcealed`) so focus-line reveal doesn't
        /// suppress concealment-aware deletes on the line the user is on.
        private func rangeIsAllConcealed(in storage: NSTextStorage, range: NSRange) -> Bool {
            guard range.length > 0,
                range.location >= 0,
                range.location + range.length <= storage.length
            else { return false }
            var allConcealed = true
            storage.enumerateAttribute(
                .marcdownConcealedLogical,
                in: range,
                options: []
            ) { value, _, stop in
                if (value as? Bool) != true {
                    allConcealed = false
                    stop.pointee = true
                }
            }
            return allConcealed
        }

        private func handleMoveToBeginningOfLine(
            in textView: NSTextView,
            extend: Bool
        ) -> Bool {
            guard let storage = textView.textStorage else { return false }
            if textView.hasMarkedText() { return false }

            let selection = textView.selectedRange()
            // The caret end is the active end for shift-extended moves.
            let cursor = extend ? selection.location + selection.length : selection.location
            let lineStart = lineStartOffset(in: storage.string, cursor: cursor)
            if cursor <= lineStart { return false }

            if extend {
                // Extend the selection so its active end is at the true line
                // start. If the caret was below the anchor we collapse onto
                // the line start; otherwise we grow leftward.
                let anchor = selection.location
                if lineStart <= anchor {
                    textView.setSelectedRange(
                        NSRange(location: lineStart, length: anchor - lineStart)
                    )
                } else {
                    textView.setSelectedRange(
                        NSRange(location: anchor, length: lineStart - anchor)
                    )
                }
            } else {
                textView.setSelectedRange(NSRange(location: lineStart, length: 0))
            }
            return true
        }

        private func handleInsertNewline(in textView: NSTextView) -> Bool {
            guard let storage = textView.textStorage else { return false }
            if textView.hasMarkedText() { return false }

            let cursor = textView.selectedRange().location
            let outcome = TaskListContinuation.enterOutcome(
                buffer: storage.string,
                cursorOffset: cursor
            )
            switch outcome {
            case .noOp:
                break
            case .replace(let range, let replacement, let cursorOffsetInBuffer):
                let undoName = replacement.isEmpty ? "Remove Task Item" : "New Task Item"
                guard textView.shouldChangeText(in: range, replacementString: replacement) else {
                    return false
                }
                textView.undoManager?.setActionName(undoName)
                storage.replaceCharacters(in: range, with: replacement)
                textView.didChangeText()
                textView.setSelectedRange(NSRange(location: cursorOffsetInBuffer, length: 0))
                // textDidChange will run a restyle pass + propagate text.
                return true
            }

            // Task-list helper did not claim the keystroke — try the plain
            // list-marker helper as a fallback. Checkbox continuation must
            // keep precedence, hence this ordering.
            let listOutcome = ListContinuation.enterOutcome(
                buffer: storage.string,
                cursorOffset: cursor
            )
            switch listOutcome {
            case .noOp:
                break
            case .replace(let range, let replacement, let cursorOffsetInBuffer):
                let undoName = replacement.isEmpty ? "Remove List Item" : "New List Item"
                guard textView.shouldChangeText(in: range, replacementString: replacement) else {
                    return false
                }
                textView.undoManager?.setActionName(undoName)
                storage.replaceCharacters(in: range, with: replacement)
                textView.didChangeText()
                textView.setSelectedRange(NSRange(location: cursorOffsetInBuffer, length: 0))
                // Renumber any ordered run whose structure may have changed.
                runRenumberPass(in: textView, around: cursorOffsetInBuffer)
                return true
            }

            // Blockquote helper — Spec §9.
            let blockquoteOutcome = BlockquoteContinuation.enterOutcome(
                buffer: storage.string,
                cursorOffset: cursor
            )
            switch blockquoteOutcome {
            case .noOp:
                return false
            case .replace(let range, let replacement, let cursorOffsetInBuffer):
                let undoName = replacement.isEmpty ? "Exit Blockquote" : "New Blockquote Line"
                guard textView.shouldChangeText(in: range, replacementString: replacement) else {
                    return false
                }
                textView.undoManager?.setActionName(undoName)
                storage.replaceCharacters(in: range, with: replacement)
                textView.didChangeText()
                textView.setSelectedRange(NSRange(location: cursorOffsetInBuffer, length: 0))
                return true
            }
        }

        private func handleDeleteBackward(in textView: NSTextView) -> Bool {
            guard let storage = textView.textStorage else { return false }
            if textView.hasMarkedText() { return false }

            // Selection BS is a normal range delete; defer to AppKit.
            let selection = textView.selectedRange()
            if selection.length > 0 { return false }

            let cursor = selection.location
            let outcome = BackspaceContinuation.deleteOutcome(
                buffer: storage.string,
                cursorOffset: cursor
            )
            switch outcome {
            case .standard:
                break
            case .replace(let range, let cursorOffsetInBuffer):
                guard textView.shouldChangeText(in: range, replacementString: "") else {
                    return false
                }
                textView.undoManager?.setActionName("Remove Task Item")
                storage.replaceCharacters(in: range, with: "")
                textView.didChangeText()
                textView.setSelectedRange(NSRange(location: cursorOffsetInBuffer, length: 0))
                // textDidChange will run a restyle pass + propagate text.
                return true
            }

            // Task-list backspace helper did not claim the keystroke — try
            // the plain list-marker helper as a fallback.
            let listOutcome = ListContinuation.backspaceOutcome(
                buffer: storage.string,
                cursorOffset: cursor
            )
            switch listOutcome {
            case .standard:
                break
            case .replace(let range, let cursorOffsetInBuffer):
                guard textView.shouldChangeText(in: range, replacementString: "") else {
                    return false
                }
                textView.undoManager?.setActionName("Remove List Item")
                storage.replaceCharacters(in: range, with: "")
                textView.didChangeText()
                textView.setSelectedRange(NSRange(location: cursorOffsetInBuffer, length: 0))
                runRenumberPass(in: textView, around: cursorOffsetInBuffer)
                return true
            }

            // Blockquote helper — Spec §9.4.
            let blockquoteOutcome = BlockquoteContinuation.backspaceOutcome(
                buffer: storage.string,
                cursorOffset: cursor
            )
            switch blockquoteOutcome {
            case .standard:
                break
            case .replace(let range, let cursorOffsetInBuffer):
                guard textView.shouldChangeText(in: range, replacementString: "") else {
                    return false
                }
                textView.undoManager?.setActionName("Remove Blockquote")
                storage.replaceCharacters(in: range, with: "")
                textView.didChangeText()
                textView.setSelectedRange(NSRange(location: cursorOffsetInBuffer, length: 0))
                return true
            }

            // Heading helper — Spec §8.2.
            let headingOutcome = HeadingContinuation.backspaceOutcome(
                buffer: storage.string,
                cursorOffset: cursor
            )
            switch headingOutcome {
            case .standard:
                return false
            case .replace(let range, let cursorOffsetInBuffer):
                guard textView.shouldChangeText(in: range, replacementString: "") else {
                    return false
                }
                textView.undoManager?.setActionName("Remove Heading")
                storage.replaceCharacters(in: range, with: "")
                textView.didChangeText()
                textView.setSelectedRange(NSRange(location: cursorOffsetInBuffer, length: 0))
                return true
            }
        }

        public func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard
                let storage = textView.textStorage,
                let replacement = replacementString,
                replacement == " ",
                affectedCharRange.length == 0,
                !textView.hasMarkedText()
            else { return true }

            // Compute line content up to (but not including) the cursor.
            let buffer = storage.string
            let units = Array(buffer.utf16)
            let cursor = affectedCharRange.location
            guard cursor >= 0, cursor <= units.count else { return true }
            var lineStart = cursor
            while lineStart > 0, units[lineStart - 1] != 0x0A {
                lineStart -= 1
            }
            let prefixSlice = Array(units[lineStart..<cursor])
            let prefix: String
            if prefixSlice.isEmpty {
                prefix = ""
            } else {
                prefix = prefixSlice.withUnsafeBufferPointer {
                    String(utf16CodeUnits: $0.baseAddress!, count: $0.count)
                }
            }

            guard
                let expansion = CheckboxAutoExpansion.expansionOnTypingSpace(
                    beforeCursorOnLine: prefix
                )
            else { return true }

            let prefixRange = NSRange(location: lineStart, length: cursor - lineStart)
            guard textView.shouldChangeText(in: prefixRange, replacementString: expansion) else {
                return false
            }
            textView.undoManager?.setActionName("Insert Checkbox")
            storage.replaceCharacters(in: prefixRange, with: expansion)
            textView.didChangeText()
            let newCursor = lineStart + (expansion as NSString).length
            textView.setSelectedRange(NSRange(location: newCursor, length: 0))
            return false
        }

        // MARK: - Click toggle

        func toggleCheckbox(at charIndex: Int) {
            guard
                let textView,
                let storage,
                charIndex >= 0,
                charIndex < storage.length
            else { return }

            var effective = NSRange(location: 0, length: 0)
            let value = storage.attribute(
                .marcdownCheckbox,
                at: charIndex,
                longestEffectiveRange: &effective,
                in: NSRange(location: 0, length: storage.length)
            )
            guard let state = value as? MarcdownCheckboxState, effective.length >= 3 else {
                return
            }

            let middleRange = NSRange(location: effective.location + 1, length: 1)
            let newChar = state == .checked ? " " : "x"
            guard textView.shouldChangeText(in: middleRange, replacementString: newChar) else {
                return
            }
            textView.undoManager?.setActionName("Toggle Task")
            storage.replaceCharacters(in: middleRange, with: newChar)
            textView.didChangeText()
        }

        // MARK: - Formatting commands

        /// Single entry point for every formatting command. Returns `false`
        /// when nothing changed so a ⌘-chord can fall through to AppKit.
        @discardableResult
        func perform(_ command: EditorCommand) -> Bool {
            guard let textView, let storage else { return false }
            if textView.hasMarkedText() { return false }
            let buffer = storage.string
            let selection = textView.selectedRange()
            switch command {
            case .bold:
                return apply(
                    InlineFormat.toggleOutcome(buffer: buffer, selection: selection, delimiter: "**"),
                    undoName: "Bold", in: textView)
            case .italic:
                return apply(
                    InlineFormat.toggleOutcome(buffer: buffer, selection: selection, delimiter: "*"),
                    undoName: "Italic", in: textView)
            case .inlineCode:
                return apply(
                    InlineFormat.toggleOutcome(buffer: buffer, selection: selection, delimiter: "`"),
                    undoName: "Inline Code", in: textView)
            case .strikethrough:
                return apply(
                    InlineFormat.toggleOutcome(buffer: buffer, selection: selection, delimiter: "~~"),
                    undoName: "Strikethrough", in: textView)
            case .highlight:
                return apply(
                    InlineFormat.toggleOutcome(buffer: buffer, selection: selection, delimiter: "=="),
                    undoName: "Highlight", in: textView)
            case .link:
                let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
                let url =
                    InlineFormat.isHTTPURL(clipboard) ? clipboard.trimmingCharacters(in: .whitespacesAndNewlines) : ""
                return apply(
                    InlineFormat.linkOutcome(buffer: buffer, selection: selection, url: url),
                    undoName: "Link", in: textView)
            default:
                return performBlock(command, in: textView)
            }
        }

        private func performBlock(_ command: EditorCommand, in textView: NSTextView) -> Bool {
            guard let storage = textView.textStorage else { return false }
            let buffer = storage.string
            let selection = textView.selectedRange()
            let kind: BlockKind
            let undoName: String
            switch command {
            case .heading(let level):
                kind = level == 0 ? .paragraph : .heading(level)
                undoName = level == 0 ? "Paragraph" : "Heading \(level)"
            case .bulletList:
                kind = .bullet
                undoName = "Bullet List"
            case .orderedList:
                kind = .ordered
                undoName = "Numbered List"
            case .taskList:
                kind = .task
                undoName = "Task List"
            case .quote:
                kind = .quote
                undoName = "Quote"
            case .codeBlock:
                return apply(
                    BlockFormat.codeBlockOutcome(buffer: buffer, selection: selection),
                    undoName: "Code Block", in: textView)
            case .divider:
                return apply(
                    BlockFormat.dividerOutcome(buffer: buffer, selection: selection),
                    undoName: "Divider", in: textView)
            default:
                return false
            }
            let handled = apply(
                BlockFormat.toggleOutcome(buffer: buffer, selection: selection, kind: kind),
                undoName: undoName, in: textView)
            if handled {
                runRenumberPass(in: textView, around: textView.selectedRange().location)
            }
            return handled
        }

        /// The one place edits from pure helpers touch the storage: the
        /// same shouldChange → replace → didChange → select dance every
        /// keystroke handler already does, with a named undo group.
        @discardableResult
        func apply(_ outcome: TextEditOutcome, undoName: String, in textView: NSTextView) -> Bool {
            guard let storage = textView.textStorage else { return false }
            switch outcome {
            case .noOp:
                return false
            case .replace(let range, let replacement, let selection):
                guard textView.shouldChangeText(in: range, replacementString: replacement) else { return false }
                textView.undoManager?.setActionName(undoName)
                storage.replaceCharacters(in: range, with: replacement)
                textView.didChangeText()
                textView.setSelectedRange(selection)
                return true
            }
        }
    }
}

/// `NSTextView` that claims first responder exactly once on first window
/// attach. SwiftUI may recreate the `NSViewRepresentable` mid-session; doing
/// the focus dance unconditionally in `makeNSView` would steal focus from
/// wherever the user was working. Also routes clicks on a checkbox marker
/// to a handler instead of moving the insertion point.
private final class FocusOnAttachTextView: NSTextView {
    private var didClaimFocus = false
    /// Called when the user clicks anywhere inside a `[X]` marker. Argument
    /// is the character index of the click.
    var checkboxClickHandler: ((Int) -> Void)?
    /// Receives ⌘-chords the chord table recognises. Returns whether the
    /// command changed anything; `false` lets AppKit's default run.
    var commandHandler: ((EditorCommand) -> Bool)?
    /// Local monitor that re-invalidates cursor rects whenever modifier flags
    /// change, so the `.pointingHand` cursor appears/disappears over link
    /// labels as the user presses or releases the Command key.
    private var flagsMonitor: Any?

    /// ⌘-keyDowns walk the view tree here before reaching `keyDown`. The
    /// first-responder guard keeps chords from firing while a palette text
    /// field owns the keyboard (DESIGN.md: chrome shortcuts are disabled
    /// while an overlay is open). Chord sets are disjoint from the App's
    /// SwiftUI `.keyboardShortcut` layer, so order between the two never
    /// matters.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self,
            let key = event.charactersIgnoringModifiers,
            let command = EditorCommand.command(forKey: key, keyCode: event.keyCode, modifiers: event.modifierFlags),
            commandHandler?(command) == true
        else { return super.performKeyEquivalent(with: event) }
        return true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !didClaimFocus, let window else { return }
        didClaimFocus = true
        window.makeFirstResponder(self)
        if flagsMonitor == nil {
            flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                guard let self else { return event }
                self.window?.invalidateCursorRects(for: self)
                return event
            }
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
        super.viewWillMove(toWindow: newWindow)
    }

    /// Installs `.pointingHand` cursor rects over every checkbox marker so the
    /// cursor signals interactivity on hover. Called by AppKit whenever the
    /// view is resized/scrolled and explicitly after each restyle pass via
    /// `invalidateCursorRects(for:)`.
    override func resetCursorRects() {
        super.resetCursorRects()
        guard let layoutManager,
            let storage = textStorage
        else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.marcdownCheckbox, in: fullRange, options: []) { value, charRange, _ in
            guard value != nil, charRange.length >= 3 else { return }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
            guard glyphRange.length >= 3 else { return }
            let middleGlyph = glyphRange.location + 1
            var lineFragRange = NSRange(location: 0, length: 0)
            let lineFragRect = layoutManager.lineFragmentRect(forGlyphAt: middleGlyph, effectiveRange: &lineFragRange)
            let middleLocation = layoutManager.location(forGlyphAt: middleGlyph)
            let nextGlyph = middleGlyph + 1
            let advanceWidth: CGFloat
            if nextGlyph < lineFragRange.location + lineFragRange.length {
                let nextLocation = layoutManager.location(forGlyphAt: nextGlyph)
                advanceWidth = max(13, nextLocation.x - middleLocation.x)
            } else {
                advanceWidth = 13
            }
            let rect = NSRect(
                x: textContainerOrigin.x + lineFragRect.minX + middleLocation.x,
                y: textContainerOrigin.y + lineFragRect.minY,
                width: advanceWidth,
                height: lineFragRect.height
            )
            addCursorRect(rect, cursor: .pointingHand)
        }

        // When Cmd is held, treat link labels as clickable: show a
        // `.pointingHand` cursor over each `.marcdownLink` run. The flag-change
        // monitor in `viewDidMoveToWindow` triggers a fresh cursor-rect pass
        // whenever Cmd is pressed or released, so the cursor reflects the
        // current modifier state without requiring a mouse move.
        let cmdHeld = NSEvent.modifierFlags.contains(.command)
        if cmdHeld, let textContainer {
            storage.enumerateAttribute(.marcdownLink, in: fullRange, options: []) { value, charRange, _ in
                guard let dest = value as? String, !dest.isEmpty else { return }
                let glyphRange = layoutManager.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
                guard glyphRange.length > 0 else { return }
                let bounding = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                let rect = bounding.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
                addCursorRect(rect, cursor: .pointingHand)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard
            let layoutManager,
            let textContainer,
            let storage = textStorage
        else {
            super.mouseDown(with: event)
            return
        }

        let pointInView = convert(event.locationInWindow, from: nil)
        let pointInContainer = NSPoint(
            x: pointInView.x - textContainerOrigin.x,
            y: pointInView.y - textContainerOrigin.y
        )
        let glyphIndex = layoutManager.glyphIndex(
            for: pointInContainer,
            in: textContainer
        )
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard charIndex >= 0, charIndex < storage.length else {
            super.mouseDown(with: event)
            return
        }

        // Cmd+click on a styled link label opens the destination URL in the
        // user's default handler, mirroring the convention used by Xcode,
        // Obsidian, and other markdown editors. Falls through to the default
        // text-view behaviour when Cmd is held but the click misses a link.
        if event.modifierFlags.contains(.command) {
            if let destination = storage.attribute(.marcdownLink, at: charIndex, effectiveRange: nil) as? String,
                !destination.isEmpty,
                let url = URL(string: destination)
            {
                NSWorkspace.shared.open(url)
                return
            }
        }

        let value = storage.attribute(.marcdownCheckbox, at: charIndex, effectiveRange: nil)
        if value is MarcdownCheckboxState {
            checkboxClickHandler?(charIndex)
            return
        }

        super.mouseDown(with: event)
    }
}
