import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Toggles the floating Marcdown panel. Default chord: ⌘⇧Space.
    static let togglePanel = Self(
        "togglePanel",
        default: .init(.space, modifiers: [.command, .shift])
    )
}
