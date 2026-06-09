import AppKit
import Foundation
import Testing

@testable import MarcdownStyling

// MARK: - Expected production API (to be implemented by guy)
//
// Spec §4.7 + acceptance #11: nested bullet items render with different glyph
// styles per depth (filled circle / hollow circle / filled diamond / hollow
// diamond). The styler must encode the depth so the layout manager can pick
// the right glyph. The cleanest way is to put the depth in the
// `.marcdownListMarker` payload:
//
//   public enum MarcdownListMarkerKind: Sendable, Equatable, Hashable {
//       case bullet(depth: Int)         // 0-indexed depth (0 = top level)
//       case ordered(number: Int, depth: Int)
//   }
//
// Depth is computed by `floor(leadingWhitespaceUnits / 2)`. A tab counts as
// one depth level (consistent with `ListIndentation.outdentOutcome` stripping
// one tab as the indent unit).
//
// NOTE: This is a breaking change to the existing `MarcdownListMarkerKind`.
// The existing `ListAttributeTests` use `.bullet` and `.ordered(number:)` —
// guy must update those tests' expectations as part of this change. We pin
// the *new* contract here; the migration of the older tests is part of the
// production work.

@MainActor
@Suite("Nested bullet depth attribute")
struct NestedBulletDepthTests {

    private func restyle(_ source: String) -> NSTextStorage {
        let styler = MarkdownStyler()
        let storage = NSTextStorage(string: source)
        styler.restyle(storage: storage, source: source)
        return storage
    }

    @Test func topLevelBulletIsDepthZero() {
        let storage = restyle("- foo")
        let kind = storage.attribute(.marcdownListMarker, at: 0, effectiveRange: nil) as? MarcdownListMarkerKind
        #expect(kind == .bullet(depth: 0))
    }

    @Test func twoSpaceIndentedBulletIsDepthOne() {
        let storage = restyle("  - foo")
        let kind = storage.attribute(.marcdownListMarker, at: 2, effectiveRange: nil) as? MarcdownListMarkerKind
        #expect(kind == .bullet(depth: 1))
    }

    @Test func fourSpaceIndentedBulletIsDepthTwo() {
        let storage = restyle("    - foo")
        let kind = storage.attribute(.marcdownListMarker, at: 4, effectiveRange: nil) as? MarcdownListMarkerKind
        #expect(kind == .bullet(depth: 2))
    }

    @Test func sixSpaceIndentedBulletIsDepthThree() {
        let storage = restyle("      - foo")
        let kind = storage.attribute(.marcdownListMarker, at: 6, effectiveRange: nil) as? MarcdownListMarkerKind
        #expect(kind == .bullet(depth: 3))
    }

    @Test func tabIndentedBulletIsDepthOne() {
        // One tab counts as one depth level (same indent unit as the
        // outdent helper strips).
        let storage = restyle("\t- foo")
        let kind = storage.attribute(.marcdownListMarker, at: 1, effectiveRange: nil) as? MarcdownListMarkerKind
        #expect(kind == .bullet(depth: 1))
    }

    @Test func indentedOrderedItemCarriesDepth() {
        let storage = restyle("  1. foo")
        let kind = storage.attribute(.marcdownListMarker, at: 2, effectiveRange: nil) as? MarcdownListMarkerKind
        #expect(kind == .ordered(number: 1, depth: 1))
    }

    @Test func topLevelOrderedItemIsDepthZero() {
        let storage = restyle("1. foo")
        let kind = storage.attribute(.marcdownListMarker, at: 0, effectiveRange: nil) as? MarcdownListMarkerKind
        #expect(kind == .ordered(number: 1, depth: 0))
    }
}
