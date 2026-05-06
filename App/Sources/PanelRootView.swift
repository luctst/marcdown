import AppKit
import MarcdownCore
import MarcdownEditor
import SwiftUI

/// Single source of truth for which overlay (if any) is currently presented
/// inside the panel. Replaces the previous pair of `@State Bool` flags so the
/// transition palette ↔ switcher is a single state mutation rather than two
/// racing flips. See QA bug #1.
enum ActiveOverlay: Equatable {
    case none
    case palette
    case switcher
}

/// Which toggle the user invoked. Pure input to `nextActiveOverlay`.
enum OverlayToggle: Equatable {
    case palette
    case switcher
}

/// Pure state-machine for overlay transitions. Extracted so the four
/// cross-state combinations (none↔palette↔switcher with proper swap-or-dismiss)
/// can be unit-tested without mounting SwiftUI. Mirrors the behavior used by
/// `PanelRootView.togglePalette()` and `toggleSwitcher()`.
func nextActiveOverlay(from current: ActiveOverlay, toggle: OverlayToggle) -> ActiveOverlay {
    switch toggle {
    case .palette:
        return current == .palette ? .none : .palette
    case .switcher:
        return current == .switcher ? .none : .switcher
    }
}

/// Builds the command palette's action list. Extracted as a free function so
/// the contract "each handler owns its post-action overlay state" can be
/// unit-tested without mounting `PanelRootView` or constructing a `NotesStore`.
///
/// The order returned here is the order users see in the palette and is
/// load-bearing for keyboard navigation tests.
@MainActor
func makePaletteActions(
    setOverlay: @escaping @MainActor (ActiveOverlay) -> Void,
    newNote: @escaping @MainActor () -> Void,
    triggerFind: @escaping @MainActor () -> Void,
    duplicate: @escaping @MainActor () -> Void,
    delete: @escaping @MainActor () -> Void,
    prev: @escaping @MainActor () -> Void,
    next: @escaping @MainActor () -> Void
) -> [PaletteAction] {
    [
        PaletteAction(id: "new-note", title: "New Note", icon: "plus", shortcutLabel: "⌘N") {
            setOverlay(.none)
            newNote()
        },
        PaletteAction(id: "browse-notes", title: "Browse Notes", icon: "list.bullet", shortcutLabel: "⌘P") {
            withAnimation(.easeOut(duration: 0.15)) { setOverlay(.switcher) }
        },
        PaletteAction(id: "find", title: "Find in Note", icon: "magnifyingglass", shortcutLabel: "⌘F") {
            setOverlay(.none)
            // Direct-dispatch to the editor's NSTextView instead of walking
            // the responder chain via NSApp.sendAction(... to: nil ...): after
            // the SwiftUI overlay tears down, the first responder is the
            // hosting view, not the editor, so a chain walk never reaches a
            // handler. See QA bugs #5 and the follow-up fix.
            triggerFind()
        },
        PaletteAction(id: "duplicate", title: "Duplicate Note", icon: "doc.on.doc", shortcutLabel: "⌘D") {
            setOverlay(.none)
            duplicate()
        },
        PaletteAction(id: "delete", title: "Delete Note", icon: "trash", shortcutLabel: "⇧⌘⌫") {
            setOverlay(.none)
            delete()
        },
        PaletteAction(id: "prev-note", title: "Previous Note", icon: "chevron.left", shortcutLabel: "⇧⌘[") {
            setOverlay(.none)
            prev()
        },
        PaletteAction(id: "next-note", title: "Next Note", icon: "chevron.right", shortcutLabel: "⇧⌘]") {
            setOverlay(.none)
            next()
        },
    ]
}

struct PanelRootView: View {
    @Bindable var store: NotesStore

    @State private var activeOverlay: ActiveOverlay = .none
    @State private var tooltips = TooltipModel()

    private var currentTitle: String {
        guard let editor = store.editor else { return "Marcdown" }
        return Note.extractTitle(from: editor.text)
            ?? store.currentNote?.deletingPathExtension().lastPathComponent
            ?? "Untitled"
    }

    var body: some View {
        ZStack {
            editorLayer
            shortcutLayer
            if activeOverlay == .switcher {
                switcherOverlay
            }
            if activeOverlay == .palette {
                commandPaletteOverlay
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        .ignoresSafeArea(.all, edges: .top)
        .coordinateSpace(name: PanelCoordinateSpace.name)
        .environment(tooltips)
        .background(
            EscapeKeyMonitor(isActive: activeOverlay != .none) {
                dismissActiveOverlay()
            }
        )
        .task {
            await store.bootstrap()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
            guard notification.object as? MarcdownPanel != nil else { return }
            tooltips.hideAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMoveNotification)) { notification in
            guard notification.object as? MarcdownPanel != nil else { return }
            tooltips.hideAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            tooltips.hideAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .marcdownPanelDidHide)) { _ in
            // The SwiftUI hosting view persists across hide/show, so overlay
            // state would otherwise survive a panel toggle. Reset on hide so
            // the panel always reopens to a clean editor view.
            activeOverlay = .none
        }
    }

    // MARK: - Editor

    @ViewBuilder
    private var editorLayer: some View {
        if let editor = store.editor {
            VStack(spacing: 0) {
                HeaderBar(
                    title: currentTitle,
                    onCommandPalette: { togglePalette() },
                    onQuickSwitcher: { toggleSwitcher() },
                    onNewNote: { Task { await store.newNote() } }
                )
                EditorHost(editor: editor)
                if let err = editor.lastSaveError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.regularMaterial)
                }
                FooterBar(characterCount: editor.text.count)
            }
        } else {
            VStack(spacing: 12) {
                Text("No notes yet")
                    .font(.headline)
                Text("Press ⌘N to create one.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Hidden shortcut buttons

    private var shortcutLayer: some View {
        // Note: ⌘K and ⌘P are intentionally never disabled — they must stay
        // live so the user can press them while an overlay is open to either
        // dismiss it (same key twice) or swap to the other overlay.
        VStack {
            Button("New Note") { Task { await store.newNote() } }
                .keyboardShortcut("n", modifiers: [.command])
                .disabled(activeOverlay != .none)

            Button("Quick Switcher") { toggleSwitcher() }
                .keyboardShortcut("p", modifiers: [.command])

            Button("Command Palette") { togglePalette() }
                .keyboardShortcut("k", modifiers: [.command])

            Button("Delete Current") { deleteCurrentNote() }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(activeOverlay != .none)

            Button("Duplicate Note") { Task { await store.duplicateCurrent() } }
                .keyboardShortcut("d", modifiers: [.command])
                .disabled(activeOverlay != .none)

            Button("Find") { triggerFind() }
                .keyboardShortcut("f", modifiers: [.command])
                .disabled(activeOverlay != .none)

            Button("Previous Note") { store.prev() }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled(activeOverlay != .none)

            Button("Next Note") { store.next() }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled(activeOverlay != .none)

            ForEach(1..<10, id: \.self) { n in
                Button("Jump to Recent \(n)") { store.jumpToRecent(n) }
                    .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: [.command])
                    .disabled(activeOverlay != .none)
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private var switcherOverlay: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { activeOverlay = .none } }
            QuickSwitcher(
                notes: store.notes,
                onOpen: { url in
                    store.open(url)
                    activeOverlay = .none
                },
                onDismiss: { activeOverlay = .none },
                currentNote: store.currentNote,
                isBootstrapping: store.isBootstrapping
            )
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
        }
        .transition(.opacity)
    }

    private var commandPaletteOverlay: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { activeOverlay = .none } }
            CommandPalette(
                actions: paletteActions,
                onDismiss: { activeOverlay = .none }
            )
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
        }
        .transition(.opacity)
    }

    private var paletteActions: [PaletteAction] {
        makePaletteActions(
            setOverlay: { activeOverlay = $0 },
            newNote: { Task { await store.newNote() } },
            triggerFind: { triggerFind() },
            duplicate: { Task { await store.duplicateCurrent() } },
            delete: { deleteCurrentNote() },
            prev: { store.prev() },
            next: { store.next() }
        )
    }

    // MARK: - Overlay state transitions

    private func togglePalette() {
        withAnimation(.easeOut(duration: 0.15)) {
            activeOverlay = nextActiveOverlay(from: activeOverlay, toggle: .palette)
        }
    }

    private func toggleSwitcher() {
        withAnimation(.easeOut(duration: 0.15)) {
            activeOverlay = nextActiveOverlay(from: activeOverlay, toggle: .switcher)
        }
    }

    private func dismissActiveOverlay() {
        withAnimation(.easeOut(duration: 0.15)) { activeOverlay = .none }
    }

    private func triggerFind() {
        let menuItem = NSMenuItem()
        menuItem.tag = Int(NSTextFinder.Action.showFindInterface.rawValue)
        guard
            let panel = NSApp.windows.first(where: { $0 is MarcdownPanel }),
            let textView = panel.contentView?.firstDescendant(ofType: NSTextView.self)
        else { return }
        textView.performFindPanelAction(menuItem)
    }

    private func deleteCurrentNote() {
        guard store.currentNote != nil else { return }
        Task { await store.deleteCurrent() }
    }
}

/// Binds to a specific `NoteViewModel` instance so SwiftUI correctly reinstalls
/// the `NoteEditorView` whenever the store swaps in a new view model.
private struct EditorHost: View {
    @Bindable var editor: NoteViewModel

    var body: some View {
        NoteEditorView(text: $editor.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(editor.url)
    }
}

/// Local AppKit key event monitor that intercepts Esc whenever an overlay is
/// active and dismisses the overlay, preventing the keystroke from reaching
/// `MarcdownPanel.cancelOperation` (which would hide the entire panel). See
/// QA bug #2.
private struct EscapeKeyMonitor: NSViewRepresentable {
    let isActive: Bool
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(isActive: isActive, onEscape: onEscape)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    @MainActor
    final class Coordinator {
        private var monitor: Any?
        private var onEscape: (() -> Void)?

        func update(isActive: Bool, onEscape: @escaping () -> Void) {
            self.onEscape = onEscape
            if isActive {
                installIfNeeded()
            } else {
                removeMonitor()
            }
        }

        private func installIfNeeded() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53 else { return event }  // 53 == Escape
                self?.onEscape?()
                return nil
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
