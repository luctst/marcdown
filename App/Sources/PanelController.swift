import AppKit
import SwiftUI

/// Owns the lifecycle of the floating editor panel.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let panel: MarcdownPanel
    private let store: NotesStore

    override init() {
        let store = NotesStore()
        self.store = store

        let initialFrame = NSRect(x: 0, y: 0, width: 720, height: 520)
        let panel = MarcdownPanel(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .hudWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        let hosting = NSHostingView(rootView: PanelRootView(store: store))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = hosting

        self.panel = panel
        super.init()

        panel.delegate = self
        panel.center()
    }

    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        recenterOnActiveScreen()
        // We're an .accessory app — to take key without bouncing focus to
        // another window, activate ignoring other apps and order front as key.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func recenterOnActiveScreen() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        var frame = panel.frame
        frame.origin.x = visible.midX - frame.width / 2
        frame.origin.y = visible.midY - frame.height / 2
        panel.setFrame(frame, display: false)
    }

    // MARK: NSWindowDelegate

    nonisolated func windowDidResignKey(_ notification: Notification) {
        MainActor.assumeIsolated {
            self.hide()
        }
    }
}

/// `NSPanel` subclass that can become key (so the editor receives keystrokes)
/// and hides on Esc.
final class MarcdownPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        self.isFloatingPanel = true
        self.level = .floating
        self.hidesOnDeactivate = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.isMovableByWindowBackground = true
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.title = "Marcdown"
        self.isReleasedWhenClosed = false
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true
    }

    override func cancelOperation(_ sender: Any?) {
        // Esc — hide rather than close so we keep state in memory.
        orderOut(nil)
    }
}
