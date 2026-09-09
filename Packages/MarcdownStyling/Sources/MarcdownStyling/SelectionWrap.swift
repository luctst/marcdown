import Foundation

/// Typing a markdown delimiter with text selected wraps the text instead of
/// replacing it (Bear/Notion behaviour). Pure, AppKit-free.
public enum SelectionWrap {
    public static func outcome(buffer: String, selection: NSRange, typed: String) -> TextEditOutcome {
        guard selection.length > 0 else { return .noOp }
        let closer: String
        switch typed {
        case "*", "_", "`", "~", "=", "\"": closer = typed
        case "[": closer = "]"
        case "(": closer = ")"
        default: return .noOp
        }
        let units = Array(buffer.utf16)
        guard selection.location >= 0, selection.location + selection.length <= units.count else { return .noOp }
        let inner = String(
            decoding: units[selection.location..<(selection.location + selection.length)], as: UTF16.self)
        return .replace(
            range: selection,
            replacement: typed + inner + closer,
            selection: NSRange(location: selection.location + 1, length: selection.length)
        )
    }
}
