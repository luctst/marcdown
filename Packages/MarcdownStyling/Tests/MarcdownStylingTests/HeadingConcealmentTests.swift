import AppKit
import Foundation
import Testing

@testable import MarcdownStyling

/// Regression tests for the "bare hash stays visible until trailing space"
/// behavior in `StyleWalker.visitHeading`. The styler must NOT conceal or
/// upsize ATX hashes until the user types a space after them (heading
/// intent confirmed). Once a trailing space is present, all the existing
/// concealment and font-bump behavior must remain intact.
@MainActor
@Suite("Heading concealment")
struct HeadingConcealmentTests {

    private let baseFont = NSFont.systemFont(ofSize: 14)

    // MARK: - Bare hashes (no trailing space) — must render as plain text

    @Test func bareHashIsNotConcealedAndKeepsBaseFont() {
        let storage = styledStorage(for: "#")

        let concealed = storage.attribute(.marcdownConcealed, at: 0, effectiveRange: nil) as? Bool
        #expect(concealed != true)

        let color = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(color != NSColor.clear)

        let font = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font?.pointSize == baseFont.pointSize)
    }

    @Test func bareDoubleHashIsNotConcealedAndKeepsBaseFont() {
        let storage = styledStorage(for: "##")

        for idx in 0..<2 {
            let concealed = storage.attribute(.marcdownConcealed, at: idx, effectiveRange: nil) as? Bool
            #expect(concealed != true, "char \(idx) should not be concealed")
            let color = storage.attribute(.foregroundColor, at: idx, effectiveRange: nil) as? NSColor
            #expect(color != NSColor.clear, "char \(idx) should not be clear-painted")
            let font = storage.attribute(.font, at: idx, effectiveRange: nil) as? NSFont
            #expect(font?.pointSize == baseFont.pointSize, "char \(idx) should keep base font size")
        }
    }

    @Test func bareTripleHashIsNotConcealedAndKeepsBaseFont() {
        let storage = styledStorage(for: "###")

        for idx in 0..<3 {
            let concealed = storage.attribute(.marcdownConcealed, at: idx, effectiveRange: nil) as? Bool
            #expect(concealed != true, "char \(idx) should not be concealed")
            let color = storage.attribute(.foregroundColor, at: idx, effectiveRange: nil) as? NSColor
            #expect(color != NSColor.clear, "char \(idx) should not be clear-painted")
            let font = storage.attribute(.font, at: idx, effectiveRange: nil) as? NSFont
            #expect(font?.pointSize == baseFont.pointSize, "char \(idx) should keep base font size")
        }
    }

    /// The fix must not only apply at the start of the buffer — a bare `#`
    /// after a newline should also remain visible.
    @Test func bareHashAfterNewlineIsNotConcealed() {
        let source = "foo\n#"
        let storage = styledStorage(for: source)

        let hashIndex = (source as NSString).range(of: "#").location
        let concealed = storage.attribute(.marcdownConcealed, at: hashIndex, effectiveRange: nil) as? Bool
        #expect(concealed != true)

        let color = storage.attribute(.foregroundColor, at: hashIndex, effectiveRange: nil) as? NSColor
        #expect(color != NSColor.clear)

        let font = storage.attribute(.font, at: hashIndex, effectiveRange: nil) as? NSFont
        #expect(font?.pointSize == baseFont.pointSize)
    }

    // MARK: - Empty heading with trailing space — clear-paint preserved

    /// `"# "` (hash + space, no body) is the existing empty-heading branch.
    /// The marker range must still be clear-painted so the marker is invisible
    /// while the line keeps its advance for the cursor. The fix must NOT
    /// regress this branch.
    @Test func emptyHeadingWithTrailingSpaceIsClearPainted() {
        let storage = styledStorage(for: "# ")

        // Both the `#` and the space share the clear-paint treatment.
        let hashColor = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let spaceColor = storage.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor
        #expect(hashColor == NSColor.clear)
        #expect(spaceColor == NSColor.clear)
    }

    // MARK: - Heading with body — concealment + font bump preserved

    /// H1 body should receive the largest heading font; the marker is
    /// concealed. This is the existing behavior; ensure the fix doesn't
    /// accidentally regress it.
    @Test func h1WithBodyConcealsMarkerAndBumpsFont() {
        let storage = styledStorage(for: "# Hello")

        // `# ` (0..<2) is concealed.
        let markerConcealed = storage.attribute(.marcdownConcealed, at: 0, effectiveRange: nil) as? Bool
        #expect(markerConcealed == true)

        // Body font is larger than base.
        let bodyFont = storage.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        #expect((bodyFont?.pointSize ?? 0) > baseFont.pointSize)
    }

    @Test func h2WithBodyConcealsMarkerAndBumpsFont() {
        let storage = styledStorage(for: "## Hello")

        for idx in 0..<3 {
            let concealed = storage.attribute(.marcdownConcealed, at: idx, effectiveRange: nil) as? Bool
            #expect(concealed == true, "char \(idx) of `## ` should be concealed")
        }

        let bodyFont = storage.attribute(.font, at: 3, effectiveRange: nil) as? NSFont
        #expect((bodyFont?.pointSize ?? 0) > baseFont.pointSize)
    }

    @Test func h3WithBodyConcealsMarkerAndBumpsFont() {
        let storage = styledStorage(for: "### Hello")

        for idx in 0..<4 {
            let concealed = storage.attribute(.marcdownConcealed, at: idx, effectiveRange: nil) as? Bool
            #expect(concealed == true, "char \(idx) of `### ` should be concealed")
        }

        let bodyFont = storage.attribute(.font, at: 4, effectiveRange: nil) as? NSFont
        #expect((bodyFont?.pointSize ?? 0) > baseFont.pointSize)
    }

    /// Heading levels must be visually distinct: H1 > H2 > H3 > base. If any
    /// future refactor collapses them, this test catches it.
    @Test func headingSizesAreOrderedAndDistinct() {
        let h1 = styledStorage(for: "# H1")
        let h2 = styledStorage(for: "## H2")
        let h3 = styledStorage(for: "### H3")

        let h1Size = (h1.attribute(.font, at: 2, effectiveRange: nil) as? NSFont)?.pointSize ?? 0
        let h2Size = (h2.attribute(.font, at: 3, effectiveRange: nil) as? NSFont)?.pointSize ?? 0
        let h3Size = (h3.attribute(.font, at: 4, effectiveRange: nil) as? NSFont)?.pointSize ?? 0

        #expect(h1Size > h2Size)
        #expect(h2Size > h3Size)
        #expect(h3Size > baseFont.pointSize)
    }

    // MARK: - Helpers

    private func styledStorage(for source: String) -> NSTextStorage {
        let storage = NSTextStorage(string: source)
        let styler = MarkdownStyler(baseFont: baseFont)
        styler.restyle(storage: storage, source: source)
        return storage
    }
}
