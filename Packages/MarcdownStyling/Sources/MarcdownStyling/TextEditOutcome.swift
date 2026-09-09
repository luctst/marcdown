import Foundation

/// Result of any editing command. Shared by inline/block formatting,
/// selection indent, and paste helpers so the editor applies every edit with
/// one code path. `selection` is expressed in the buffer *after* the edit.
public enum TextEditOutcome: Sendable, Equatable {
    case noOp
    case replace(range: NSRange, replacement: String, selection: NSRange)
}
