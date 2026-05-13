import AppKit
import MarcdownStyling

/// `NSLayoutManager` subclass that paints overlay glyphs for two attribute
/// runs the styler tags:
///
/// - `.marcdownCheckbox` — a rounded-square icon over the middle glyph of a
///   3-character `[ ]` / `[x]` / `[X]` marker.
/// - `.marcdownListMarker` — a filled bullet circle (for `.bullet`) or an
///   accent-coloured `"<N>."` string (for `.ordered(number:)`) over the
///   concealed/clear-painted source glyphs of a plain list marker.
///
/// We deliberately avoid `boundingRect(forGlyphRange:)` for sizing or
/// positioning. With `.null` glyphs flanking the visible anchor char(s),
/// `boundingRect` returns inconsistent geometry across line fragments. Using
/// `lineFragmentRect(forGlyphAt:)` + `location(forGlyphAt:)` yields stable
/// pixel anchors regardless of which glyphs are suppressed.
final class CheckboxIconLayoutManager: NSLayoutManager {
    /// Per-draw deduplication for checkbox icons. `drawBackground(forGlyphRange:at:)`
    /// is invoked once per dirty rect; if a marker straddles two dirty rects
    /// we'd otherwise stroke the icon twice. AppKit drawing always happens on
    /// the main thread, so the unchecked annotation is safe in practice.
    private nonisolated(unsafe) var drawnRanges: Set<NSRange> = []

    /// Per-draw deduplication for list markers. Kept separate from
    /// `drawnRanges` so each sub-walk's bookkeeping is fully independent —
    /// avoids any range-collision reasoning between checkbox (length 3) and
    /// list-marker (length 2 for bullet, length ≥ 3 for ordered) keys. AppKit
    /// drawing always happens on the main thread, so the unchecked annotation
    /// is safe in practice.
    private nonisolated(unsafe) var drawnListRanges: Set<NSRange> = []

    /// Per-draw deduplication for code-block containers. A fenced block can
    /// straddle multiple dirty rects; without this set we'd fill the rounded
    /// rect twice and the overlap would visibly darken. AppKit drawing always
    /// happens on the main thread, so the unchecked annotation is safe in
    /// practice.
    private nonisolated(unsafe) var drawnCodeBlockRanges: Set<NSRange> = []

    /// Fill color for the rounded code-block container. Set by the editor's
    /// `makeNSView` from the same `StylingTheme` the styler uses so the
    /// container matches the rest of the palette. `NSColor` is `Sendable`,
    /// so this stays clean under Swift 6. Falls back to a neutral gray
    /// when unset (preserves usability for tests / previews).
    nonisolated(unsafe) var codeBlockFillColor: NSColor?

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        // Code-block container is drawn first so checkbox + list-marker
        // overlays render on top if they ever coincide (defensive — they
        // shouldn't overlap in practice, but the icons are interactive UI
        // and must never be visually clipped by a background fill).
        drawCodeBlockBackgrounds(forGlyphRange: glyphsToShow, at: origin)
        drawCheckboxIcons(forGlyphRange: glyphsToShow, at: origin)
        drawListMarkers(forGlyphRange: glyphsToShow, at: origin)
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

    // MARK: - List markers

    private nonisolated func drawListMarkers(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        drawnListRanges.removeAll(keepingCapacity: true)

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
                .marcdownListMarker,
                at: probe,
                longestEffectiveRange: &effective,
                in: NSRange(location: 0, length: storageLength)
            )
            if let kind = value as? MarcdownListMarkerKind {
                let markerRange = effective
                if !drawnListRanges.contains(markerRange) {
                    drawnListRanges.insert(markerRange)
                    switch kind {
                    case .bullet:
                        drawBullet(charRange: markerRange, origin: origin)
                    case .ordered(let number):
                        drawOrderedNumber(number: number, charRange: markerRange, origin: origin)
                    }
                }
            }
            probe = max(probe + 1, effective.location + effective.length)
        }
    }

    /// Draws a filled circle in the first marker glyph's advance box. The
    /// 2-char marker is `<dash><space>`; both glyphs are `.clear`-painted by
    /// the styler with a forced monospaced font so each contributes a stable,
    /// wide advance. We anchor on the first (dash) glyph and centre the
    /// circle inside its advance box — the icon may bleed slightly past the
    /// dash's right edge, but only into the (invisible) space glyph's slot,
    /// never into the body text.
    private nonisolated func drawBullet(charRange: NSRange, origin: NSPoint) {
        guard charRange.length == 2 else { return }

        let glyphRange = glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        guard glyphRange.length >= 2 else { return }

        // Anchor on the first marker glyph (the dash). Both glyphs are
        // `.clear`-painted with a monospaced font, so glyph[1] - glyph[0]
        // gives us the dash's true advance width.
        let firstGlyph = glyphRange.location
        var lineFragRange = NSRange(location: 0, length: 0)
        let lineFragRect = lineFragmentRect(forGlyphAt: firstGlyph, effectiveRange: &lineFragRange)
        let firstLocation = location(forGlyphAt: firstGlyph)

        let secondLocation = location(forGlyphAt: firstGlyph + 1)
        let advance = secondLocation.x - firstLocation.x

        let maxSide: CGFloat = 13
        let side = min(lineFragRect.height * 0.65, maxSide)
        let advanceBoxWidth = advance > 0 ? advance : side

        let glyphX = origin.x + lineFragRect.origin.x + firstLocation.x
        let lineY = origin.y + lineFragRect.origin.y

        let iconX = glyphX + (advanceBoxWidth - side) / 2
        let iconY = lineY + (lineFragRect.height - side) / 2
        let rect = NSRect(x: iconX, y: iconY, width: side, height: side)

        let path = NSBezierPath(ovalIn: rect)
        NSColor.controlAccentColor.setFill()
        path.fill()
    }

    /// Draws `"<N>."` anchored at the first digit's baseline, at the overlay
    /// font's natural width. The marker layout is `<digits>.<space>`; all
    /// marker chars are `.clear`-painted with a forced monospaced font by the
    /// styler so the marker footprint is wide enough to host the overlay
    /// without bleeding into body text.
    ///
    /// We use `NSAttributedString`-style `.draw(at:)` rather than
    /// `.draw(in:withAttributes:)` because the rect form top-aligns the text
    /// inside the rect, causing the overlay to float above the body baseline.
    /// `.draw(at:)` interprets the point as the top-left of the text rect, so
    /// we convert the baseline-relative location returned by
    /// `location(forGlyphAt:)` into a top-left point by subtracting the font's
    /// ascender.
    private nonisolated func drawOrderedNumber(number: Int, charRange: NSRange, origin: NSPoint) {
        // markerLength = digits + 2 (`.` + space).
        let digitCount = charRange.length - 2
        guard digitCount > 0 else { return }

        let glyphRange = glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        guard glyphRange.length >= digitCount else { return }

        let firstDigitGlyph = glyphRange.location
        let lineFragRect = lineFragmentRect(forGlyphAt: firstDigitGlyph, effectiveRange: nil)
        let firstDigitLocation = location(forGlyphAt: firstDigitGlyph)

        // Match the body text's font size so the overlay sits on the same
        // baseline rhythm as surrounding content. Using `.systemFontSize`
        // would be wrong for an editor whose base font differs; query a
        // representative glyph's font from the storage instead.
        let fontSize = orderedOverlayFontSize(forGlyphAt: firstDigitGlyph)
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

        // `location(forGlyphAt:)` returns a y at the BASELINE relative to the
        // line fragment. `.draw(at:)` interprets its point as the TOP-LEFT of
        // the text rect — convert by subtracting the font ascender.
        let glyphX = origin.x + lineFragRect.origin.x + firstDigitLocation.x
        let baselineY = origin.y + lineFragRect.origin.y + firstDigitLocation.y
        let drawY = baselineY - font.ascender
        let drawPoint = NSPoint(x: glyphX, y: drawY)

        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.controlAccentColor,
            .font: font,
        ]

        let text = "\(number)."
        text.draw(at: drawPoint, withAttributes: attributes)
    }

    /// Returns the point size to use for the ordered-number overlay. Reads
    /// the font attribute the styler wrote on the digit char to honour any
    /// theme or zoom adjustment. Falls back to the system body size.
    private nonisolated func orderedOverlayFontSize(forGlyphAt glyphIndex: Int) -> CGFloat {
        let charIndex = characterIndexForGlyph(at: glyphIndex)
        guard let storage = textStorage, charIndex < storage.length else {
            return NSFont.systemFontSize
        }
        if let font = storage.attribute(.font, at: charIndex, effectiveRange: nil) as? NSFont {
            return font.pointSize
        }
        return NSFont.systemFontSize
    }

    // MARK: - Code block container

    /// Paints a single rounded rect behind each `.marcdownCodeBlock` run.
    /// The container hugs the text container's width (minus a small inset)
    /// rather than wrapping the text glyphs, mimicking the Raycast Notes
    /// look. Runs once per draw cycle per block via `drawnCodeBlockRanges`.
    private nonisolated func drawCodeBlockBackgrounds(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        drawnCodeBlockRanges.removeAll(keepingCapacity: true)

        guard let storage = textStorage else { return }
        guard let container = textContainers.first else { return }
        guard glyphsToShow.length > 0 else { return }

        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        guard charRange.length > 0 else { return }

        let storageLength = storage.length
        let upper = min(charRange.location + charRange.length, storageLength)

        // Container geometry. `containerSize.width` reflects the text view's
        // current laid-out width when `widthTracksTextView` is true.
        let containerWidth = container.size.width
        // The rounded rect spans the full content width — internal breathing
        // room comes from the paragraph-style indents the styler sets on the
        // code block, not from narrowing the rect.
        let horizontalInset: CGFloat = 0
        let cornerRadius: CGFloat = 6

        let fillColor = codeBlockFillColor ?? NSColor.gray.withAlphaComponent(0.10)

        var probe = charRange.location
        while probe < upper {
            var effective = NSRange(location: 0, length: 0)
            let value = storage.attribute(
                .marcdownCodeBlock,
                at: probe,
                longestEffectiveRange: &effective,
                in: NSRange(location: 0, length: storageLength)
            )
            if let flag = value as? Bool, flag, effective.length > 0 {
                if !drawnCodeBlockRanges.contains(effective) {
                    drawnCodeBlockRanges.insert(effective)

                    let blockGlyphRange = glyphRange(
                        forCharacterRange: effective,
                        actualCharacterRange: nil
                    )
                    if blockGlyphRange.length > 0 {
                        let bounding = boundingRect(
                            forGlyphRange: blockGlyphRange,
                            in: container
                        )
                        // Translate into view coordinates and stretch to
                        // full container width minus inset. The vertical
                        // extent is whatever the glyphs occupied — for an
                        // empty fenced block this is still the two fence
                        // lines' height, so the container remains visible.
                        // Expand the bounding rect by 6pt top and 6pt bottom
                        // so the fence lines have breathing room inside the
                        // rounded container rather than sitting flush against
                        // its edges. Horizontal breathing room is provided by
                        // the paragraph-style indents on the code block run.
                        var rect = NSRect(
                            x: origin.x + horizontalInset,
                            y: origin.y + bounding.origin.y,
                            width: max(0, containerWidth - horizontalInset * 2),
                            height: bounding.height
                        )
                        rect.origin.y -= 6
                        rect.size.height += 12
                        if rect.width > 0, rect.height > 0 {
                            let path = NSBezierPath(
                                roundedRect: rect,
                                xRadius: cornerRadius,
                                yRadius: cornerRadius
                            )
                            fillColor.setFill()
                            path.fill()
                        }
                    }
                }
            }
            probe = max(probe + 1, effective.location + effective.length)
        }
    }
}
