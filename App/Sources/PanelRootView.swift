import AppKit
import MarcdownCore
import MarcdownEditor
import SwiftUI

struct PanelRootView: View {
    @Bindable var store: NotesStore

    @State private var showSwitcher: Bool = false
    @State private var showCommandPalette: Bool = false
    @State private var deleteConfirmationInProgress: Bool = false
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
            if showSwitcher {
                switcherOverlay
            }
            if showCommandPalette {
                commandPaletteOverlay
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        .ignoresSafeArea(.all, edges: .top)
        .coordinateSpace(name: PanelCoordinateSpace.name)
        .environment(tooltips)
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
    }

    // MARK: - Editor

    @ViewBuilder
    private var editorLayer: some View {
        if let editor = store.editor {
            VStack(spacing: 0) {
                HeaderBar(
                    title: currentTitle,
                    onCommandPalette: {
                        showSwitcher = false
                        withAnimation(.easeOut(duration: 0.15)) { showCommandPalette.toggle() }
                    },
                    onQuickSwitcher: {
                        showCommandPalette = false
                        withAnimation(.easeOut(duration: 0.15)) { showSwitcher.toggle() }
                    },
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
        VStack {
            Button("New Note") { Task { await store.newNote() } }
                .keyboardShortcut("n", modifiers: [.command])

            Button("Quick Switcher") {
                showCommandPalette = false
                withAnimation(.easeOut(duration: 0.15)) { showSwitcher.toggle() }
            }
            .keyboardShortcut("p", modifiers: [.command])

            Button("Command Palette") {
                showSwitcher = false
                withAnimation(.easeOut(duration: 0.15)) { showCommandPalette.toggle() }
            }
            .keyboardShortcut("k", modifiers: [.command])

            Button("Delete Current") { confirmDelete() }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])

            Button("Duplicate Note") { Task { await store.duplicateCurrent() } }
                .keyboardShortcut("d", modifiers: [.command])

            Button("Find") { triggerFind() }
                .keyboardShortcut("f", modifiers: [.command])

            Button("Previous Note") { store.prev() }
                .keyboardShortcut("[", modifiers: [.command, .shift])

            Button("Next Note") { store.next() }
                .keyboardShortcut("]", modifiers: [.command, .shift])

            ForEach(1 ..< 10, id: \.self) { n in
                Button("Jump to Recent \(n)") { store.jumpToRecent(n) }
                    .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: [.command])
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
                .onTapGesture { showSwitcher = false }
            QuickSwitcher(
                notes: store.notes,
                onOpen: { url in
                    store.open(url)
                    showSwitcher = false
                },
                onDismiss: { showSwitcher = false },
                currentNote: store.currentNote
            )
        }
        .transition(.opacity)
    }

    private var commandPaletteOverlay: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { showCommandPalette = false } }
            CommandPalette(
                actions: paletteActions,
                onDismiss: { showCommandPalette = false }
            )
        }
        .transition(.opacity)
    }

    private var paletteActions: [PaletteAction] {
        [
            PaletteAction(id: "new-note", title: "New Note", icon: "plus", shortcutLabel: "⌘N") {
                showCommandPalette = false
                Task { await store.newNote() }
            },
            PaletteAction(id: "browse-notes", title: "Browse Notes", icon: "list.bullet", shortcutLabel: "⌘P") {
                showCommandPalette = false
                showSwitcher = true
            },
            PaletteAction(id: "find", title: "Find in Note", icon: "magnifyingglass", shortcutLabel: "⌘F") {
                showCommandPalette = false
                triggerFind()
            },
            PaletteAction(id: "duplicate", title: "Duplicate Note", icon: "doc.on.doc", shortcutLabel: "⌘D") {
                showCommandPalette = false
                Task { await store.duplicateCurrent() }
            },
            PaletteAction(id: "delete", title: "Delete Note", icon: "trash", shortcutLabel: "⇧⌘⌫") {
                showCommandPalette = false
                confirmDelete()
            },
            PaletteAction(id: "prev-note", title: "Previous Note", icon: "chevron.left", shortcutLabel: "⇧⌘[") {
                showCommandPalette = false
                store.prev()
            },
            PaletteAction(id: "next-note", title: "Next Note", icon: "chevron.right", shortcutLabel: "⇧⌘]") {
                showCommandPalette = false
                store.next()
            },
        ]
    }

    private func triggerFind() {
        let menuItem = NSMenuItem()
        menuItem.tag = Int(NSTextFinder.Action.showFindInterface.rawValue)
        NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: menuItem)
    }

    private func confirmDelete() {
        guard !deleteConfirmationInProgress, store.currentNote != nil else { return }
        deleteConfirmationInProgress = true
        defer { deleteConfirmationInProgress = false }

        let alert = NSAlert()
        alert.messageText = "Move note to Trash?"
        alert.informativeText = "You can restore it from the Finder Trash."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            Task { await store.deleteCurrent() }
        }
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
