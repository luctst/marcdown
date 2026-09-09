import AppKit
import Testing

@testable import MarcdownStyling

@MainActor
@Suite("Highlight styling")
struct HighlightStylingTests {
    private func styledStorage(_ source: String) -> NSTextStorage {
        let styler = MarkdownStyler()
        let storage = NSTextStorage(string: source)
        styler.restyle(storage: storage, source: source)
        return storage
    }

    @Test func contentGetsBackgroundAndDelimitersAreConcealed() {
        let storage = styledStorage("x ==hi== y")
        #expect(
            storage.attribute(.backgroundColor, at: 4, effectiveRange: nil) as? NSColor == StylingTheme.system.highlight
        )
        #expect(storage.attribute(.marcdownConcealed, at: 2, effectiveRange: nil) as? Bool == true)
        #expect(storage.attribute(.marcdownConcealed, at: 3, effectiveRange: nil) as? Bool == true)
        #expect(storage.attribute(.marcdownConcealed, at: 6, effectiveRange: nil) as? Bool == true)
        #expect(storage.attribute(.marcdownConcealed, at: 7, effectiveRange: nil) as? Bool == true)
        #expect(storage.attribute(.backgroundColor, at: 0, effectiveRange: nil) == nil)
    }

    @Test func codeBlockLinesAreLeftAlone() {
        let storage = styledStorage("```\na ==b== c\n```")
        #expect(storage.attribute(.backgroundColor, at: 8, effectiveRange: nil) == nil)
    }

    @Test func inlineCodeIsLeftAlone() {
        let storage = styledStorage("`a ==b== c`")
        #expect(storage.attribute(.marcdownConcealed, at: 3, effectiveRange: nil) as? Bool != true)
    }
}
