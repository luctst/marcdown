import Foundation
import Testing
@testable import MarcdownStyling

@Suite("LineOffsetIndex")
struct LineOffsetIndexTests {
    @Test func asciiConversionMatchesUtf16Offset() {
        let source = "hello\nworld"
        let index = LineOffsetIndex(source: source)

        // Line 1, col 1 -> offset 0 (before 'h')
        #expect(index.utf16Offset(line: 1, column: 1) == 0)
        // Line 2, col 1 -> offset 6 (after "hello\n")
        #expect(index.utf16Offset(line: 2, column: 1) == 6)
        // Line 2, col 6 -> offset 11 (after "world")
        #expect(index.utf16Offset(line: 2, column: 6) == 11)
    }

    @Test func multiByteUtf8ColumnsMapToUtf16() {
        // "café" is 5 UTF-8 bytes (é = 0xC3 0xA9) but 4 UTF-16 units.
        // "Héllo" is 6 UTF-8 bytes but 5 UTF-16 units.
        let source = "café\n# Héllo"
        let index = LineOffsetIndex(source: source)

        // Line 1, col 1 -> 0
        #expect(index.utf16Offset(line: 1, column: 1) == 0)
        // Line 1, end of line: 5 UTF-8 bytes -> 4 UTF-16 units
        #expect(index.utf16Offset(line: 1, column: 6) == 4)
        // Line 2, col 1 -> 5 (after "café\n", which is 4 + 1 UTF-16 units)
        #expect(index.utf16Offset(line: 2, column: 1) == 5)
        // Line 2 content is "# Héllo". The `H` sits at byte col 3 (after "# ").
        #expect(index.utf16Offset(line: 2, column: 3) == 7)
    }

    @Test func endOfFilePositionsAreClamped() {
        let source = "abc"
        let index = LineOffsetIndex(source: source)
        // Asking past the end clamps to source.utf16.count.
        let range = index.nsRange(line: 1, column: 1, endLine: 99, endColumn: 99)
        #expect(range.location == 0)
        #expect(range.length == source.utf16.count)
    }

    @Test func outOfBoundsStartClamps() {
        let source = "abc\ndef"
        let index = LineOffsetIndex(source: source)
        // Line far beyond source -> last known line start, column clamped.
        let range = index.nsRange(line: 100, column: 1, endLine: 100, endColumn: 100)
        #expect(range.location <= source.utf16.count)
        #expect(range.length >= 0)
        #expect(range.location + range.length <= source.utf16.count)
    }

    @Test func emptySourceReturnsZeroOffset() {
        let index = LineOffsetIndex(source: "")
        #expect(index.utf16Offset(line: 1, column: 1) == 0)
        let range = index.nsRange(line: 1, column: 1, endLine: 1, endColumn: 5)
        #expect(range == NSRange(location: 0, length: 0))
    }
}
