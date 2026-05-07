import AppKit
import Foundation
import Testing

@testable import MarcdownStyling

/// Tests for GFM table styling applied by `MarkdownStyler` / `StyleWalker`.
///
/// The contract: tables are styled by *dimming* the structural syntax (pipes
/// and the separator/alignment row) to `theme.dim`, while cell content stays
/// at `theme.body`. The styler never mutates `storage.string`, never applies
/// `.marcdownConcealed` to table positions, and never forces the table block
/// to a monospaced font. Inline markup inside cells (e.g. `**bold**`) must
/// continue to style — that's the contract for `descendInto` on cells.
@MainActor
@Suite("TableStyling")
struct TableStylingTests {

    // MARK: - Helpers

    private func styledStorage(_ source: String) -> NSTextStorage {
        let storage = NSTextStorage(string: source)
        MarkdownStyler().restyle(storage: storage, source: source)
        return storage
    }

    private func color(at index: Int, in storage: NSTextStorage) -> NSColor? {
        guard index < storage.length else { return nil }
        return storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
    }

    // MARK: - Tests

    // 1. Every pipe in a header row is dim.
    @Test func headerPipesAreDim() {
        let source = "| A | B |\n| --- | --- |\n| 1 | 2 |\n"
        let storage = styledStorage(source)
        let dim = StylingTheme.system.dim
        let pipePositions = source.utf16.enumerated()
            .filter { $0.element == 0x7C }
            .map { $0.offset }
        for pos in pipePositions {
            #expect(color(at: pos, in: storage) == dim)
        }
    }

    // 2. Every non-syntax character in the separator row is dim.
    @Test func separatorRowIsDim() {
        let source = "| A | B |\n| --- | :---: |\n| 1 | 2 |\n"
        let storage = styledStorage(source)
        let dim = StylingTheme.system.dim
        let separatorStart = (source as NSString).range(of: "| --- | :---: |").location
        let separatorLen = ("| --- | :---: |" as NSString).length
        for pos in separatorStart..<(separatorStart + separatorLen) {
            #expect(color(at: pos, in: storage) == dim)
        }
    }

    // 3. Cell content is NOT dim — it stays at body color.
    @Test func cellContentIsNotDim() {
        let source = "| Hello | World |\n| --- | --- |\n| Foo | Bar |\n"
        let storage = styledStorage(source)
        let dim = StylingTheme.system.dim
        let body = StylingTheme.system.body
        for word in ["Hello", "World", "Foo", "Bar"] {
            let r = (source as NSString).range(of: word)
            for i in r.location..<(r.location + r.length) {
                #expect(color(at: i, in: storage) != dim)
                #expect(color(at: i, in: storage) == body)
            }
        }
    }

    // 4. No conceal flag is applied to any table position.
    @Test func tablesUseNoConceal() {
        let source = "| A | B |\n| --- | --- |\n| 1 | 2 |\n"
        let storage = styledStorage(source)
        for i in 0..<storage.length {
            let flag = storage.attribute(.marcdownConcealed, at: i, effectiveRange: nil) as? Bool
            #expect(flag != true)
        }
    }

    // 5. The table block does NOT receive blanket monospace.
    @Test func tableIsNotForcedMonospace() {
        let source = "| Hello | World |\n| --- | --- |\n| Foo | Bar |\n"
        let storage = styledStorage(source)
        let r = (source as NSString).range(of: "Hello")
        let font = storage.attribute(.font, at: r.location, effectiveRange: nil) as? NSFont
        // The default base font is the system font, not monospaced.
        #expect(font?.isFixedPitch == false)
    }

    // 6. Storage string is preserved across restyle.
    @Test func tableRestylePreservesCharacters() {
        let source = "| A | B |\n| --- | --- |\n| 1 | 2 |\n"
        let storage = NSTextStorage(string: source)
        MarkdownStyler().restyle(storage: storage, source: source)
        #expect(storage.string == source)
    }

    // 7. Restyle is idempotent.
    @Test func tableRestyleIsIdempotent() {
        let source = "| A | B |\n| --- | --- |\n| 1 | 2 |\n"
        let storage = NSTextStorage(string: source)
        MarkdownStyler().restyle(storage: storage, source: source)
        let firstSnapshot = (0..<storage.length).map {
            (storage.attribute(.foregroundColor, at: $0, effectiveRange: nil) as? NSColor)?.description
        }
        MarkdownStyler().restyle(storage: storage, source: source)
        let secondSnapshot = (0..<storage.length).map {
            (storage.attribute(.foregroundColor, at: $0, effectiveRange: nil) as? NSColor)?.description
        }
        #expect(firstSnapshot == secondSnapshot)
    }

    // 8. Malformed table (no separator row) does not crash; not parsed as Table.
    @Test func malformedTableDoesNotCrash() {
        let source = "| A | B |"
        let storage = NSTextStorage(string: source)
        MarkdownStyler().restyle(storage: storage, source: source)
        #expect(storage.string == source)
    }

    // 9. Adjacent blocks are not contaminated by table styling.
    @Test func adjacentBlocksAreNotContaminated() {
        let source = "# Heading\n\n| A |\n| --- |\n| B |\n\nA paragraph.\n"
        let storage = styledStorage(source)
        let body = StylingTheme.system.body
        let pr = (source as NSString).range(of: "A paragraph.")
        for i in pr.location..<(pr.location + pr.length) {
            #expect(color(at: i, in: storage) == body)
        }
    }

    // 10. Inline markup inside cells still styles (descendInto works).
    @Test func boldInsideCellIsStillBold() {
        let source = "| **bold** | plain |\n| --- | --- |\n| 1 | 2 |\n"
        let storage = styledStorage(source)
        let r = (source as NSString).range(of: "bold")
        let font = storage.attribute(.font, at: r.location, effectiveRange: nil) as? NSFont
        let isBold = font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
        #expect(isBold)
    }
}
