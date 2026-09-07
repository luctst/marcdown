import AppKit
import Foundation
import Testing

@testable import MarcdownStyling

@MainActor
@Suite("MarkdownStyler")
struct MarkdownStylerTests {

    // MARK: - attributedString(for:)

    @Test func headingProducesLargerBoldFontInRange() {
        let styler = MarkdownStyler()
        let source = "# Hello\n\nBody text"
        let attributed = styler.attributedString(for: source)

        let ns = source as NSString
        let headingRange = ns.range(of: "# Hello")
        let headingFont = attributed.attribute(.font, at: headingRange.location, effectiveRange: nil) as? NSFont
        #expect(headingFont != nil)
        let headingSize = headingFont?.pointSize ?? 0
        #expect(headingSize > 14)  // larger than base

        let traits = headingFont.map { NSFontManager.shared.traits(of: $0) } ?? []
        #expect(traits.contains(.boldFontMask))

        // Body should be plain base font.
        let bodyStart = ns.range(of: "Body text").location
        let bodyFont = attributed.attribute(.font, at: bodyStart, effectiveRange: nil) as? NSFont
        #expect(bodyFont?.pointSize == 15)
    }

    @Test func defaultBaseFontIsAvenirNextAt15() {
        let styler = MarkdownStyler()
        let source = "Body text"
        let attributed = styler.attributedString(for: source)

        let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font != nil)
        #expect(font?.pointSize == 15)
        #expect(font?.familyName?.contains("Avenir") == true)
    }

    @Test func strongAppliesBoldToInnerText() {
        let styler = MarkdownStyler()
        let source = "This is **bold** text"
        let attributed = styler.attributedString(for: source)

        let ns = source as NSString
        // Inspect a character inside "bold"
        let boldWord = ns.range(of: "bold")
        let font = attributed.attribute(.font, at: boldWord.location, effectiveRange: nil) as? NSFont
        #expect(font != nil)
        let traits = font.map { NSFontManager.shared.traits(of: $0) } ?? []
        #expect(traits.contains(.boldFontMask))
    }

    @Test func emphasisAppliesItalicToInnerText() {
        let styler = MarkdownStyler()
        let source = "This is *slanted* text"
        let attributed = styler.attributedString(for: source)

        let ns = source as NSString
        let innerRange = ns.range(of: "slanted")
        let font = attributed.attribute(.font, at: innerRange.location, effectiveRange: nil) as? NSFont
        #expect(font != nil)
        let traits = font.map { NSFontManager.shared.traits(of: $0) } ?? []
        #expect(traits.contains(.italicFontMask))
    }

    @Test func inlineCodeGetsMonospacedFont() {
        let styler = MarkdownStyler()
        let source = "Use `printf` here"
        let attributed = styler.attributedString(for: source)

        let ns = source as NSString
        let codeRange = ns.range(of: "`printf`")
        let font = attributed.attribute(.font, at: codeRange.location, effectiveRange: nil) as? NSFont
        #expect(font != nil)
        #expect(font?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true)
    }

    @Test func fencedCodeBlockIsFullyMonospaced() {
        let styler = MarkdownStyler()
        let source = """
            Intro

            ```
            let x = 1
            let y = 2
            ```

            Outro
            """
        let attributed = styler.attributedString(for: source)

        let ns = source as NSString
        let innerRange = ns.range(of: "let x = 1")
        let font = attributed.attribute(.font, at: innerRange.location, effectiveRange: nil) as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true)

        // Outside the block should not be monospaced.
        let outroRange = ns.range(of: "Outro")
        let outroFont = attributed.attribute(.font, at: outroRange.location, effectiveRange: nil) as? NSFont
        #expect(outroFont?.fontDescriptor.symbolicTraits.contains(.monoSpace) == false)
    }

    @Test func blockquoteMarkerIsClearPaintedAndBodyKeepsColor() {
        let styler = MarkdownStyler()
        let source = "> quoted line"
        let attributed = styler.attributedString(for: source)

        let markerColor = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(markerColor == NSColor.clear)
        let bodyColor = attributed.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor
        #expect(bodyColor == StylingTheme.system.body)
    }

    // MARK: - restyle(storage:source:)

    @Test func restyleIsIdempotent() {
        let styler = MarkdownStyler()
        let source = "# Title\n\n**Bold** and `code` here."
        let storage = NSTextStorage(string: source)

        styler.restyle(storage: storage, source: source)
        let first = NSAttributedString(attributedString: storage)

        styler.restyle(storage: storage, source: source)
        let second = NSAttributedString(attributedString: storage)

        #expect(first.isEqual(to: second))
        #expect(storage.string == source)
    }

    @Test func restyleReappliesAfterEdit() {
        let styler = MarkdownStyler()
        let initialSource = "# Title"
        let storage = NSTextStorage(string: initialSource)
        styler.restyle(storage: storage, source: initialSource)

        // User types " more" at the end: mutate characters, then restyle.
        storage.replaceCharacters(in: NSRange(location: storage.length, length: 0), with: " more")
        let newSource = storage.string
        styler.restyle(storage: storage, source: newSource)

        // Characters preserved.
        #expect(storage.string == "# Title more")

        // Heading styling still covers the whole line (it's still one heading).
        let font = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font != nil)
        #expect(font?.pointSize ?? 0 > 14)
    }

    @Test func fenceLinesAreClearPaintedAndOpeningFenceCarriesLanguage() {
        let styler = MarkdownStyler()
        let source = "```swift\nlet x = 1\n```"
        let storage = NSTextStorage(string: source)
        styler.restyle(storage: storage, source: source)

        #expect(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == NSColor.clear)
        #expect(storage.attribute(.marcdownCodeLanguage, at: 0, effectiveRange: nil) as? String == "swift")
        let closing = (source as NSString).length - 1
        #expect(storage.attribute(.foregroundColor, at: closing, effectiveRange: nil) as? NSColor == NSColor.clear)
        #expect(storage.attribute(.marcdownCodeLanguage, at: closing, effectiveRange: nil) == nil)
        #expect(
            storage.attribute(.foregroundColor, at: 10, effectiveRange: nil) as? NSColor == StylingTheme.system.body)
    }

    @Test func focusedFenceLineRevealsDimFenceAndHidesBadge() {
        let styler = MarkdownStyler()
        let source = "```swift\nlet x = 1\n```"
        let storage = NSTextStorage(string: source)
        styler.restyle(storage: storage, source: source, focusLine: FocusLine(lineStart: 0, lineLength: 8))

        #expect(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == StylingTheme.system.dim)
        #expect(storage.attribute(.marcdownCodeLanguage, at: 0, effectiveRange: nil) == nil)
    }
}
