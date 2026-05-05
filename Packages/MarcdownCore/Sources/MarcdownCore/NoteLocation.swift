import Foundation

/// Hardcoded note locations for this slice. A folder picker replaces the
/// `defaultDirectory` constant in a later slice.
public enum NoteLocation {
    /// `~/marcdown/`
    public static var defaultDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("marcdown", isDirectory: true)
    }

    /// `~/marcdown/scratch.md`
    public static var scratchNote: URL {
        defaultDirectory.appendingPathComponent("scratch.md", isDirectory: false)
    }

    public static let scratchPlaceholder: String = """
        # Welcome to Marcdown

        This is your scratch note. Anything you type here is saved automatically.

        Press the global hotkey to toggle this panel. Press Esc to hide it.
        """
}
