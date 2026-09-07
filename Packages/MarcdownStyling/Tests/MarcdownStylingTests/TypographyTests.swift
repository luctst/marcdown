import AppKit
import Testing

@testable import MarcdownStyling

@MainActor
@Suite("Typography baseline")
struct TypographyTests {
    private func styledStorage(_ source: String) -> NSTextStorage {
        let styler = MarkdownStyler()
        let storage = NSTextStorage(string: source)
        styler.restyle(storage: storage, source: source)
        return storage
    }

    private func paragraphStyle(_ storage: NSTextStorage, at offset: Int) -> NSParagraphStyle? {
        storage.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle
    }

    @Test func bodyTextCarriesThemeLineHeight() {
        let storage = styledStorage("hello")
        #expect(paragraphStyle(storage, at: 0)?.lineHeightMultiple == StylingTheme.system.lineHeightMultiple)
        #expect(MarkdownStyler().baseParagraphStyle.lineHeightMultiple == 1.2)
    }

    @Test func listLineKeepsLineHeightAfterListPass() {
        let storage = styledStorage("- foo")
        #expect(paragraphStyle(storage, at: 3)?.lineHeightMultiple == StylingTheme.system.lineHeightMultiple)
        #expect(paragraphStyle(storage, at: 3)?.paragraphSpacingBefore == 4)
    }

    @Test func codeBlockKeepsLineHeight() {
        let storage = styledStorage("```\nlet x = 1\n```")
        #expect(paragraphStyle(storage, at: 5)?.lineHeightMultiple == StylingTheme.system.lineHeightMultiple)
        #expect(paragraphStyle(storage, at: 5)?.headIndent == 14)
    }

    @Test func headingUsesBaseFontFamilyInBold() {
        let storage = styledStorage("# Title")
        let font = storage.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        #expect(font?.familyName == NSFont(name: "AvenirNext-Regular", size: 15)?.familyName)
        #expect(NSFontManager.shared.traits(of: font ?? .systemFont(ofSize: 15)).contains(.boldFontMask))
        #expect(font?.pointSize == 25)
    }

    @Test func headingsGetSpaceAbove() {
        let h1 = styledStorage("# One")
        let h3 = styledStorage("### Three")
        #expect(paragraphStyle(h1, at: 2)?.paragraphSpacingBefore == 16)
        #expect(paragraphStyle(h3, at: 4)?.paragraphSpacingBefore == 8)
        #expect(paragraphStyle(h1, at: 2)?.paragraphSpacing == 4)
        #expect(paragraphStyle(h1, at: 2)?.lineHeightMultiple == StylingTheme.system.lineHeightMultiple)
    }
}
