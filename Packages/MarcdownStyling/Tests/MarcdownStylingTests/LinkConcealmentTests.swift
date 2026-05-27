import AppKit
import Foundation
import Testing

@testable import MarcdownStyling

/// Tests for inline link concealment and tagging applied by
/// `StyleWalker.visitLink`. The styler must:
///
/// * Conceal `[`, `]`, `(`, the URL chars, and `)` via `.marcdownConcealed`.
/// * Leave the label text (between `[` and `]`) visible.
/// * Tag the label run with `.marcdownLink = destination` so the editor's
///   click handler can resolve a Cmd+click to a URL.
/// * Style the label with the theme's accent color and a single underline,
///   so the user can see it is a link.
///
/// Like `ConcealmentTests`, we assert against storage attributes directly —
/// that is the boundary the layout delegate and click handler consume.
@MainActor
@Suite("Link Concealment")
struct LinkConcealmentTests {

    // MARK: - Helpers

    private func styledStorage(_ source: String) -> NSTextStorage {
        let styler = MarkdownStyler()
        let storage = NSTextStorage(string: source)
        styler.restyle(storage: storage, source: source)
        return storage
    }

    private func concealedRanges(in storage: NSTextStorage) -> [NSRange] {
        var ranges: [NSRange] = []
        let full = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.marcdownConcealed, in: full, options: []) { value, range, _ in
            if let flag = value as? Bool, flag { ranges.append(range) }
        }
        return ranges
    }

    /// Enumerates `.marcdownLink` runs whose value is a `String`, in order.
    private func linkRuns(in storage: NSTextStorage) -> [(range: NSRange, destination: String)] {
        var runs: [(NSRange, String)] = []
        let full = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.marcdownLink, in: full, options: []) { value, range, _ in
            if let destination = value as? String {
                runs.append((range, destination))
            }
        }
        return runs
    }

    // MARK: - Standard link concealment

    @Test func standardLinkConcealsBracketsAndURL() {
        let source = "[Anthropic](https://anthropic.com)"
        let storage = styledStorage(source)

        let ns = source as NSString
        // `[` at index 0, length 1.
        let openBracket = ns.range(of: "[")
        // `](https://anthropic.com)` — everything from `]` to the trailing `)`.
        let tail = ns.range(of: "](https://anthropic.com)")
        let labelRange = ns.range(of: "Anthropic")

        #expect(concealedRanges(in: storage) == [openBracket, tail])

        for offset in labelRange.location..<(labelRange.location + labelRange.length) {
            let value = storage.attribute(.marcdownConcealed, at: offset, effectiveRange: nil) as? Bool
            #expect(value != true, "Label char at \(offset) was concealed")
        }
    }

    @Test func standardLinkLabelCarriesMarcdownLinkAttribute() {
        let source = "[Anthropic](https://anthropic.com)"
        let storage = styledStorage(source)

        let ns = source as NSString
        let labelRange = ns.range(of: "Anthropic")

        // Every char of the label reports the same destination.
        for offset in labelRange.location..<(labelRange.location + labelRange.length) {
            let value = storage.attribute(.marcdownLink, at: offset, effectiveRange: nil) as? String
            #expect(value == "https://anthropic.com", "Label char at \(offset) missing link tag")
        }

        // Concealed syntax chars (`[`, `]`, `(`, URL, `)`) must NOT carry the link tag —
        // the click handler keys off the label run only, and a Cmd+click on the
        // (invisible) syntax should never fire.
        let openBracket = ns.range(of: "[").location
        #expect(storage.attribute(.marcdownLink, at: openBracket, effectiveRange: nil) == nil)

        // `]` lives immediately after the label.
        let closeBracket = labelRange.location + labelRange.length
        #expect(storage.attribute(.marcdownLink, at: closeBracket, effectiveRange: nil) == nil)

        // Pick a char inside the URL portion — `(` is at closeBracket + 1.
        let urlStart = closeBracket + 1 + 1  // skip `]` then `(`
        #expect(storage.attribute(.marcdownLink, at: urlStart, effectiveRange: nil) == nil)
    }

    // MARK: - Empty URL

    @Test func emptyURLLinkConcealsSyntaxAndTagsLabel() {
        let source = "[empty]()"
        let storage = styledStorage(source)

        let ns = source as NSString
        let labelRange = ns.range(of: "empty")

        // Label is not concealed.
        for offset in labelRange.location..<(labelRange.location + labelRange.length) {
            let value = storage.attribute(.marcdownConcealed, at: offset, effectiveRange: nil) as? Bool
            #expect(value != true, "Label char at \(offset) was concealed")
        }

        // Label carries an empty-string destination — `[empty]()` has no URL.
        for offset in labelRange.location..<(labelRange.location + labelRange.length) {
            let value = storage.attribute(.marcdownLink, at: offset, effectiveRange: nil) as? String
            #expect(value == "", "Label char at \(offset) should carry empty link tag")
        }

        // `]()` — the 3-char tail starting at `]`.
        let tail = ns.range(of: "]()")
        let openBracket = ns.range(of: "[")
        #expect(concealedRanges(in: storage) == [openBracket, tail])
    }

    // MARK: - Visual styling on the label

    @Test func linkLabelHasAccentColorAndUnderline() {
        let source = "[click me](https://example.com)"
        let storage = styledStorage(source)

        let ns = source as NSString
        let labelRange = ns.range(of: "click me")

        let expectedColor = StylingTheme.system.accent

        for offset in labelRange.location..<(labelRange.location + labelRange.length) {
            let color = storage.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? NSColor
            #expect(color == expectedColor, "Label char at \(offset) missing accent color")

            let underline = storage.attribute(.underlineStyle, at: offset, effectiveRange: nil) as? Int
            #expect(
                underline == NSUnderlineStyle.single.rawValue,
                "Label char at \(offset) missing single underline")
        }
    }

    // MARK: - Surrounding text

    @Test func linkInsideSentenceDoesNotConcealSurroundingText() {
        let source = "Go to [GitHub](https://github.com) now"
        let storage = styledStorage(source)

        let ns = source as NSString
        let prefix = ns.range(of: "Go to ")
        let label = ns.range(of: "GitHub")
        let suffix = ns.range(of: " now")

        for range in [prefix, label, suffix] {
            for offset in range.location..<(range.location + range.length) {
                let value = storage.attribute(.marcdownConcealed, at: offset, effectiveRange: nil) as? Bool
                #expect(value != true, "Char at \(offset) was unexpectedly concealed")
            }
        }
    }

    // MARK: - Multiple links

    @Test func twoLinksOnOneLine() {
        let source = "[A](https://a.com) and [B](https://b.com)"
        let storage = styledStorage(source)

        let ns = source as NSString
        let labelA = ns.range(of: "A")  // first occurrence — the label
        let labelB = ns.range(of: "B")

        let runs = linkRuns(in: storage)
        #expect(runs.count == 2, "Expected exactly two link runs, got \(runs.count)")

        #expect(runs.first?.range == labelA)
        #expect(runs.first?.destination == "https://a.com")

        #expect(runs.last?.range == labelB)
        #expect(runs.last?.destination == "https://b.com")

        // Neither label is concealed.
        for range in [labelA, labelB] {
            for offset in range.location..<(range.location + range.length) {
                let value = storage.attribute(.marcdownConcealed, at: offset, effectiveRange: nil) as? Bool
                #expect(value != true, "Label char at \(offset) was concealed")
            }
        }
    }

    // MARK: - Disk invariant

    @Test func storageStringIsPreservedAfterLinkRestyle() {
        let source = "[text](https://url.com)"
        let storage = styledStorage(source)
        #expect(storage.string == source)
    }
}
