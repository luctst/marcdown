import AppKit
import KeyboardShortcuts
import MarcdownCore
import MarcdownLaunchKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let launchAtLoginController = LaunchAtLoginController()
    private var panelController: PanelController?
    // Retained for the app's lifetime — `NSStatusBar` does not keep a strong
    // reference to the status item, so dropping this property would remove
    // the icon from the menu bar.
    private var statusItem: NSStatusItem?

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

        installStatusItem()

        let defaults = UserDefaults.standard
        if isFirstLaunch(defaults: defaults) {
            markLaunched(defaults: defaults)
            controller.show()
            launchAtLoginController.registerOnFirstLaunchSilently()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        panelController = nil
        statusItem = nil
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // SF Symbols default to a filled black render, which disappears against
        // the dark menu bar. Marking the image as a template lets AppKit tint it
        // to match the current menu bar appearance and highlight states.
        let icon = NSImage(systemSymbolName: "pencil", accessibilityDescription: "Marcdown")
        icon?.isTemplate = true
        item.button?.image = icon

        let menu = NSMenu()

        // The shortcut is shown as a title hint rather than a real keyEquivalent:
        // the global `KeyboardShortcuts` hotkey owns ⌘⇧Space, and we don't want
        // the menu item competing for that chord when the status menu is open.
        let openItem = NSMenuItem(
            title: "Open Marcdown  ⌘⇧Space",
            action: #selector(openMarcdown),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Marcdown",
            action: #selector(quitMarcdown),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        self.statusItem = item
    }

    @objc private func openMarcdown() {
        panelController?.show()
    }

    @objc private func quitMarcdown() {
        NSApp.terminate(nil)
    }
}
