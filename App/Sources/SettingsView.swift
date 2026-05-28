import KeyboardShortcuts
import MarcdownLaunchKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
            ShortcutsTab()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
        }
        .frame(width: 420, height: 220)
    }
}

private struct GeneralTab: View {
    @Environment(LaunchAtLoginController.self) private var launchController

    var body: some View {
        Form {
            Toggle("Launch at Login", isOn: Binding(
                get: { launchController.state == .enabled },
                set: { launchController.setEnabled($0) }
            ))
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { launchController.refresh() }
    }
}

private struct ShortcutsTab: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Toggle Marcdown panel:", name: .togglePanel)
        }
        .formStyle(.grouped)
        .padding()
    }
}
