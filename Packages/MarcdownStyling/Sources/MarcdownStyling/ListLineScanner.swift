import Foundation

/// Classification of a single line for plain list-marker (bullet / ordered)
/// purposes.
///
/// Mirrors the shape of `CheckboxLineScanner` so the styler and the editor
/// helpers consume both scanners with the same pattern. Checkbox lines
/// (`- [ ] task`) are NOT a list line from this scanner's perspective: they
/// return `.none` and remain owned by `CheckboxLineScanner`.
public enum ListLineShape: Sendable, Equatable {
    /// Not a plain list line.
    case none

    /// Partially-typed shape (`-`, `- `, `1`, `1.`, `1. `, etc.) — the user
    /// has begun a marker but has not yet typed any body content.
    ///
    /// - `indentLength`: count of leading whitespace UTF-16 units.
    /// - `markerLength`: number of UTF-16 units from the end of the indent
    ///   through whatever fragment of the marker the user has typed so far
    ///   (inclusive of any trailing space).
    case partial(indentLength: Int, markerLength: Int)

    /// A complete `<marker> <body>` line.
    ///
    /// - `indentLength`: count of leading whitespace UTF-16 units.
    /// - `markerLength`: number of UTF-16 units from the end of the indent
    ///   through the single trailing space/tab (inclusive). For a bullet
    ///   this is always 2 (`- `); for ordered it is `digits + 1 (.) + 1 ( )`.
    /// - `kind`: bullet vs ordered (with the parsed integer).
    case complete(indentLength: Int, markerLength: Int, kind: MarcdownListMarkerKind)
}

/// Pure helper. AppKit-free.
public enum ListLineScanner {
    /// Classify `line` (a single line, no trailing newline) into a
    /// `ListLineShape`.
    public static func scan(line: String) -> ListLineShape {
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

        guard i < length else { return .none }

        let first = units[i]

        // Bullet path: `-` (0x2D), `*` (0x2A), `+` (0x2B).
        if first == 0x2D || first == 0x2A || first == 0x2B {
            return scanBullet(units: units, indentLength: indentLength)
        }

        // Ordered path: ASCII digit `0`–`9` (0x30–0x39).
        if first >= 0x30 && first <= 0x39 {
            return scanOrdered(units: units, indentLength: indentLength)
        }

        return .none
    }

    /// Classify a line known to start (after indent) with `-` / `*` / `+`.
    private static func scanBullet(units: [UInt16], indentLength: Int) -> ListLineShape {
        let length = units.count
        // Marker char position is `indentLength`; advance past it.
        var i = indentLength + 1

        // `-` (or `*` / `+`) alone — partial, markerLength == 1.
        if i == length {
            return .partial(indentLength: indentLength, markerLength: 1)
        }

        // Need exactly one space or tab after the marker char.
        guard units[i] == 0x20 || units[i] == 0x09 else { return .none }
        i += 1

        let depth = depth(forIndentUnits: units, indentLength: indentLength)

        // `- ` with no body — complete marker, empty body.
        if i == length {
            return .complete(
                indentLength: indentLength,
                markerLength: 2,
                kind: .bullet(depth: depth)
            )
        }

        // `- [` is a checkbox line (owned by CheckboxLineScanner). Refuse.
        if units[i] == 0x5B {
            return .none
        }

        return .complete(
            indentLength: indentLength,
            markerLength: 2,
            kind: .bullet(depth: depth)
        )
    }

    /// Classify a line known to start (after indent) with an ASCII digit.
    private static func scanOrdered(units: [UInt16], indentLength: Int) -> ListLineShape {
        let length = units.count

        // Consume the digit run.
        var i = indentLength
        var number = 0
        // Guard against integer overflow on absurd inputs by capping the
        // digit count; markdown ordered lists rarely exceed a few digits.
        // We continue scanning past the cap but stop accumulating into the
        // Int — the scanner is still a deterministic classifier.
        var overflow = false
        while i < length, units[i] >= 0x30 && units[i] <= 0x39 {
            if !overflow {
                let digit = Int(units[i] - 0x30)
                let (mul, mulOverflow) = number.multipliedReportingOverflow(by: 10)
                if mulOverflow {
                    overflow = true
                } else {
                    let (add, addOverflow) = mul.addingReportingOverflow(digit)
                    if addOverflow {
                        overflow = true
                    } else {
                        number = add
                    }
                }
            }
            i += 1
        }

        // Digits alone — partial. `markerLength` is the digit count.
        if i == length {
            return .partial(indentLength: indentLength, markerLength: i - indentLength)
        }

        // After digits, require `.` (0x2E). Anything else (including `)`)
        // is out of scope.
        guard units[i] == 0x2E else { return .none }
        i += 1

        // `<digits>.` alone — partial.
        if i == length {
            return .partial(indentLength: indentLength, markerLength: i - indentLength)
        }

        // After `.`, require exactly one space or tab. Otherwise (e.g.
        // `1.text`) it's not a list line.
        guard units[i] == 0x20 || units[i] == 0x09 else { return .none }
        i += 1

        let depth = depth(forIndentUnits: units, indentLength: indentLength)

        // `<digits>. ` with no body — complete marker, empty body.
        // Treat overflow as not-a-list-line — silently miscounting would be
        // worse than not concealing.
        if i == length {
            if overflow { return .none }
            return .complete(
                indentLength: indentLength,
                markerLength: i - indentLength,
                kind: .ordered(number: number, depth: depth)
            )
        }

        if overflow {
            return .none
        }

        return .complete(
            indentLength: indentLength,
            markerLength: i - indentLength,
            kind: .ordered(number: number, depth: depth)
        )
    }

    /// Compute nesting depth from leading whitespace. A tab counts as one
    /// depth level; spaces count as `floor(spaceCount / 2)`. Mixed indents
    /// sum the two contributions.
    private static func depth(forIndentUnits units: [UInt16], indentLength: Int) -> Int {
        var spaces = 0
        var tabs = 0
        for k in 0..<indentLength {
            if units[k] == 0x20 {
                spaces += 1
            } else if units[k] == 0x09 {
                tabs += 1
            }
        }
        return tabs + (spaces / 2)
    }
}
