import Foundation

/// State of a complete checkbox marker.
public enum MarcdownCheckboxState: Sendable, Equatable {
    case unchecked
    case checked
}

/// Classification of a single line for checkbox / task-list purposes.
///
/// `CheckboxLineScanner` is the single source of truth: both the styler and
/// the editor (auto-expand, Enter handling) consult it instead of doing their
/// own ad-hoc regex scans. This avoids the v1 "AST + regex" seam bugs.
public enum CheckboxLineShape: Sendable, Equatable {
    /// Not a checkbox line at all.
    case none

    /// Partially-typed shape (`-`, `- `, `- [`, `- [ `, `- [x`, `- [X`, `- []`).
    ///
    /// - `indentLength`: count of leading whitespace UTF-16 units.
    /// - `concealLength`: number of UTF-16 units after the indent that the
    ///   editor should conceal (i.e. the bullet/marker fragment the user has
    ///   typed so far).
    case partial(indentLength: Int, concealLength: Int)

    /// Complete `- [ ]`, `- [x]`, or `- [X]`.
    ///
    /// - `indentLength`: count of leading whitespace UTF-16 units.
    /// - `bracketLocation`: UTF-16 offset of `[` from the start of the line.
    /// - `state`: checked / unchecked.
    case complete(indentLength: Int, bracketLocation: Int, state: MarcdownCheckboxState)
}

/// Pure helper. AppKit-free.
public enum CheckboxLineScanner {
    /// Classify `line` (a single line, no trailing newline) into a
    /// `CheckboxLineShape`.
    public static func scan(line: String) -> CheckboxLineShape {
        // Operate on UTF-16 because the styler and editor work in UTF-16
        // offsets (NSRange / NSTextStorage).
        let units = Array(line.utf16)
        let length = units.count

        // 1. Skip leading whitespace (space / tab) → indent length.
        var i = 0
        while i < length, units[i] == 0x20 || units[i] == 0x09 {
            i += 1
        }
        let indentLength = i

        // After indent, require `-` (0x2D).
        guard i < length else { return .none }
        guard units[i] == 0x2D else { return .none }
        i += 1

        // `- ` (dash with no following content).
        if i == length {
            // `-` alone: partial with conceal length 1 (just the dash).
            return .partial(indentLength: indentLength, concealLength: 1)
        }

        // After `-`, require exactly one space or tab.
        guard units[i] == 0x20 || units[i] == 0x09 else { return .none }
        i += 1

        // After `- `:
        if i == length {
            // `- ` alone.
            return .partial(indentLength: indentLength, concealLength: 2)
        }

        // The next char after `- ` MUST be `[` (0x5B) — otherwise plain unordered list.
        guard units[i] == 0x5B else { return .none }
        let bracketLocation = i
        i += 1

        // After `[`, examine what follows.
        if i == length {
            // `- [` only — partial up to and including `[`.
            return .partial(
                indentLength: indentLength,
                concealLength: bracketLocation + 1 - indentLength
            )
        }

        let inner = units[i]

        // `- []` — empty brackets (`]` is 0x5D), treat as partial.
        if inner == 0x5D {
            return .partial(
                indentLength: indentLength,
                concealLength: bracketLocation + 2 - indentLength
            )
        }

        // Inner must be space (0x20), 'x' (0x78), or 'X' (0x58) to potentially be complete.
        let isUnchecked = (inner == 0x20)
        let isChecked = (inner == 0x78 || inner == 0x58)

        guard isUnchecked || isChecked else {
            return .none
        }

        // Need a `]` immediately after the inner char to be complete.
        if i + 1 >= length {
            // `- [ ` / `- [x` / `- [X` — partial through inner char.
            return .partial(
                indentLength: indentLength,
                concealLength: bracketLocation + 2 - indentLength
            )
        }

        // `]` is 0x5D.
        guard units[i + 1] == 0x5D else {
            // Something after the inner char that isn't `]`. Not a checkbox.
            return .none
        }

        let state: MarcdownCheckboxState = isChecked ? .checked : .unchecked
        return .complete(
            indentLength: indentLength,
            bracketLocation: bracketLocation,
            state: state
        )
    }
}
