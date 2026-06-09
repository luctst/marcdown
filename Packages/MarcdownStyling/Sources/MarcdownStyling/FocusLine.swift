import Foundation

/// A single focused line in the editor — the line containing the cursor
/// (or one of the lines spanned by the active selection).
///
/// When passed to `MarkdownStyler.restyle(storage:source:focusLine:)`, the
/// styler removes `.marcdownConcealed` from any character in the line and
/// repaints those characters with the dim theme color (Spec §3 / acceptance
/// #1). It also strips `.marcdownListMarker` / `.marcdownCheckbox` tags on
/// the focused line so the layout-manager overlays defer to the raw text.
public struct FocusLine: Sendable, Equatable {
    /// UTF-16 offset of the start of the focused line in the source string.
    public let lineStart: Int
    /// UTF-16 length of the line content, excluding any trailing `\n`.
    public let lineLength: Int

    public init(lineStart: Int, lineLength: Int) {
        self.lineStart = lineStart
        self.lineLength = lineLength
    }
}
