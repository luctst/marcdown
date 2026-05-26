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

        Press **⌘⇧Space** anywhere to bring this window back.

        Your notes are saved as plain `.md` files in `~/marcdown`.

        Edit this note, delete it, or start a new one — it's yours.
        """
}
