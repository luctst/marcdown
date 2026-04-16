import AppKit
import KeyboardShortcuts
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: PanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Background-only app: even though LSUIElement hides us from the Dock,
        // an explicit accessory policy keeps activation behavior predictable
        // when toggling panels and Settings.
        NSApp.setActivationPolicy(.accessory)

        let controller = PanelController()
        self.panelController = controller

        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak controller] in
            controller?.toggle()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        panelController = nil
    }
}
