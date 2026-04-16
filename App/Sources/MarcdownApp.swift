import SwiftUI

@main
struct MarcdownApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No WindowGroup: the panel is owned by AppDelegate. Settings is the
        // only standard SwiftUI scene we expose.
        Settings {
            SettingsView()
        }
    }
}
