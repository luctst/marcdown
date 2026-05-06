import Foundation
import Testing

@testable import Marcdown

/// Locks down the overlay state machine that drives `PanelRootView`.
/// Issue #1 in the QA report was a focus race caused by ad-hoc Bool flips —
/// these tests guard the documented swap-or-dismiss semantics so a regression
/// in `nextActiveOverlay` is caught at unit-test speed instead of via repro.
@Suite("nextActiveOverlay state machine")
struct PanelOverlayStateTests {
    @Test("Toggling palette from .none opens the palette")
    func paletteFromNoneOpensPalette() {
        #expect(nextActiveOverlay(from: .none, toggle: .palette) == .palette)
    }

    @Test("Toggling palette while palette is open dismisses it")
    func paletteFromPaletteDismisses() {
        #expect(nextActiveOverlay(from: .palette, toggle: .palette) == .none)
    }

    @Test("Toggling palette while switcher is open swaps to palette")
    func paletteFromSwitcherSwapsToPalette() {
        #expect(nextActiveOverlay(from: .switcher, toggle: .palette) == .palette)
    }

    @Test("Toggling switcher from .none opens the switcher")
    func switcherFromNoneOpensSwitcher() {
        #expect(nextActiveOverlay(from: .none, toggle: .switcher) == .switcher)
    }

    @Test("Toggling switcher while switcher is open dismisses it")
    func switcherFromSwitcherDismisses() {
        #expect(nextActiveOverlay(from: .switcher, toggle: .switcher) == .none)
    }

    @Test("Toggling switcher while palette is open swaps to switcher")
    func switcherFromPaletteSwapsToSwitcher() {
        #expect(nextActiveOverlay(from: .palette, toggle: .switcher) == .switcher)
    }
}
