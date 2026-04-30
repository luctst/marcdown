import Foundation
import Testing
@testable import Marcdown

@Suite("computeMaxWidth clamp")
struct PanelControllerTests {
    @Test("Caps at maxWidth on a wide screen")
    func wideScreenIsCappedAtMaxWidth() {
        // 1920 - 16 = 1904, well above the 720 hard cap.
        #expect(computeMaxWidth(screenWidth: 1920) == PanelSizeConstraints.maxWidth)
    }

    @Test("Subtracts margin on a tight screen between min and max")
    func tightScreenSubtractsMargin() {
        // 600 - 16 = 584, sits between minWidth (400) and maxWidth (720),
        // so the margin-clamped value wins.
        #expect(computeMaxWidth(screenWidth: 600) == 584)
    }

    @Test("Floors at minWidth so max never falls below min")
    func narrowScreenIsFlooredAtMinWidth() {
        // 200 - 16 = 184, which is below minWidth (400). AppKit crashes if
        // maxSize.width < minSize.width, so the floor is a real correctness
        // invariant — never let it regress.
        #expect(computeMaxWidth(screenWidth: 200) == PanelSizeConstraints.minWidth)
    }

    @Test("Boundary at exactly maxWidth + margin returns maxWidth")
    func boundaryAtMaxWidthPlusMargin() {
        // 736 - 16 = 720 == maxWidth. Both candidates equal, result is maxWidth.
        #expect(computeMaxWidth(screenWidth: 736) == PanelSizeConstraints.maxWidth)
    }

    @Test("Boundary just below maxWidth + margin returns screenWidth - margin")
    func boundaryJustBelowMaxWidthPlusMargin() {
        // 735 - 16 = 719, one unit below the cap; margin clamp wins by 1.
        #expect(computeMaxWidth(screenWidth: 735) == 719)
    }
}
