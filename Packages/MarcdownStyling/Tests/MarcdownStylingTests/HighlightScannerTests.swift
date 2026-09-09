import Foundation
import Testing

@testable import MarcdownStyling

@Suite("HighlightScanner")
struct HighlightScannerTests {
    @Test func findsSingleSpan() {
        #expect(HighlightScanner.scan(line: "a ==b== c") == [NSRange(location: 2, length: 5)])
    }

    @Test func findsTwoSpans() {
        #expect(
            HighlightScanner.scan(line: "==a== ==b==") == [
                NSRange(location: 0, length: 5),
                NSRange(location: 6, length: 5),
            ])
    }

    @Test func ignoresUnterminated() {
        #expect(HighlightScanner.scan(line: "==open").isEmpty)
    }

    @Test func ignoresSpaceAfterOpener() {
        #expect(HighlightScanner.scan(line: "== not ==").isEmpty)
    }

    @Test func ignoresEmptySpan() {
        #expect(HighlightScanner.scan(line: "====").isEmpty)
    }

    @Test func ignoresSpaceBeforeCloser() {
        #expect(HighlightScanner.scan(line: "==a ==").isEmpty)
    }
}
