import AppKit
import Foundation
import Testing
@testable import MarcdownStyling

/// Tests for the `.marcdownConcealed` attribute applied by `MarkdownStyler` /
/// `StyleWalker`. The attribute is the contract between the styler and the
/// editor's `NSLayoutManagerDelegate`; if these flags are wrong, the live
/// preview shows or hides the wrong characters.
///
/// We assert against the storage attributes directly — that is the public
/// boundary the layout delegate consumes. We never mutate `storage.string`.
@MainActor
@Suite("Concealment")
struct ConcealmentTests {

    // MARK: - Helpers

    /// Returns ranges where `.marcdownConcealed == true` is set, in order.
    private func concealedRanges(in storage: NSTextStorage) -> [NSRange] {
        var ranges: [NSRange] = []
        let full = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.marcdownConcealed, in: full, options: []) { value, range, _ in
            if let flag = value as? Bool, flag {
                ranges.append(range)
            }
        }
        return ranges
    }

    private func styledStorage(_ source: String) -> NSTextStorage {
        let styler = MarkdownStyler()
        let storage = NSTextStorage(string: source)
        styler.restyle(storage: storage, source: source)
        return storage
    }

    // MARK: - Heading marker concealment

    @Test func h1MarkerIsConcealed() {
        let storage = styledStorage("# Hello")
        let ranges = concealedRanges(in: storage)
        #expect(ranges == [NSRange(location: 0, length: 2)])
    }

    @Test func h2ThroughH6MarkersConcealedWithCorrectLengths() {
        let cases: [(source: String, expected: NSRange)] = [
            ("## Hi",        NSRange(location: 0, length: 3)),
            ("### Wat",      NSRange(location: 0, length: 4)),
            ("#### Four",    NSRange(location: 0, length: 5)),
            ("##### Five",   NSRange(location: 0, length: 6)),
            ("###### Six",   NSRange(location: 0, length: 7)),
        ]
        for (source, expected) in cases {
            let ranges = concealedRanges(in: styledStorage(source))
            #expect(ranges == [expected], "Wrong conceal range for \(source)")
        }
    }

    @Test func emptyHeadingConcealsHashOnly() {
        // `#\n` — the marker is a lone `#` (no trailing space). Length 1.
        let storage = styledStorage("#\nbody")
        let ranges = concealedRanges(in: storage)
        #expect(ranges == [NSRange(location: 0, length: 1)])
    }

    @Test func headingBodyTextIsNotConcealed() {
        let storage = styledStorage("# Hello")
        // Each character of "Hello" should have no concealed flag.
        for offset in 2..<7 {
            let value = storage.attribute(.marcdownConcealed, at: offset, effectiveRange: nil) as? Bool
            #expect(value != true, "Body char at \(offset) was concealed")
        }
    }

    // MARK: - Inline emphasis / strong / strike concealment

    @Test func emphasisAsteriskDelimitersAreConcealed() {
        let storage = styledStorage("*foo*")
        let ranges = concealedRanges(in: storage)
        #expect(ranges == [
            NSRange(location: 0, length: 1),
            NSRange(location: 4, length: 1),
        ])
        // Inner body is not flagged.
        for offset in 1..<4 {
            let value = storage.attribute(.marcdownConcealed, at: offset, effectiveRange: nil) as? Bool
            #expect(value != true)
        }
    }

    @Test func emphasisUnderscoreDelimitersAreConcealed() {
        let storage = styledStorage("_italic_")
        let ranges = concealedRanges(in: storage)
        #expect(ranges == [
            NSRange(location: 0, length: 1),
            NSRange(location: 7, length: 1),
        ])
    }

    @Test func strongAsteriskDelimitersAreConcealed() {
        let storage = styledStorage("**bold**")
        let ranges = concealedRanges(in: storage)
        #expect(ranges == [
            NSRange(location: 0, length: 2),
            NSRange(location: 6, length: 2),
        ])
    }

    @Test func strongUnderscoreDelimitersAreConcealed() {
        let storage = styledStorage("__bold__")
        let ranges = concealedRanges(in: storage)
        #expect(ranges == [
            NSRange(location: 0, length: 2),
            NSRange(location: 6, length: 2),
        ])
    }

    @Test func strikethroughDelimitersAreConcealed() {
        let storage = styledStorage("~~strike~~")
        let ranges = concealedRanges(in: storage)
        #expect(ranges == [
            NSRange(location: 0, length: 2),
            NSRange(location: 8, length: 2),
        ])
    }

    @Test func inlineCodeSingleBackticksAreConcealed() {
        let storage = styledStorage("`code`")
        let ranges = concealedRanges(in: storage)
        #expect(ranges == [
            NSRange(location: 0, length: 1),
            NSRange(location: 5, length: 1),
        ])
    }

    @Test func inlineCodeDoubleBackticksAreConcealed() {
        // ``code`` — opening and closing 2-backtick runs.
        let storage = styledStorage("``code``")
        let ranges = concealedRanges(in: storage)
        #expect(ranges == [
            NSRange(location: 0, length: 2),
            NSRange(location: 6, length: 2),
        ])
    }

    // MARK: - Disk invariant

    @Test func restylePreservesEveryCharacter() {
        let sources = [
            "# Hello",
            "## With **bold** and *italic*",
            "Plain ~~strike~~ and `code` here.",
            "# H1\n## H2\n### H3\n\n**b** _i_ ~~s~~ `c`",
        ]
        let styler = MarkdownStyler()
        for source in sources {
            let storage = NSTextStorage(string: source)
            styler.restyle(storage: storage, source: source)
            #expect(storage.string == source, "Storage mutated for: \(source)")
        }
    }

    // MARK: - Idempotency

    @Test func restyleIsIdempotentForConcealFlags() {
        let styler = MarkdownStyler()
        let source = "# Hello\n**bold**"
        let storage = NSTextStorage(string: source)

        styler.restyle(storage: storage, source: source)
        let first = concealedRanges(in: storage)

        styler.restyle(storage: storage, source: source)
        let second = concealedRanges(in: storage)

        #expect(first == second)
    }

    // MARK: - ATX edge cases (parser-level)

    @Test func sevenHashesIsNotAHeadingAndIsNotConcealed() {
        // Per CommonMark, 7+ hashes is not a heading. swift-markdown should
        // parse this as a paragraph, so no marker conceal flag is applied.
        let storage = styledStorage("####### too many")
        #expect(concealedRanges(in: storage).isEmpty)
    }

    @Test func hashWithoutSpaceIsNotAHeadingAndIsNotConcealed() {
        // `#hello` without a space is not an ATX heading per CommonMark.
        let storage = styledStorage("#hello")
        #expect(concealedRanges(in: storage).isEmpty)
    }

    // MARK: - Layout-delegate contract (storage attribute lookup)

    /// The `ConcealmentLayoutDelegate` (in MarcdownEditor) does not mutate
    /// storage; it reads `.marcdownConcealed` via
    /// `storage.attribute(_:at:longestEffectiveRange:in:)` and OR-s `.null`
    /// into the glyph properties for matched character indexes. We can't
    /// exercise the delegate from this package (it's `internal` and there's
    /// no test target in MarcdownEditor), but we can verify the contract it
    /// depends on: every concealed char index reports `true` via
    /// `attribute(at:longestEffectiveRange:in:)`, and the effective ranges
    /// returned exactly match the conceal ranges.
    @Test func longestEffectiveRangeReportsConcealRunsForLayoutDelegate() {
        let storage = styledStorage("# Hello")
        let full = NSRange(location: 0, length: storage.length)

        // Char 0 is inside the `# ` conceal run.
        var effective = NSRange(location: 0, length: 0)
        let value = storage.attribute(
            .marcdownConcealed,
            at: 0,
            longestEffectiveRange: &effective,
            in: full
        ) as? Bool
        #expect(value == true)
        #expect(effective == NSRange(location: 0, length: 2))

        // Char 2 ("H") is not concealed.
        var bodyEffective = NSRange(location: 0, length: 0)
        let bodyValue = storage.attribute(
            .marcdownConcealed,
            at: 2,
            longestEffectiveRange: &bodyEffective,
            in: full
        ) as? Bool
        #expect(bodyValue != true)
        // Effective body run covers all of "Hello".
        #expect(bodyEffective == NSRange(location: 2, length: 5))
    }
}
