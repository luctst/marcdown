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

@Suite("resolvePanelOrigin fallback")
struct ResolvePanelOriginTests {
    @Test("No saved origin returns nil")
    func noSavedOriginReturnsNil() {
        let screens = [CGRect(x: 0, y: 0, width: 1920, height: 1080)]
        #expect(resolvePanelOrigin(saved: nil, screenVisibleFrames: screens) == nil)
    }

    @Test("Empty screens list returns nil")
    func emptyScreensReturnsNil() {
        // Edge case: app launching before any display has been detected.
        // Caller must center; we have no frame to validate against.
        let saved = CGPoint(x: 100, y: 200)
        #expect(resolvePanelOrigin(saved: saved, screenVisibleFrames: []) == nil)
    }

    @Test("Origin inside the only screen is returned")
    func originInsideSingleScreenIsReturned() {
        let screens = [CGRect(x: 0, y: 0, width: 1920, height: 1080)]
        let saved = CGPoint(x: 100, y: 200)
        #expect(resolvePanelOrigin(saved: saved, screenVisibleFrames: screens) == saved)
    }

    @Test("Origin off-screen returns nil")
    func originOffScreenReturnsNil() {
        // Disconnected-display fallback: the saved point belongs to a monitor
        // that's no longer attached, so we must drop it and let the caller
        // re-center. PM review explicitly called this path out.
        let screens = [CGRect(x: 0, y: 0, width: 1920, height: 1080)]
        let saved = CGPoint(x: -500, y: -500)
        #expect(resolvePanelOrigin(saved: saved, screenVisibleFrames: screens) == nil)
    }

    @Test("Origin on a secondary screen is returned")
    func originOnSecondaryScreenIsReturned() {
        // The bug we're explicitly preventing: treating "not on primary" as
        // "off-screen" would yank multi-monitor users back to the main display
        // every launch.
        let screens = [
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            CGRect(x: 1920, y: 0, width: 1920, height: 1080),
        ]
        let saved = CGPoint(x: 2500, y: 400)
        #expect(resolvePanelOrigin(saved: saved, screenVisibleFrames: screens) == saved)
    }

    @Test("Origin in the gap between screens returns nil")
    func originInGapBetweenScreensReturnsNil() {
        // Primary ends at x=1920, secondary starts at x=3000. The saved point
        // at x=2500 fell inside what used to be a screen but isn't anymore.
        let screens = [
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            CGRect(x: 3000, y: 0, width: 1920, height: 1080),
        ]
        let saved = CGPoint(x: 2500, y: 500)
        #expect(resolvePanelOrigin(saved: saved, screenVisibleFrames: screens) == nil)
    }

    @Test("Point on the max edge is treated as outside")
    func pointOnMaxEdgeIsOutside() {
        // CGRect.contains is half-open: it includes the origin edge but
        // excludes the max edge. A point at exactly (width, 0) is therefore
        // *not* inside a single-screen frame — and falling through to nil is
        // the correct behavior, since that pixel column belongs to the next
        // screen (or to nothing at all).
        let screens = [CGRect(x: 0, y: 0, width: 1920, height: 1080)]
        let saved = CGPoint(x: 1920, y: 0)
        #expect(resolvePanelOrigin(saved: saved, screenVisibleFrames: screens) == nil)
    }
}
