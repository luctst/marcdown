import AppKit
import MarcdownStyling

/// `NSLayoutManagerDelegate` that suppresses glyphs whose backing characters
/// are tagged with `NSAttributedString.Key.marcdownConcealed`. Glyphs are
/// suppressed by OR-ing `.null` into their `GlyphProperty` flags before they
/// reach layout.
///
/// The disk file remains the source of truth — characters are never
/// removed from `NSTextStorage`. The reveal-on-cursor behavior is achieved
/// by the styler stripping the `.marcdownConcealed` flag from the active
/// line; this delegate just trusts whatever is currently in storage.
@MainActor
final class ConcealmentLayoutDelegate: NSObject, NSLayoutManagerDelegate {
    nonisolated func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes: UnsafePointer<Int>,
        font: NSFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        guard let storage = layoutManager.textStorage else {
            // No storage to query — pass through unchanged. Returning 0 keeps
            // the layout system on its default path.
            return 0
        }

        // Copy the input properties into a mutable buffer we can edit.
        var modified = [NSLayoutManager.GlyphProperty](
            UnsafeBufferPointer(start: properties, count: glyphRange.length)
        )

        // Walk character-attribute runs of `.marcdownConcealed`, not glyphs,
        // so we amortize the attribute lookup. For each run that's flagged
        // concealed, mark every glyph whose char index falls in that run.
        let storageLength = storage.length
        let glyphCount = glyphRange.length
        var cursor = 0
        while cursor < glyphCount {
            let charIndex = characterIndexes[cursor]
            // Defensive bound — characterIndexes should be in [0, storage.length)
            // but layout sometimes hands us trailing markers.
            guard charIndex >= 0, charIndex < storageLength else {
                cursor += 1
                continue
            }

            var effective = NSRange(location: 0, length: 0)
            let value = storage.attribute(
                .marcdownConcealed,
                at: charIndex,
                longestEffectiveRange: &effective,
                in: NSRange(location: 0, length: storageLength)
            )

            if let flag = value as? Bool, flag {
                let runEnd = effective.location + effective.length
                // Mark all subsequent glyphs whose character index is still
                // inside this concealed run.
                var probe = cursor
                while probe < glyphCount {
                    let probeChar = characterIndexes[probe]
                    if probeChar >= effective.location, probeChar < runEnd {
                        modified[probe].insert(.null)
                        probe += 1
                    } else {
                        break
                    }
                }
                cursor = probe
            } else {
                // Skip ahead over the entire un-concealed run.
                let runEnd = effective.location + effective.length
                var probe = cursor + 1
                while probe < glyphCount {
                    let probeChar = characterIndexes[probe]
                    if probeChar >= effective.location, probeChar < runEnd {
                        probe += 1
                    } else {
                        break
                    }
                }
                cursor = probe
            }
        }

        modified.withUnsafeBufferPointer { buffer in
            layoutManager.setGlyphs(
                glyphs,
                properties: buffer.baseAddress!,
                characterIndexes: characterIndexes,
                font: font,
                forGlyphRange: glyphRange
            )
        }
        return glyphCount
    }
}
