import AppKit
import Foundation
import Testing

@testable import MarcdownStyling

/// Verifies the attribute shape applied by `applyListScannerPass` to plain
/// bullet (`-`, `*`, `+`) and ordered (`1.`, `10.`, …) list markers.
///
/// The icon painter relies on:
/// - The marker syntax char(s) being either concealed (zero-advance, glyph
///   suppressed) or painted `.clear` (visible advance, invisible glyph) so
///   the drawn bullet circle / number overlay has a stable anchor box.
/// - The `.marcdownListMarker` tag spanning the full marker run so the
///   layout manager can locate the anchor with a single attribute lookup.
/// - Checkbox lines being skipped entirely by the list pass so the
///   checkbox pass remains the single owner of those ranges.
@MainActor
@Suite("List marker attribute application")
struct ListAttributeTests {

    private func restyle(_ source: String) -> NSTextStorage {
        let styler = MarkdownStyler()
        let storage = NSTextStorage(string: source)
        styler.restyle(storage: storage, source: source)
        return storage
    }

    // MARK: - Bullet `.complete`

    @Test func dashBulletMarkerCharIsClearPaintedNotConcealed() {
        let storage = restyle("- foo")
        let concealed = storage.attribute(.marcdownConcealed, at: 0, effectiveRange: nil) as? Bool
        #expect(concealed != true)
        let color = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(color == NSColor.clear)
    }

    @Test func dashBulletSpaceIsRenderedClearNotConcealed() {
        let storage = restyle("- foo")
        let concealed = storage.attribute(.marcdownConcealed, at: 1, effectiveRange: nil) as? Bool
        #expect(concealed != true)
        let color = storage.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor
        #expect(color == NSColor.clear)
    }

    @Test func dashBulletMarkerRangeUsesMonospacedFont() {
        let storage = restyle("- foo")
        for index in 0...1 {
            let font = storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont
            #expect(font != nil, "expected font at position \(index)")
            #expect(
                font?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true,
                "expected monospace at position \(index)")
        }
    }

    @Test func dashBulletBodyHasNoConcealmentOrMarkerTag() {
        let storage = restyle("- foo")
        for index in 2..<storage.length {
            let concealed = storage.attribute(.marcdownConcealed, at: index, effectiveRange: nil) as? Bool
            #expect(concealed != true, "expected position \(index) to NOT be concealed")
            let marker =
                storage.attribute(.marcdownListMarker, at: index, effectiveRange: nil) as? MarcdownListMarkerKind
            #expect(marker == nil, "expected no list-marker tag at position \(index)")
        }
    }

    @Test func dashBulletMarkerTagSpansTwoChars() {
        let storage = restyle("- foo")
        var effective = NSRange(location: 0, length: 0)
        let kind =
            storage.attribute(
                .marcdownListMarker,
                at: 0,
                longestEffectiveRange: &effective,
                in: NSRange(location: 0, length: storage.length)
            ) as? MarcdownListMarkerKind
        #expect(kind == .bullet)
        #expect(effective == NSRange(location: 0, length: 2))
    }

    @Test func asteriskBulletProducesIdenticalLayout() {
        let storage = restyle("* foo")
        let concealedMarker = storage.attribute(.marcdownConcealed, at: 0, effectiveRange: nil) as? Bool
        #expect(concealedMarker != true)
        let markerColor = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(markerColor == NSColor.clear)
        let color = storage.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor
        #expect(color == NSColor.clear)
        var effective = NSRange(location: 0, length: 0)
        let kind =
            storage.attribute(
                .marcdownListMarker,
                at: 0,
                longestEffectiveRange: &effective,
                in: NSRange(location: 0, length: storage.length)
            ) as? MarcdownListMarkerKind
        #expect(kind == .bullet)
        #expect(effective == NSRange(location: 0, length: 2))
    }

    @Test func plusBulletProducesIdenticalLayout() {
        let storage = restyle("+ foo")
        let concealedMarker = storage.attribute(.marcdownConcealed, at: 0, effectiveRange: nil) as? Bool
        #expect(concealedMarker != true)
        let markerColor = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(markerColor == NSColor.clear)
        let color = storage.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor
        #expect(color == NSColor.clear)
        var effective = NSRange(location: 0, length: 0)
        let kind =
            storage.attribute(
                .marcdownListMarker,
                at: 0,
                longestEffectiveRange: &effective,
                in: NSRange(location: 0, length: storage.length)
            ) as? MarcdownListMarkerKind
        #expect(kind == .bullet)
        #expect(effective == NSRange(location: 0, length: 2))
    }

    // MARK: - Indented bullet

    @Test func indentedBulletLeadingSpacesAreUntouched() {
        let storage = restyle("  - foo")
        for index in 0...1 {
            let concealed = storage.attribute(.marcdownConcealed, at: index, effectiveRange: nil) as? Bool
            #expect(concealed != true, "expected indent space \(index) to NOT be concealed")
            let marker =
                storage.attribute(.marcdownListMarker, at: index, effectiveRange: nil) as? MarcdownListMarkerKind
            #expect(marker == nil, "expected no list-marker tag at indent position \(index)")
        }
    }

    @Test func indentedBulletDashIsClearPaintedNotConcealed() {
        let storage = restyle("  - foo")
        let concealed = storage.attribute(.marcdownConcealed, at: 2, effectiveRange: nil) as? Bool
        #expect(concealed != true)
        let color = storage.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor
        #expect(color == NSColor.clear)
    }

    @Test func indentedBulletSpaceIsRenderedClear() {
        let storage = restyle("  - foo")
        let color = storage.attribute(.foregroundColor, at: 3, effectiveRange: nil) as? NSColor
        #expect(color == NSColor.clear)
    }

    @Test func indentedBulletMarkerRangeUsesMonospacedFont() {
        let storage = restyle("  - foo")
        for index in 2...3 {
            let font = storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont
            #expect(font != nil, "expected font at position \(index)")
            #expect(
                font?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true,
                "expected monospace at position \(index)")
        }
    }

    /// Indent whitespace sits on the same monospaced grid as the marker so a
    /// tab and two spaces indent by exactly one marker width (see
    /// `IndentNormalisationTests`).
    @Test func indentedBulletLeadingSpacesAreMonospaced() {
        let storage = restyle("  - foo")
        for index in 0...1 {
            let font = storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont
            let isMono = font?.fontDescriptor.symbolicTraits.contains(.monoSpace) ?? false
            #expect(isMono == true, "expected indent space \(index) to be monospace")
        }
    }

    @Test func indentedBulletMarkerTagSpansTwoCharsAfterIndent() {
        let storage = restyle("  - foo")
        var effective = NSRange(location: 0, length: 0)
        let kind =
            storage.attribute(
                .marcdownListMarker,
                at: 2,
                longestEffectiveRange: &effective,
                in: NSRange(location: 0, length: storage.length)
            ) as? MarcdownListMarkerKind
        // 2-space indent → depth 1 (new contract per `NestedBulletDepthTests`).
        #expect(kind == .bullet(depth: 1))
        #expect(effective == NSRange(location: 2, length: 2))
    }

    // MARK: - Bullet empty body

    @Test func emptyBulletMarkerCharIsClearPaintedNotConcealed() {
        let storage = restyle("- ")
        let concealed = storage.attribute(.marcdownConcealed, at: 0, effectiveRange: nil) as? Bool
        #expect(concealed != true)
        let color = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(color == NSColor.clear)
    }

    @Test func emptyBulletSpaceIsRenderedClear() {
        let storage = restyle("- ")
        let color = storage.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor
        #expect(color == NSColor.clear)
    }

    @Test func emptyBulletMarkerTagSpansTwoChars() {
        let storage = restyle("- ")
        var effective = NSRange(location: 0, length: 0)
        let kind =
            storage.attribute(
                .marcdownListMarker,
                at: 0,
                longestEffectiveRange: &effective,
                in: NSRange(location: 0, length: storage.length)
            ) as? MarcdownListMarkerKind
        #expect(kind == .bullet)
        #expect(effective == NSRange(location: 0, length: 2))
    }

    // MARK: - Ordered `.complete`

    @Test func orderedSingleDigitIsRenderedClearNotConcealedAndMonospaced() {
        let storage = restyle("1. foo")
        let concealed = storage.attribute(.marcdownConcealed, at: 0, effectiveRange: nil) as? Bool
        #expect(concealed != true)
        let color = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(color == NSColor.clear)
        let font = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font?.isFixedPitch == true)
    }

    /// The period and trailing space of a complete ordered marker are NOT
    /// concealed — concealment makes glyphs `.null` (zero advance) which
    /// shrinks the marker footprint and lets the `"<N>."` overlay bleed into
    /// body text. Clear-paint + monospaced keeps the marker invisible while
    /// preserving `(digit count + 2)` monospaced advances of breathing room.
    @Test func orderedSingleDigitPeriodIsClearPaintedMonospaced() {
        let storage = restyle("1. foo")
        let concealed = storage.attribute(.marcdownConcealed, at: 1, effectiveRange: nil) as? Bool
        #expect(concealed != true)
        let color = storage.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor
        #expect(color == NSColor.clear)
        let font = storage.attribute(.font, at: 1, effectiveRange: nil) as? NSFont
        #expect(
            font?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true,
            "expected monospace at the period")
    }

    @Test func orderedSingleDigitSpaceIsClearPaintedMonospaced() {
        let storage = restyle("1. foo")
        let concealed = storage.attribute(.marcdownConcealed, at: 2, effectiveRange: nil) as? Bool
        #expect(concealed != true)
        let color = storage.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor
        #expect(color == NSColor.clear)
        let font = storage.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        #expect(
            font?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true,
            "expected monospace at the trailing space")
    }

    @Test func orderedSingleDigitBodyHasNoConcealmentOrMarkerTag() {
        let storage = restyle("1. foo")
        for index in 3..<storage.length {
            let concealed = storage.attribute(.marcdownConcealed, at: index, effectiveRange: nil) as? Bool
            #expect(concealed != true, "expected position \(index) to NOT be concealed")
            let marker =
                storage.attribute(.marcdownListMarker, at: index, effectiveRange: nil) as? MarcdownListMarkerKind
            #expect(marker == nil, "expected no list-marker tag at position \(index)")
        }
    }

    @Test func orderedSingleDigitMarkerTagSpansThreeChars() {
        let storage = restyle("1. foo")
        var effective = NSRange(location: 0, length: 0)
        let kind =
            storage.attribute(
                .marcdownListMarker,
                at: 0,
                longestEffectiveRange: &effective,
                in: NSRange(location: 0, length: storage.length)
            ) as? MarcdownListMarkerKind
        #expect(kind == .ordered(number: 1))
        #expect(effective == NSRange(location: 0, length: 3))
    }

    @Test func orderedTwoDigitDigitsAreClearAndMonospaced() {
        let storage = restyle("10. bar")
        for index in 0...1 {
            let concealed = storage.attribute(.marcdownConcealed, at: index, effectiveRange: nil) as? Bool
            #expect(concealed != true, "expected digit at \(index) to NOT be concealed")
            let color = storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
            #expect(color == NSColor.clear, "expected digit at \(index) to be .clear")
            let font = storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont
            #expect(font?.isFixedPitch == true, "expected digit at \(index) to be monospaced")
        }
    }

    /// Same clear-paint + monospaced treatment as the single-digit case, on
    /// both the period (offset 2) and the trailing space (offset 3) of
    /// `"10. bar"`. Iterating both positions together because they share
    /// the same assertion shape.
    @Test func orderedTwoDigitPeriodAndSpaceAreClearPaintedMonospaced() {
        let storage = restyle("10. bar")
        for index in 2...3 {
            let concealed = storage.attribute(.marcdownConcealed, at: index, effectiveRange: nil) as? Bool
            #expect(concealed != true, "expected position \(index) to NOT be concealed")
            let color = storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
            #expect(color == NSColor.clear, "expected position \(index) to be .clear")
            let font = storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont
            #expect(
                font?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true,
                "expected monospace at position \(index)")
        }
    }

    @Test func orderedTwoDigitMarkerTagSpansFourChars() {
        let storage = restyle("10. bar")
        var effective = NSRange(location: 0, length: 0)
        let kind =
            storage.attribute(
                .marcdownListMarker,
                at: 0,
                longestEffectiveRange: &effective,
                in: NSRange(location: 0, length: storage.length)
            ) as? MarcdownListMarkerKind
        #expect(kind == .ordered(number: 10))
        #expect(effective == NSRange(location: 0, length: 4))
    }

    @Test func orderedNinetyNineMarkerTagCarriesNumber() {
        let storage = restyle("99. baz")
        var effective = NSRange(location: 0, length: 0)
        let kind =
            storage.attribute(
                .marcdownListMarker,
                at: 0,
                longestEffectiveRange: &effective,
                in: NSRange(location: 0, length: storage.length)
            ) as? MarcdownListMarkerKind
        #expect(kind == .ordered(number: 99))
        #expect(effective == NSRange(location: 0, length: 4))
    }

    // MARK: - `.partial` (live-typing feedback)

    /// `"-"` alone is `.partial` for BOTH scanners (it might grow into either
    /// a bullet list or a `- [ ]` checkbox), and per the established
    /// precedence rule the checkbox pass wins. The checkbox `.partial`
    /// branch still uses concealment, so the dash here ends up concealed —
    /// owned by the checkbox pass, not the list pass.
    ///
    /// Note the asymmetry with the ordered partials below: the list pass'
    /// `.partial` branch is a no-op (raw text is shown until the marker is
    /// complete), but it never gets a chance to run on `"-"` because the
    /// checkbox pass took the line first. Concealment here is therefore a
    /// checkbox-pass artefact, not a list-pass one. Both scanners agree
    /// there is no `.marcdownListMarker` tag yet.
    @Test func partialBulletDashIsConcealedWithoutMarkerTag() {
        let storage = restyle("-")
        let concealed = storage.attribute(.marcdownConcealed, at: 0, effectiveRange: nil) as? Bool
        #expect(concealed == true)
        let marker = storage.attribute(.marcdownListMarker, at: 0, effectiveRange: nil) as? MarcdownListMarkerKind
        #expect(marker == nil)
    }

    /// A lone digit (`"1"`) is `.partial` to the list scanner — it might grow
    /// into an ordered marker (`"1. "`) or stay a plain number. The list
    /// pass deliberately leaves partial ordered markers as raw text so the
    /// user sees what they typed until the marker is complete and the
    /// overlay can take over. That means no concealment, no clear-paint,
    /// no monospace forcing, and no `.marcdownListMarker` tag.
    @Test func partialOrderedSingleDigitIsRenderedRawWithoutMarkerTag() {
        let storage = restyle("1")
        let concealed = storage.attribute(.marcdownConcealed, at: 0, effectiveRange: nil) as? Bool
        #expect(concealed != true)
        let font = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(
            font?.fontDescriptor.symbolicTraits.contains(.monoSpace) != true,
            "expected raw (non-monospace) font on a partial ordered marker")
        let marker = storage.attribute(.marcdownListMarker, at: 0, effectiveRange: nil) as? MarcdownListMarkerKind
        #expect(marker == nil)
    }

    /// `"1."` is still `.partial` to the list scanner (no trailing space yet).
    /// Same contract as the single-digit case: render the digit and period
    /// as raw text — no concealment, no monospace forcing, no marker tag —
    /// until the user types the space that completes the marker.
    @Test func partialOrderedDigitPeriodIsRenderedRawWithoutMarkerTag() {
        let storage = restyle("1.")
        for index in 0...1 {
            let concealed = storage.attribute(.marcdownConcealed, at: index, effectiveRange: nil) as? Bool
            #expect(concealed != true, "expected position \(index) to NOT be concealed")
            let font = storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont
            #expect(
                font?.fontDescriptor.symbolicTraits.contains(.monoSpace) != true,
                "expected raw (non-monospace) font at position \(index)")
            let marker =
                storage.attribute(.marcdownListMarker, at: index, effectiveRange: nil) as? MarcdownListMarkerKind
            #expect(marker == nil, "expected no list-marker tag at position \(index)")
        }
    }

    // MARK: - Checkbox precedence

    @Test func checkboxLineIsNotTaggedByListPass() {
        let storage = restyle("- [ ] task")
        for index in 0..<storage.length {
            let marker =
                storage.attribute(.marcdownListMarker, at: index, effectiveRange: nil) as? MarcdownListMarkerKind
            #expect(marker == nil, "expected no list-marker tag at \(index) on a checkbox line")
        }
    }

    @Test func checkboxLineStillCarriesCheckboxState() {
        let storage = restyle("- [ ] task")
        let state = storage.attribute(.marcdownCheckbox, at: 2, effectiveRange: nil) as? MarcdownCheckboxState
        #expect(state != nil)
    }

    // MARK: - Multi-line buffers (paste correctness)

    @Test func multiLineBulletEachDashIsClearPaintedNotConcealed() {
        let storage = restyle("- a\n- b\n- c")
        for index in [0, 4, 8] {
            let concealed = storage.attribute(.marcdownConcealed, at: index, effectiveRange: nil) as? Bool
            #expect(concealed != true, "expected dash at \(index) to NOT be concealed")
            let color = storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
            #expect(color == NSColor.clear, "expected dash at \(index) to be .clear")
        }
    }

    @Test func multiLineBulletEachSpaceIsClear() {
        let storage = restyle("- a\n- b\n- c")
        for index in [1, 5, 9] {
            let color = storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
            #expect(color == NSColor.clear, "expected space at \(index) to be .clear")
        }
    }

    @Test func multiLineBulletHasThreeSeparateMarkerTags() {
        let storage = restyle("- a\n- b\n- c")
        for start in [0, 4, 8] {
            var effective = NSRange(location: 0, length: 0)
            let kind =
                storage.attribute(
                    .marcdownListMarker,
                    at: start,
                    longestEffectiveRange: &effective,
                    in: NSRange(location: 0, length: storage.length)
                ) as? MarcdownListMarkerKind
            #expect(kind == .bullet, "expected .bullet at \(start)")
            #expect(effective == NSRange(location: start, length: 2), "expected 2-char span at \(start)")
        }
    }

    @Test func multiLineOrderedEachDigitIsClearAndMonospaced() {
        let storage = restyle("1. a\n2. b\n3. c")
        for index in [0, 5, 10] {
            let color = storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
            #expect(color == NSColor.clear, "expected digit at \(index) to be .clear")
            let font = storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont
            #expect(font?.isFixedPitch == true, "expected digit at \(index) to be monospaced")
        }
    }

    @Test func multiLineOrderedEachPeriodIsClearPaintedMonospaced() {
        let storage = restyle("1. a\n2. b\n3. c")
        for index in [1, 6, 11] {
            let concealed = storage.attribute(.marcdownConcealed, at: index, effectiveRange: nil) as? Bool
            #expect(concealed != true, "expected period at \(index) to NOT be concealed")
            let color = storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
            #expect(color == NSColor.clear, "expected period at \(index) to be .clear")
            let font = storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont
            #expect(
                font?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true,
                "expected period at \(index) to be monospaced")
        }
    }

    @Test func multiLineOrderedMarkerTagsCarryRunningNumbers() {
        let storage = restyle("1. a\n2. b\n3. c")
        let expected: [(Int, Int)] = [(0, 1), (5, 2), (10, 3)]
        for (start, number) in expected {
            let kind = storage.attribute(.marcdownListMarker, at: start, effectiveRange: nil) as? MarcdownListMarkerKind
            #expect(kind == .ordered(number: number), "expected .ordered(\(number)) at \(start)")
        }
    }

    // MARK: - Mixed-content paste (list + plain + checkbox)

    /// Locks in the paste-correctness contract: a buffer containing a bullet
    /// line, a plain line, a checkbox line, and an ordered line must classify
    /// each line per its own kind. Checkbox precedence holds — the list pass
    /// never tags a checkbox line, but the bullet and ordered lines around it
    /// are tagged correctly.
    @Test func mixedContentEachLineIsClassifiedIndependently() {
        // Offsets:
        //   "- bullet\n"     → 0..<9    (newline at 8)
        //   "plain text\n"   → 9..<20   (newline at 19)
        //   "- [ ] task\n"   → 20..<31  (newline at 30)
        //   "1. ordered"     → 31..<41
        let storage = restyle("- bullet\nplain text\n- [ ] task\n1. ordered")

        // Bullet line: .bullet tag over {0, 2}.
        let bulletKind =
            storage.attribute(.marcdownListMarker, at: 0, effectiveRange: nil)
            as? MarcdownListMarkerKind
        #expect(bulletKind == .bullet)

        // Plain line: no list-marker tag.
        let plainKind =
            storage.attribute(.marcdownListMarker, at: 9, effectiveRange: nil)
            as? MarcdownListMarkerKind
        #expect(plainKind == nil)

        // Checkbox line: no list-marker tag (checkbox precedence) but checkbox state present.
        let checkboxLineKind =
            storage.attribute(.marcdownListMarker, at: 20, effectiveRange: nil)
            as? MarcdownListMarkerKind
        #expect(checkboxLineKind == nil)
        let checkboxState =
            storage.attribute(.marcdownCheckbox, at: 22, effectiveRange: nil)
            as? MarcdownCheckboxState
        #expect(checkboxState != nil)

        // Ordered line: .ordered(1) tag at offset 31.
        let orderedKind =
            storage.attribute(.marcdownListMarker, at: 31, effectiveRange: nil)
            as? MarcdownListMarkerKind
        #expect(orderedKind == .ordered(number: 1))
    }

    // MARK: - Plain-list-no-longer-dimmed regression

    /// The old `dimListMarker` pass painted `theme.dim` over the whole list
    /// item (marker + body); with that pass gone, body text must match the
    /// foreground colour of plain (non-list) text. We can't reach `theme.body`
    /// from the test target, so we compare the bullet body's colour against
    /// the same offset in a plain string — they must be equal.
    @Test func bulletBodyMatchesPlainTextColor() {
        let bulletStorage = restyle("- foo")
        let plainStorage = restyle("foo")

        let bulletBodyColor =
            bulletStorage.attribute(.foregroundColor, at: 3, effectiveRange: nil) as? NSColor
        let plainBodyColor =
            plainStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor

        #expect(bulletBodyColor == plainBodyColor)
    }
}
