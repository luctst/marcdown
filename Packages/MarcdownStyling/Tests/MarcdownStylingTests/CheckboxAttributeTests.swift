import AppKit
import Foundation
import Testing

@testable import MarcdownStyling

/// Verifies the attribute shape applied to a complete `- [ ]` / `- [x]`
/// marker. The icon painter relies on:
/// - Bullet + space (`- `) and the open bracket (`[`) being concealed
///   (zero advance, fully suppressed glyphs).
/// - The middle char and the close bracket being rendered `.clear`
///   (visible advance, invisible glyph) so the painted icon has a
///   stable, state-independent center to anchor on.
/// - The 3-char `[X]` range carrying a monospaced font so that toggling
///   between `' '` and `'x'` does not shift the icon horizontally.
@MainActor
@Suite("Checkbox attribute application")
struct CheckboxAttributeTests {

    private func restyle(_ source: String) -> NSTextStorage {
        let styler = MarkdownStyler()
        let storage = NSTextStorage(string: source)
        styler.restyle(storage: storage, source: source)
        return storage
    }

    // 1. Close bracket: `.clear` foreground, NOT concealed.
    @Test func closeBracketIsRenderedClearNotConcealed() {
        let storage = restyle("- [ ] foo")
        let closeIndex = 4  // ']'
        let color = storage.attribute(.foregroundColor, at: closeIndex, effectiveRange: nil) as? NSColor
        #expect(color == NSColor.clear)
        let concealed = storage.attribute(.marcdownConcealed, at: closeIndex, effectiveRange: nil) as? Bool
        #expect(concealed != true)
    }

    // 2. Middle char: `.clear`, not concealed.
    @Test func middleCharIsRenderedClearNotConcealed() {
        let storage = restyle("- [ ] foo")
        let middleIndex = 3  // ' ' between brackets
        let color = storage.attribute(.foregroundColor, at: middleIndex, effectiveRange: nil) as? NSColor
        #expect(color == NSColor.clear)
        let concealed = storage.attribute(.marcdownConcealed, at: middleIndex, effectiveRange: nil) as? Bool
        #expect(concealed != true)
    }

    // 3. Open bracket: concealed.
    @Test func openBracketIsConcealed() {
        let storage = restyle("- [ ] foo")
        let openIndex = 2  // '['
        let concealed = storage.attribute(.marcdownConcealed, at: openIndex, effectiveRange: nil) as? Bool
        #expect(concealed == true)
    }

    // 4. Bullet + space: concealed.
    @Test func bulletAndSeparatorAreConcealed() {
        let storage = restyle("- [ ] foo")
        for index in 0...1 {
            let concealed = storage.attribute(.marcdownConcealed, at: index, effectiveRange: nil) as? Bool
            #expect(concealed == true, "expected position \(index) to be concealed")
        }
    }

    // 5. Marker range tagged with state.
    @Test func markerRangeIsTaggedWithCheckboxState() {
        let storage = restyle("- [ ] foo")
        for index in 2...4 {
            let state = storage.attribute(.marcdownCheckbox, at: index, effectiveRange: nil) as? MarcdownCheckboxState
            #expect(state == .unchecked, "expected position \(index) to carry .unchecked")
        }
    }

    // 6. Marker range uses monospaced font (unchecked).
    @Test func markerRangeUsesMonospacedFont() {
        let storage = restyle("- [ ] foo")
        for index in 2...4 {
            let font = storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont
            #expect(font != nil, "expected font at position \(index)")
            #expect(
                font?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true,
                "expected monospace at position \(index)")
        }
    }

    // 7. Marker range uses monospaced font (checked).
    @Test func checkedMarkerRangeUsesMonospacedFont() {
        let storage = restyle("- [x] foo")
        for index in 2...4 {
            let font = storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont
            #expect(font != nil, "expected font at position \(index)")
            #expect(
                font?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true,
                "expected monospace at position \(index)")
        }
    }

    // 8. Plain text: no character carries the monospace trait (no false positives).
    @Test func markerRangeOutsideTaskUsesNoMonospaceTag() {
        let source = "plain text"
        let storage = restyle(source)
        for index in 0..<storage.length {
            let font = storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont
            let isMono = font?.fontDescriptor.symbolicTraits.contains(.monoSpace) ?? false
            #expect(isMono == false, "expected position \(index) to NOT be monospace")
        }
    }
}
