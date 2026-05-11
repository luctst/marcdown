import Testing

@testable import MarcdownStyling

@Suite("ListLineScanner")
struct ListLineScannerTests {

    // MARK: - Bullet .complete cases

    @Test func dashBulletIsComplete() {
        #expect(
            ListLineScanner.scan(line: "- foo")
                == .complete(indentLength: 0, markerLength: 2, kind: .bullet)
        )
    }

    @Test func starBulletIsComplete() {
        #expect(
            ListLineScanner.scan(line: "* foo")
                == .complete(indentLength: 0, markerLength: 2, kind: .bullet)
        )
    }

    @Test func plusBulletIsComplete() {
        #expect(
            ListLineScanner.scan(line: "+ foo")
                == .complete(indentLength: 0, markerLength: 2, kind: .bullet)
        )
    }

    @Test func indentedBulletPreservesIndent() {
        // Leading spaces are counted in indentLength; markerLength still 2.
        #expect(
            ListLineScanner.scan(line: "  - foo")
                == .complete(indentLength: 2, markerLength: 2, kind: .bullet)
        )
    }

    // MARK: - Ordered .complete cases

    @Test func singleDigitOrderedIsComplete() {
        #expect(
            ListLineScanner.scan(line: "1. foo")
                == .complete(indentLength: 0, markerLength: 3, kind: .ordered(number: 1))
        )
    }

    @Test func twoDigitOrderedIsComplete() {
        #expect(
            ListLineScanner.scan(line: "10. foo")
                == .complete(indentLength: 0, markerLength: 4, kind: .ordered(number: 10))
        )
    }

    @Test func ninetyNineOrderedIsComplete() {
        #expect(
            ListLineScanner.scan(line: "99. bar")
                == .complete(indentLength: 0, markerLength: 4, kind: .ordered(number: 99))
        )
    }

    // MARK: - .partial cases

    @Test func dashOnlyIsPartial() {
        #expect(
            ListLineScanner.scan(line: "-")
                == .partial(indentLength: 0, markerLength: 1)
        )
    }

    @Test func dashSpaceNoBodyIsComplete() {
        // `- ` with no body content — the marker is fully formed, body is
        // empty. `.complete` so the Enter handler can strip on an empty-body
        // Enter and the styler can apply concealment immediately.
        #expect(
            ListLineScanner.scan(line: "- ")
                == .complete(indentLength: 0, markerLength: 2, kind: .bullet)
        )
    }

    @Test func starOnlyIsPartial() {
        #expect(
            ListLineScanner.scan(line: "*")
                == .partial(indentLength: 0, markerLength: 1)
        )
    }

    @Test func singleDigitOnlyIsPartial() {
        #expect(
            ListLineScanner.scan(line: "1")
                == .partial(indentLength: 0, markerLength: 1)
        )
    }

    @Test func digitDotNoSpaceIsPartial() {
        #expect(
            ListLineScanner.scan(line: "1.")
                == .partial(indentLength: 0, markerLength: 2)
        )
    }

    @Test func digitDotSpaceNoBodyIsComplete() {
        // `1. ` with no body content — fully-formed marker, empty body.
        // `.complete` lets the Enter handler strip on an empty-body Enter and
        // the styler conceal the marker on first keystroke.
        #expect(
            ListLineScanner.scan(line: "1. ")
                == .complete(indentLength: 0, markerLength: 3, kind: .ordered(number: 1))
        )
    }

    // MARK: - .none cases

    @Test func plainTextIsNone() {
        #expect(ListLineScanner.scan(line: "hello") == .none)
    }

    @Test func uncheckedTaskIsNone() {
        // Checkbox lines must be skipped by the list scanner.
        #expect(ListLineScanner.scan(line: "- [ ] task") == .none)
    }

    @Test func checkedTaskIsNone() {
        #expect(ListLineScanner.scan(line: "- [x] done") == .none)
    }

    @Test func parenDelimitedOrderedIsNone() {
        // `1)` is not a supported ordered-list delimiter.
        #expect(ListLineScanner.scan(line: "1) item") == .none)
    }

    @Test func digitDotNoSpaceBeforeTextIsNone() {
        // `1.text` — no space after the period, not a list marker.
        #expect(ListLineScanner.scan(line: "1.text") == .none)
    }

    @Test func emptyLineIsNone() {
        #expect(ListLineScanner.scan(line: "") == .none)
    }
}
