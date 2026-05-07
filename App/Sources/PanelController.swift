import AppKit
import SwiftUI

extension Notification.Name {
    /// Posted by `PanelController` immediately after the panel is ordered out.
    /// `PanelRootView` listens for this to reset transient overlay state, since
    /// the SwiftUI hosting view persists across hide/show cycles.
    static let marcdownPanelDidHide = Notification.Name("MarcdownPanelDidHide")
}

/// Hardcoded size constraints for the floating editor panel.
/// Per PM scope, these are intentionally not user-configurable.
enum PanelSizeConstraints {
    static let maxWidth: CGFloat = 720
    static let minWidth: CGFloat = 400
    static let minHeight: CGFloat = 300
    /// Margin reserved on small screens so the panel never spans edge-to-edge.
    static let screenMargin: CGFloat = 16
}

/// Pure helper: clamps the desired max width to fit the current screen.
///
/// On screens narrower than `PanelSizeConstraints.maxWidth + screenMargin`,
/// the result shrinks to `screenWidth - screenMargin`. The result is also
/// floored at `PanelSizeConstraints.minWidth` so we never produce a max
/// smaller than the min (which would be an invalid AppKit configuration).
func computeMaxWidth(screenWidth: CGFloat) -> CGFloat {
    let candidate = min(PanelSizeConstraints.maxWidth, screenWidth - PanelSizeConstraints.screenMargin)
    return max(candidate, PanelSizeConstraints.minWidth)
}

/// Pure helper: returns the saved origin if it lies within any of the provided
/// screen visible frames, otherwise nil. The caller should fall back to
/// centering when this returns nil.
///
/// Kept top-level (not a method) so it can be unit-tested without spinning up
/// AppKit / NSScreen — same pattern as `computeMaxWidth`.
func resolvePanelOrigin(saved: CGPoint?, screenVisibleFrames: [CGRect]) -> CGPoint? {
    guard let saved else { return nil }
    guard !screenVisibleFrames.isEmpty else { return nil }
    if screenVisibleFrames.contains(where: { $0.contains(saved) }) {
        return saved
    }
    return nil
}

/// Owns the lifecycle of the floating editor panel.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private static let originKey = "dev.marcdown.panelOrigin"

    private let panel: MarcdownPanel
    private let store: NotesStore
    /// The app that was frontmost the moment we activated. Restored when the
    /// user explicitly dismisses the panel (Esc / hotkey toggle) so focus
    /// returns to where they came from, instead of stranding them on the
    /// desktop.
    private var previouslyActiveApp: NSRunningApplication?

    override init() {
        let store = NotesStore()
        self.store = store

        let initialFrame = NSRect(
            x: 0,
            y: 0,
            width: PanelSizeConstraints.maxWidth,
            height: 520
        )
        let panel = MarcdownPanel(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .hudWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        let hosting = NSHostingView(rootView: PanelRootView(store: store))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = hosting

        // minSize is static and AppKit-native — set it once.
        panel.minSize = NSSize(
            width: PanelSizeConstraints.minWidth,
            height: PanelSizeConstraints.minHeight
        )

        self.panel = panel
        super.init()

        panel.delegate = self
        updateMaxSizeForCurrentScreen()
        restoreOrPlace()
    }

    func toggle() {
        if panel.isVisible {
            hide(restoreFocus: true)
        } else {
            show()
        }
    }

    func show() {
        updateMaxSizeForCurrentScreen()
        restoreOrPlace()
        // Snapshot the frontmost app so we can hand focus back when the user
        // dismisses the panel. Skip if it's us — would cause an empty desktop
        // on hide.
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost != .current {
            previouslyActiveApp = frontmost
        }
        // We're an .accessory app — to take key without bouncing focus to
        // another window, activate ignoring other apps and order front as key.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    /// Hides the panel. When `restoreFocus` is true, brings the previously
    /// active app back to the front; when false, leaves focus alone (the user
    /// just clicked another app, so macOS has already moved focus there).
    func hide(restoreFocus: Bool) {
        // Capture and clear up-front: ordering out triggers windowDidResignKey
        // re-entrantly, which calls hide(restoreFocus: false). If we cleared
        // after orderOut, that re-entry would observe a stale value.
        let target = restoreFocus ? previouslyActiveApp : nil
        previouslyActiveApp = nil
        panel.orderOut(nil)
        NotificationCenter.default.post(name: .marcdownPanelDidHide, object: panel)
        if let target, !target.isTerminated {
            target.activate()
        }
    }

    private func recenterOnActiveScreen() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        var frame = panel.frame
        frame.origin.x = visible.midX - frame.width / 2
        frame.origin.y = visible.midY - frame.height / 2
        panel.setFrame(frame, display: false)
    }

    private func saveOrigin() {
        let o = panel.frame.origin
        UserDefaults.standard.set([o.x, o.y], forKey: Self.originKey)
    }

    /// Restore last-saved origin if it still lands on a connected screen;
    /// otherwise fall back to centering. Size is intentionally not persisted.
    private func restoreOrPlace() {
        let saved: CGPoint?
        if let raw = UserDefaults.standard.array(forKey: Self.originKey) as? [CGFloat],
            raw.count == 2
        {
            saved = CGPoint(x: raw[0], y: raw[1])
        } else {
            saved = nil
        }
        let frames = NSScreen.screens.map { $0.visibleFrame }
        if let origin = resolvePanelOrigin(saved: saved, screenVisibleFrames: frames) {
            let frame = NSRect(origin: origin, size: panel.frame.size)
            panel.setFrame(frame, display: false)
        } else {
            recenterOnActiveScreen()
        }
    }

    /// `NSWindow.maxSize` is a static cap — it must be refreshed whenever
    /// the active screen changes, since the small-screen clamp depends on it.
    private func updateMaxSizeForCurrentScreen() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let screenWidth = screen?.visibleFrame.width ?? PanelSizeConstraints.maxWidth
        panel.maxSize = NSSize(
            width: computeMaxWidth(screenWidth: screenWidth),
            height: CGFloat.greatestFiniteMagnitude
        )
    }

    // MARK: NSWindowDelegate

    nonisolated func windowDidResignKey(_ notification: Notification) {
        MainActor.assumeIsolated {
            // The user already moved to another app — don't yank them back.
            self.hide(restoreFocus: false)
        }
    }

    nonisolated func windowDidMove(_ notification: Notification) {
        MainActor.assumeIsolated { self.saveOrigin() }
    }

    /// Called by AppKit on every tick of the user's live-resize gesture.
    /// We clamp here instead of relying on `maxSize`/`minSize` so the
    /// constraint is enforced against the screen the panel is *currently* on
    /// — `maxSize` can be stale if the panel was dragged to a different
    /// display since it was last refreshed.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let screen = sender.screen ?? NSScreen.main ?? NSScreen.screens.first
        let screenWidth = screen?.visibleFrame.width ?? PanelSizeConstraints.maxWidth
        let allowedMaxWidth = computeMaxWidth(screenWidth: screenWidth)
        let clampedWidth = min(max(frameSize.width, PanelSizeConstraints.minWidth), allowedMaxWidth)
        let clampedHeight = max(frameSize.height, PanelSizeConstraints.minHeight)
        return NSSize(width: clampedWidth, height: clampedHeight)
    }

    /// Refresh the cached `maxSize` whenever the panel moves between displays
    /// so subsequent reopen / programmatic resizes use the correct cap.
    func windowDidChangeScreen(_ notification: Notification) {
        updateMaxSizeForCurrentScreen()
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
        // Esc — hide rather than close so we keep state in memory. Route
        // through the controller so focus returns to the prior app.
        if let controller = delegate as? PanelController {
            controller.hide(restoreFocus: true)
        } else {
            orderOut(nil)
        }
    }
}
