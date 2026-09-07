import AppKit
import Testing

@testable import MarcdownStyling

@MainActor
@Suite("Blockquote styling")
struct BlockquoteStylingTests {
    private func styledStorage(_ source: String) -> NSTextStorage {
        let styler = MarkdownStyler()
        let storage = NSTextStorage(string: source)
        styler.restyle(storage: storage, source: source)
        return storage
    }

    private func style(_ storage: NSTextStorage, at offset: Int) -> NSParagraphStyle? {
        storage.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle
    }

    @Test func wholeQuoteIsTagged() {
        let storage = styledStorage("> one\n> two")
        for offset in 0..<storage.length {
            #expect(storage.attribute(.marcdownBlockquote, at: offset, effectiveRange: nil) as? Bool == true)
        }
    }

    @Test func markerIsClearPaintedMonospacedNotConcealed() {
        let storage = styledStorage("> hi")
        for offset in 0..<2 {
            #expect(storage.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? NSColor == NSColor.clear)
            let font = storage.attribute(.font, at: offset, effectiveRange: nil) as? NSFont
            #expect(font?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true)
            #expect(storage.attribute(.marcdownConcealed, at: offset, effectiveRange: nil) as? Bool != true)
        }
    }

    @Test func nestedMarkersAreAllClearPainted() {
        let storage = styledStorage("> > deep")
        for offset in 0..<4 {
            #expect(storage.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? NSColor == NSColor.clear)
        }
        #expect(storage.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor == StylingTheme.system.body)
    }

    @Test func bodyHangsUnderFirstCharacterAndLazyLineAligns() {
        let storage = styledStorage("> first line\nlazy continuation")
        let quoted = style(storage, at: 3)
        let lazy = style(storage, at: 15)
        #expect(quoted?.firstLineHeadIndent == 0)
        #expect((quoted?.headIndent ?? 0) > 0)
        #expect(lazy?.firstLineHeadIndent == lazy?.headIndent)
        #expect(lazy?.headIndent == quoted?.headIndent)
    }

    @Test func focusedLineRevealsMarkerAsDimButKeepsBarTag() {
        let source = "> hi"
        let styler = MarkdownStyler()
        let storage = NSTextStorage(string: source)
        styler.restyle(storage: storage, source: source, focusLine: FocusLine(lineStart: 0, lineLength: 4))
        #expect(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == StylingTheme.system.dim)
        #expect(storage.attribute(.marcdownBlockquote, at: 0, effectiveRange: nil) as? Bool == true)
    }
}
