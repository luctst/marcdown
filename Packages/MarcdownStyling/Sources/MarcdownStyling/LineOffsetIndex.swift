import Foundation
import Markdown

/// Converts (line, column) source positions reported by `swift-markdown`
/// (which mirror cmark_gfm) into UTF-16 offsets suitable for
/// `NSAttributedString` / `NSTextStorage` ranges.
///
/// cmark_gfm reports columns as 1-based UTF-8 byte offsets within the line.
/// `NSAttributedString` indexes by UTF-16 code unit. For ASCII these are
/// identical; for multi-byte characters they diverge, so we walk the source
/// once to build a UTF-8-line-start table and convert per query.
public struct LineOffsetIndex {
    private let source: String
    private let utf8LineStarts: [Int]

    public init(source: String) {
        self.source = source
        var starts = [0]
        var byteOffset = 0
        for byte in source.utf8 {
            byteOffset += 1
            if byte == 0x0A { starts.append(byteOffset) }
        }
        self.utf8LineStarts = starts
    }

    /// Converts a (line, column) — both 1-based, column in UTF-8 bytes — to
    /// the equivalent UTF-16 offset.
    public func utf16Offset(line: Int, column: Int) -> Int {
        guard !utf8LineStarts.isEmpty else { return 0 }
        let lineIndex = max(0, min(line - 1, utf8LineStarts.count - 1))
        let utf8Target = utf8LineStarts[lineIndex] + max(0, column - 1)
        return convertUtf8ToUtf16(byteOffset: utf8Target)
    }

    /// Builds an NSRange from a markdown source range, clamped to the bounds
    /// of the source string.
    public func nsRange(line startLine: Int, column startColumn: Int, endLine: Int, endColumn: Int) -> NSRange {
        let lower = utf16Offset(line: startLine, column: startColumn)
        let upper = utf16Offset(line: endLine, column: endColumn)
        let utf16Length = source.utf16.count
        let safeLower = min(lower, utf16Length)
        let safeUpper = min(max(upper, safeLower), utf16Length)
        return NSRange(location: safeLower, length: safeUpper - safeLower)
    }

    /// Convenience overload accepting swift-markdown's `SourceRange`. Returns
    /// `nil` when the input range is `nil` (which happens for synthetic nodes
    /// without source positions).
    public func nsRange(_ range: SourceRange?) -> NSRange? {
        guard let range else { return nil }
        return nsRange(
            line: range.lowerBound.line,
            column: range.lowerBound.column,
            endLine: range.upperBound.line,
            endColumn: range.upperBound.column
        )
    }

    private func convertUtf8ToUtf16(byteOffset: Int) -> Int {
        let utf8 = source.utf8
        let utf16 = source.utf16
        let cappedByteOffset = min(byteOffset, utf8.count)
        let utf8Index = utf8.index(utf8.startIndex, offsetBy: cappedByteOffset)

        // Walk back to a UTF-8 boundary that aligns with a String.Index. cmark
        // shouldn't hand us mid-grapheme positions, but be defensive.
        var probe = utf8Index
        while probe > utf8.startIndex {
            if let aligned = probe.samePosition(in: source) {
                if let utf16Idx = aligned.samePosition(in: utf16) {
                    return utf16.distance(from: utf16.startIndex, to: utf16Idx)
                }
            }
            probe = utf8.index(before: probe)
        }
        return 0
    }
}
