import AppKit
import MarcdownCore
import MarcdownEditor
import SwiftUI

struct PanelRootView: View {
    @Bindable var store: NotesStore

    @State private var showSwitcher: Bool = false
    @State private var deleteConfirmationInProgress: Bool = false

    var body: some View {
        ZStack {
            editorLayer
            shortcutLayer
            if showSwitcher {
                switcherOverlay
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        .task {
            await store.bootstrap()
        }
    }

    // MARK: - Editor

    @ViewBuilder
    private var editorLayer: some View {
        if let editor = store.editor {
            VStack(spacing: 0) {
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

            Button("Quick Switcher") { showSwitcher.toggle() }
                .keyboardShortcut("p", modifiers: [.command])

            Button("Delete Current") { confirmDelete() }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])

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
                onDismiss: { showSwitcher = false }
            )
        }
        .transition(.opacity)
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
