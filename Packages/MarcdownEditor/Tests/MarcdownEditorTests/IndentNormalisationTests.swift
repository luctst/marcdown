import AppKit
import MarcdownStyling
import Testing

@testable import MarcdownEditor

/// Tabs and spaces must produce the same visual indent per depth, and wrapped
/// lines must hang exactly under the first body glyph regardless of which
/// whitespace the file uses. Measured through a real layout pass with
/// the editor's concealment delegate suppressing concealed glyphs.
@MainActor
@Suite("Indent whitespace normalisation")
struct IndentNormalisationTests {
    @MainActor
    private struct Layout {
        let storage: NSTextStorage
        let manager = NSLayoutManager()
        let delegate = ConcealmentLayoutDelegate()  // NSLayoutManager.delegate is weak

        init(_ source: String) {
            storage = NSTextStorage(string: source)
            MarkdownStyler().restyle(storage: storage, source: source)
            let container = NSTextContainer(size: NSSize(width: 1000, height: 1000))
            container.lineFragmentPadding = 0
            manager.delegate = delegate
            manager.addTextContainer(container)
            storage.addLayoutManager(manager)
            manager.ensureLayout(for: container)
        }

        func x(ofCharacter index: Int) -> CGFloat {
            manager.location(forGlyphAt: manager.glyphIndexForCharacter(at: index)).x
        }
    }

    // Children sit under a parent item so cmark parses a nested list rather
    // than an indented code block. `x` is line-fragment relative, so child
    // and parent lines compare directly.

    @Test func tabAndTwoSpacesIndentTaskIdentically() {
        let tab = Layout("- [ ] a\n\t- [ ] foo")
        let spaces = Layout("- [ ] a\n  - [ ] foo")
        #expect(abs(tab.x(ofCharacter: 12) - spaces.x(ofCharacter: 13)) < 0.5)
    }

    @Test func tabAndTwoSpacesIndentBulletIdentically() {
        let tab = Layout("- a\n\t- foo")
        let spaces = Layout("- a\n  - foo")
        #expect(abs(tab.x(ofCharacter: 5) - spaces.x(ofCharacter: 6)) < 0.5)
    }

    @Test func childMarkerStartsWhereParentMarkerEnds() {
        // One level = one bullet marker width, so nesting reads as a real
        // step (child bullet under parent text) rather than a wobble.
        let bullets = Layout("- foo\n  - bar")
        #expect(abs(bullets.x(ofCharacter: 8) - bullets.x(ofCharacter: 2)) < 0.5)
        let tasks = Layout("- [ ] foo\n  - [ ] bar")
        #expect(abs(tasks.x(ofCharacter: 15) - tasks.x(ofCharacter: 5)) < 0.5)
    }

    @Test func wrappedLinesHangUnderBodyWhateverTheIndent() {
        for child in ["\t- foo", "\t- [ ] foo", "\t1. foo", "  \t- foo", "    - [x] foo"] {
            let source = "- [ ] a\n" + child
            let l = Layout(source)
            let body = (source as NSString).range(of: "foo").location
            let head = (l.storage.attribute(.paragraphStyle, at: 8, effectiveRange: nil) as? NSParagraphStyle)?.headIndent ?? -1
            #expect(abs(head - l.x(ofCharacter: body)) < 0.5, "\(child.debugDescription)")
        }
    }
}
