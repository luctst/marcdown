import AppKit
import Testing

@testable import MarcdownStyling

@MainActor
@Suite("Hanging indent on list lines")
struct HangingIndentTests {
    private func headIndent(_ source: String, at offset: Int) -> CGFloat {
        let styler = MarkdownStyler()
        let storage = NSTextStorage(string: source)
        styler.restyle(storage: storage, source: source)
        let style = storage.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle
        return style?.headIndent ?? -1
    }

    private func firstLineHeadIndent(_ source: String) -> CGFloat {
        let styler = MarkdownStyler()
        let storage = NSTextStorage(string: source)
        styler.restyle(storage: storage, source: source)
        let style = storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        return style?.firstLineHeadIndent ?? -1
    }

    @Test func bulletLineHangsBodyUnderFirstCharacter() {
        #expect(headIndent("- foo bar", at: 4) > 0)
        #expect(firstLineHeadIndent("- foo bar") == 0)
    }

    @Test func nestedBulletHangsFurther() {
        #expect(headIndent("  - foo", at: 5) > headIndent("- foo", at: 3))
    }

    @Test func twoDigitOrderedMarkerHangsFurtherThanOneDigit() {
        #expect(headIndent("10. foo", at: 5) > headIndent("1. foo", at: 4))
    }

    @Test func taskLineHangs() {
        #expect(headIndent("- [ ] foo", at: 7) > 0)
    }

    @Test func partialMarkerDoesNotHang() {
        #expect(headIndent("-", at: 0) == 0)
        #expect(headIndent("1.", at: 0) == 0)
    }

    @Test func plainLineDoesNotHang() {
        #expect(headIndent("foo", at: 0) == 0)
    }
}
