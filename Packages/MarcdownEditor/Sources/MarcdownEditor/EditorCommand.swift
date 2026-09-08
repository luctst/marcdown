import AppKit

/// Every formatting command the editor understands. Dispatched from three
/// places with one implementation (`Coordinator.perform`): ⌘-chords caught
/// in the text view, the ⌘K palette's Markdown rows, and the `/` menu.
public enum EditorCommand: Hashable, Sendable {
    case bold
    case italic
    case inlineCode
    case strikethrough
    case highlight
    case link
    /// 1…6 set a heading level; 0 turns the line back into a paragraph.
    case heading(Int)
    case bulletList
    case orderedList
    case taskList
    case quote
    case codeBlock
    case divider

    /// Chord table. Letters match the layout's character (lower-cased so
    /// Shift/Caps Lock don't matter); heading digits match the physical key
    /// so AZERTY/QWERTZ layouts, where digits need Shift, still work.
    /// Modifiers must match exactly — ⌥⌘B is not Bold.
    static func command(forKey key: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> EditorCommand? {
        let mods = modifiers.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        let command: NSEvent.ModifierFlags = [.command]
        let shiftCommand: NSEvent.ModifierFlags = [.command, .shift]
        let optionCommand: NSEvent.ModifierFlags = [.command, .option]

        if mods == optionCommand, let level = headingLevel(forKeyCode: keyCode) {
            return .heading(level)
        }
        switch (key.lowercased(), mods) {
        case ("b", command): return .bold
        case ("i", command): return .italic
        case ("e", command): return .inlineCode
        case ("x", shiftCommand): return .strikethrough
        case ("h", shiftCommand): return .highlight
        case ("k", shiftCommand): return .link
        case ("l", shiftCommand): return .bulletList
        case ("n", shiftCommand): return .orderedList
        case ("t", shiftCommand): return .taskList
        case ("b", shiftCommand): return .quote
        default: return nil
        }
    }

    /// kVK_ANSI_0…6 virtual key codes.
    private static func headingLevel(forKeyCode code: UInt16) -> Int? {
        switch code {
        case 29: return 0
        case 18: return 1
        case 19: return 2
        case 20: return 3
        case 21: return 4
        case 23: return 5
        case 22: return 6
        default: return nil
        }
    }
}
