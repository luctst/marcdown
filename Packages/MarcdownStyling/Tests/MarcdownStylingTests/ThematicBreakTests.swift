import AppKit
import Testing

@testable import MarcdownStyling

@MainActor
@Suite("Thematic break")
struct ThematicBreakTests {
    private func styledStorage(_ source: String, focus: FocusLine? = nil) -> NSTextStorage {
        let styler = MarkdownStyler()
        let storage = NSTextStorage(string: source)
        styler.restyle(storage: storage, source: source, focusLine: focus)
        return storage
    }

    @Test func dashesAreClearPaintedAndTagged() {
        let storage = styledStorage("a\n\n---\n\nb")
        let ruleStart = 3
        for offset in ruleStart..<(ruleStart + 3) {
            #expect(storage.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? NSColor == NSColor.clear)
            #expect(storage.attribute(.marcdownThematicBreak, at: offset, effectiveRange: nil) as? Bool == true)
            #expect(storage.attribute(.marcdownConcealed, at: offset, effectiveRange: nil) as? Bool != true)
        }
        #expect(storage.attribute(.marcdownThematicBreak, at: 0, effectiveRange: nil) == nil)
    }

    @Test func starRuleIsNotTreatedAsBullet() {
        let storage = styledStorage("* * *")
        #expect(storage.attribute(.marcdownListMarker, at: 0, effectiveRange: nil) == nil)
        #expect(storage.attribute(.marcdownThematicBreak, at: 0, effectiveRange: nil) as? Bool == true)
    }

    @Test func indentedSpacedRuleIsNotTreatedAsBullet() {
        let storage = styledStorage("  - - -")
        #expect(storage.attribute(.marcdownListMarker, at: 2, effectiveRange: nil) == nil)
        #expect(storage.attribute(.marcdownThematicBreak, at: 2, effectiveRange: nil) as? Bool == true)
    }

    @Test func focusedRuleShowsDimDashesAndDropsTag() {
        let storage = styledStorage("---", focus: FocusLine(lineStart: 0, lineLength: 3))
        #expect(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == StylingTheme.system.dim)
        #expect(storage.attribute(.marcdownThematicBreak, at: 0, effectiveRange: nil) == nil)
    }

    @Test func setextUnderlineIsNotARule() {
        let storage = styledStorage("Title\n---")
        #expect(storage.attribute(.marcdownThematicBreak, at: 6, effectiveRange: nil) == nil)
    }
}
