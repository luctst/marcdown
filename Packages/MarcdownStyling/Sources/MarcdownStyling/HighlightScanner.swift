import Foundation

/// Pure helper. AppKit-free. `==text==` is not CommonMark, so the AST walk
/// never sees it; this line scanner is the single owner of the shape.
public enum HighlightScanner {
    /// Line-relative UTF-16 ranges of every `==text==` span. A span opens at
    /// `==` followed by a non-space, non-`=` unit and closes at the next `==`
    /// preceded by a non-space unit. Unterminated openers are ignored.
    public static func scan(line: String) -> [NSRange] {
        let units = Array(line.utf16)
        let count = units.count
        var results: [NSRange] = []
        var i = 0
        // Minimum span is `==x==` (5 units).
        while i + 4 < count {
            if units[i] == 0x3D, units[i + 1] == 0x3D, units[i + 2] != 0x20, units[i + 2] != 0x3D {
                guard let close = closingIndex(units, from: i + 3) else { return results }
                results.append(NSRange(location: i, length: close + 2 - i))
                i = close + 2
                continue
            }
            i += 1
        }
        return results
    }

    private static func closingIndex(_ units: [UInt16], from start: Int) -> Int? {
        var j = start
        while j + 1 < units.count {
            if units[j] == 0x3D, units[j + 1] == 0x3D, units[j - 1] != 0x20 {
                return j
            }
            j += 1
        }
        return nil
    }
}
