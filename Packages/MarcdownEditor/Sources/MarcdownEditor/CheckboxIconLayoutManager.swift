import AppKit
import MarcdownStyling

/// `NSLayoutManager` subclass that paints a rounded-square checkbox icon over
/// the middle glyph of every `.marcdownCheckbox`-tagged 3-character `[X]`
/// run. The styler conceals the `[` / `]` brackets and paints the middle
/// glyph clear; this layout manager draws the icon in the middle glyph's
/// advance box, anchored to the line fragment rect.
///
/// We deliberately avoid `boundingRect(forGlyphRange:)` for sizing or
/// positioning. With `.null` glyphs flanking the visible middle char,
/// `boundingRect` returns inconsistent geometry across line fragments. Using
/// `lineFragmentRect(forGlyphAt:)` + `location(forGlyphAt:)` yields stable
/// pixel anchors regardless of which glyphs are suppressed.
final class CheckboxIconLayoutManager: NSLayoutManager {
    /// Per-draw deduplication. `drawBackground(forGlyphRange:at:)` is invoked
    /// once per dirty rect; if a marker straddles two dirty rects we'd
    /// otherwise stroke the icon twice. AppKit drawing always happens on the
    /// main thread, so the unchecked annotation is safe in practice.
    private nonisolated(unsafe) var drawnRanges: Set<NSRange> = []

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        drawCheckboxIcons(forGlyphRange: glyphsToShow, at: origin)
    }

    private nonisolated func drawCheckboxIcons(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        drawnRanges.removeAll(keepingCapacity: true)

        guard let storage = textStorage else { return }
        guard glyphsToShow.length > 0 else { return }

        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        guard charRange.length > 0 else { return }

        let storageLength = storage.length
        let upper = min(charRange.location + charRange.length, storageLength)
        var probe = charRange.location
        while probe < upper {
            var effective = NSRange(location: 0, length: 0)
            let value = storage.attribute(
                .marcdownCheckbox,
                at: probe,
                longestEffectiveRange: &effective,
                in: NSRange(location: 0, length: storageLength)
            )
            if let state = value as? MarcdownCheckboxState, effective.length >= 3 {
                let markerRange = NSRange(location: effective.location, length: 3)
                if !drawnRanges.contains(markerRange) {
                    drawnRanges.insert(markerRange)
                    drawIcon(state: state, charRange: markerRange, origin: origin)
                }
            }
            probe = max(probe + 1, effective.location + effective.length)
        }
    }

    private nonisolated func drawIcon(state: MarcdownCheckboxState, charRange: NSRange, origin: NSPoint) {
        let glyphRange = glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        guard glyphRange.length >= 3 else { return }

        let middleGlyph = glyphRange.location + 1
        var lineFragRange = NSRange(location: 0, length: 0)
        let lineFragRect = lineFragmentRect(forGlyphAt: middleGlyph, effectiveRange: &lineFragRange)
        let middleLocation = location(forGlyphAt: middleGlyph)

        // Determine the middle glyph's advance. Prefer the next glyph's
        // location for an exact width; otherwise fall back to `maxSide`.
        let nextGlyph = middleGlyph + 1
        let advanceWidth: CGFloat
        if nextGlyph < lineFragRange.location + lineFragRange.length {
            let nextLocation = location(forGlyphAt: nextGlyph)
            let delta = nextLocation.x - middleLocation.x
            advanceWidth = delta > 0 ? delta : 0
        } else {
            advanceWidth = 0
        }

        let maxSide: CGFloat = 13
        let side = min(lineFragRect.height * 0.65, maxSide)
        let advanceBoxWidth = advanceWidth > 0 ? advanceWidth : side

        // Translate from line-fragment coordinates to view coordinates by
        // adding the textContainerOrigin (`origin` passed in already accounts
        // for that — it is the container origin in the view).
        let glyphX = origin.x + lineFragRect.origin.x + middleLocation.x
        let lineY = origin.y + lineFragRect.origin.y

        let iconX = glyphX + (advanceBoxWidth - side) / 2
        let iconY = lineY + (lineFragRect.height - side) / 2
        let rect = NSRect(x: iconX, y: iconY, width: side, height: side)

        let path = NSBezierPath(roundedRect: rect, xRadius: side * 0.25, yRadius: side * 0.25)
        let accent = NSColor.controlAccentColor
        switch state {
        case .unchecked:
            accent.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        case .checked:
            accent.setFill()
            path.fill()
        }
    }
}
