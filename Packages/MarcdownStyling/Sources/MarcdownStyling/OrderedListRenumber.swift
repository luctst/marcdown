import Foundation

/// Outcome of an ordered-list renumber pass. Pure helper, buffer-relative.
public enum RenumberOutcome: Sendable, Equatable {
    /// No rewrite needed (anchor not on an ordered line, or the run is
    /// already consecutive starting from its first item's number).
    case noOp
    /// Replace the entire buffer with `newBuffer` and place the cursor at
    /// `newCursorOffset`. Callers translate this into a single
    /// `replaceCharacters(in:)` covering just the run for minimal redraw.
    case rewrite(newBuffer: String, newCursorOffset: Int)
}

/// Renumbers the contiguous ordered-list run that contains a given anchor
/// line. A "run" is the maximal consecutive sequence of lines whose
/// `ListLineScanner` shape is `.complete(.ordered)` AND share the same
/// `indentLength` as the anchor line. The first number is preserved; each
/// subsequent item is renumbered to `firstNumber + i`.
///
/// Spec §5.3 / §5.4: invoked by the editor coordinator after Enter, Backspace,
/// Tab, or Shift-Tab on an ordered item to keep the visible numbering in sync.
public enum OrderedListRenumber {

    public static func renumberRun(
        buffer: String,
        anchorOffset: Int,
        cursorOffset: Int
    ) -> RenumberOutcome {
        let units = Array(buffer.utf16)
        let length = units.count
        guard anchorOffset >= 0, anchorOffset <= length else { return .noOp }

        // 1. Identify the anchor line and its ordered metadata.
        guard let anchor = orderedLineMetadata(units: units, offset: anchorOffset) else {
            return .noOp
        }

        // 2. Walk backward. Stop on any line that is not ordered-at-anchor-depth
        //    AND not a strictly-deeper list/task line (nested children are
        //    "owned" by the run and skipped over, not break-points).
        var runLineStarts: [Int] = [anchor.lineStart]
        var cursor = anchor.lineStart
        while cursor > 0 {
            let prevLineEnd = cursor - 1
            guard prevLineEnd >= 0 else { break }
            let prevLineStart = scanLineStart(units: units, endOffset: prevLineEnd)
            let walk = walkClassification(
                units: units,
                lineStart: prevLineStart,
                lineEnd: prevLineEnd,
                anchorIndent: anchor.indentLength
            )
            switch walk {
            case .matches:
                runLineStarts.append(prevLineStart)
                cursor = prevLineStart
            case .skipNested:
                cursor = prevLineStart
            case .breaks:
                break
            }
            if case .breaks = walk { break }
        }
        runLineStarts.reverse()

        // 3. Walk forward with the same classification.
        var lookahead = anchor.lineEnd
        while lookahead < length {
            guard units[lookahead] == 0x0A else { break }
            let nextStart = lookahead + 1
            guard nextStart <= length else { break }
            let nextEnd = scanLineEnd(units: units, startOffset: nextStart)
            let walk = walkClassification(
                units: units,
                lineStart: nextStart,
                lineEnd: nextEnd,
                anchorIndent: anchor.indentLength
            )
            switch walk {
            case .matches:
                runLineStarts.append(nextStart)
                lookahead = nextEnd
            case .skipNested:
                lookahead = nextEnd
            case .breaks:
                break
            }
            if case .breaks = walk { break }
        }

        // 4. Compute the new numbers. Preserve the first line's number.
        guard let firstStart = runLineStarts.first,
            let firstMeta = orderedLineMetadata(
                units: units, lineStart: firstStart, lineEnd: scanLineEnd(units: units, startOffset: firstStart))
        else { return .noOp }

        let firstNumber = firstMeta.number

        // 5. Build the new buffer in one pass. Compute cursor delta along the
        //    way so we don't have to re-scan.
        var newUnits: [UInt16] = []
        newUnits.reserveCapacity(units.count)
        var changed = false
        var cursorDelta = 0
        var cursorAdjusted = cursorOffset

        var writeIndex = 0
        for (i, lineStart) in runLineStarts.enumerated() {
            let expectedNumber = firstNumber + i
            // Copy untouched units up to this line's start.
            if writeIndex < lineStart {
                newUnits.append(contentsOf: units[writeIndex..<lineStart])
                writeIndex = lineStart
            }
            // Decode the metadata for this line.
            let lineEnd = scanLineEnd(units: units, startOffset: lineStart)
            guard let meta = orderedLineMetadata(units: units, lineStart: lineStart, lineEnd: lineEnd) else {
                continue
            }
            // Emit indent unchanged.
            if meta.indentLength > 0 {
                newUnits.append(contentsOf: units[lineStart..<(lineStart + meta.indentLength)])
            }
            // Emit the new digit string.
            let oldDigitCount = meta.digitCount
            let newDigitString = "\(expectedNumber)"
            let newDigitUnits = Array(newDigitString.utf16)
            let newDigitCount = newDigitUnits.count
            newUnits.append(contentsOf: newDigitUnits)
            if expectedNumber != meta.number {
                changed = true
            }
            if newDigitCount != oldDigitCount {
                changed = true
                let widthDelta = newDigitCount - oldDigitCount
                let digitsEndInOriginal = lineStart + meta.indentLength + oldDigitCount
                // Cursor adjustments:
                if cursorOffset >= digitsEndInOriginal {
                    // Cursor is past the digit run on this or a later line —
                    // shift by the full width delta.
                    cursorAdjusted += widthDelta
                } else if cursorOffset > lineStart + meta.indentLength {
                    // Cursor is INSIDE the digit run that grew/shrunk —
                    // snap to the body-start of this item.
                    cursorAdjusted = lineStart + meta.indentLength + newDigitCount + 2  // `. `
                }
                cursorDelta += widthDelta
            }
            // Emit the `. ` and the rest of the line content (body).
            let bodyStart = lineStart + meta.indentLength + oldDigitCount
            let lineEndOrig = lineEnd
            newUnits.append(contentsOf: units[bodyStart..<lineEndOrig])
            writeIndex = lineEndOrig
        }
        // Append any trailing content past the final processed line.
        if writeIndex < units.count {
            newUnits.append(contentsOf: units[writeIndex..<units.count])
        }

        guard changed else { return .noOp }

        let newBuffer = newUnits.withUnsafeBufferPointer {
            String(utf16CodeUnits: $0.baseAddress!, count: $0.count)
        }
        // Final cursor clamp.
        let newLength = newUnits.count
        let clampedCursor = max(0, min(newLength, cursorAdjusted))
        return .rewrite(newBuffer: newBuffer, newCursorOffset: clampedCursor)
    }

    // MARK: - Walk classification

    private enum WalkClassification {
        /// Ordered line at exactly the anchor's indent — part of the run.
        case matches
        /// List/task line at strictly deeper indent — a nested sublist that
        /// "belongs" to the run; skipped over but does not break the run.
        case skipNested
        /// Anything else: plain text, bullet-at-anchor-depth, ordered-at-shallower-depth.
        case breaks
    }

    private static func walkClassification(
        units: [UInt16],
        lineStart: Int,
        lineEnd: Int,
        anchorIndent: Int
    ) -> WalkClassification {
        guard lineEnd >= lineStart else { return .breaks }
        let line = Array(units[lineStart..<lineEnd]).withUnsafeBufferPointer {
            String(utf16CodeUnits: $0.baseAddress!, count: $0.count)
        }
        // An empty line (no content) always breaks the run — matches
        // CommonMark's blank-line-ends-tight-list behaviour.
        if line.isEmpty { return .breaks }

        // Try ordered first.
        if case .complete(let indent, _, .ordered) = ListLineScanner.scan(line: line) {
            if indent == anchorIndent { return .matches }
            if indent > anchorIndent { return .skipNested }
            return .breaks
        }
        // Check bullet / partial list lines.
        switch ListLineScanner.scan(line: line) {
        case .complete(let indent, _, _):
            // Bullet at anchor depth breaks the run.
            if indent > anchorIndent { return .skipNested }
            return .breaks
        case .partial(let indent, _):
            if indent > anchorIndent { return .skipNested }
            return .breaks
        case .none:
            break
        }
        // Check task lines.
        switch CheckboxLineScanner.scan(line: line) {
        case .complete(let indent, _, _):
            if indent > anchorIndent { return .skipNested }
            return .breaks
        case .partial(let indent, _):
            if indent > anchorIndent { return .skipNested }
            return .breaks
        case .none:
            return .breaks
        }
    }

    // MARK: - Metadata extraction

    private struct OrderedLineMeta {
        let lineStart: Int
        let lineEnd: Int
        let indentLength: Int
        let digitCount: Int
        let number: Int
    }

    /// Locate the line containing `offset` and decode its ordered-list metadata,
    /// if any.
    private static func orderedLineMetadata(units: [UInt16], offset: Int) -> OrderedLineMeta? {
        let lineStart = scanLineStart(units: units, endOffset: offset)
        let lineEnd = scanLineEnd(units: units, startOffset: lineStart)
        return orderedLineMetadata(units: units, lineStart: lineStart, lineEnd: lineEnd)
    }

    /// Decode the ordered-list metadata for an already-located line.
    private static func orderedLineMetadata(units: [UInt16], lineStart: Int, lineEnd: Int) -> OrderedLineMeta? {
        guard lineEnd >= lineStart else { return nil }
        let line = Array(units[lineStart..<lineEnd]).withUnsafeBufferPointer {
            String(utf16CodeUnits: $0.baseAddress!, count: $0.count)
        }
        switch ListLineScanner.scan(line: line) {
        case .complete(let indent, let markerLength, .ordered(let number, _)):
            return OrderedLineMeta(
                lineStart: lineStart,
                lineEnd: lineEnd,
                indentLength: indent,
                digitCount: markerLength - 2,  // markerLength = digits + `.` + space
                number: number
            )
        default:
            return nil
        }
    }

    // MARK: - Line boundary scans

    private static func scanLineStart(units: [UInt16], endOffset: Int) -> Int {
        var probe = max(0, min(endOffset, units.count))
        while probe > 0, units[probe - 1] != 0x0A {
            probe -= 1
        }
        return probe
    }

    private static func scanLineEnd(units: [UInt16], startOffset: Int) -> Int {
        var probe = max(0, min(startOffset, units.count))
        while probe < units.count, units[probe] != 0x0A {
            probe += 1
        }
        return probe
    }
}
