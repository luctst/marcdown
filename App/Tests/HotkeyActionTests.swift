import Foundation
import Testing

@testable import Marcdown

/// Locks down the global-hotkey decision logic that replaces the old
/// `panel.isVisible`-based toggle. The bug we're explicitly preventing:
/// a user drafting in Marcdown tabs to Safari, hits the hotkey to come
/// back, and the old logic *hides* the still-visible panel instead of
/// bringing it to key. See spec `foreground-and-focus.md` §2.
@Suite("nextHotkeyAction")
struct HotkeyActionTests {
    @Test("Hidden panel → show")
    func hiddenPanelShows() {
        // Cold-start case: nothing on screen, hotkey must summon the panel.
        #expect(nextHotkeyAction(isVisible: false, isKey: false) == .show)
    }

    @Test("Visible but not key → bringToKey")
    func visibleButNotKeyBringsToKey() {
        // User is in Safari with Marcdown still floating in the background.
        // Hotkey must reactivate the app and key the panel — never hide it.
        // This is the exact regression that motivated the spec.
        #expect(nextHotkeyAction(isVisible: true, isKey: false) == .bringToKey)
    }

    @Test("Visible and key → hide")
    func visibleAndKeyHides() {
        // Panel is focused and the user wants to dismiss it; hotkey doubles
        // as the "tuck away and restore previous app" action.
        #expect(nextHotkeyAction(isVisible: true, isKey: true) == .hide)
    }

    @Test("Impossible state (not visible but key) defaults to show")
    func impossibleStateDefaultsToShow() {
        // AppKit cannot produce a keyed-but-invisible window, but defensive
        // mapping keeps the hotkey from crashing or no-oping if state
        // observation lags behind reality. Prefer the "make panel visible"
        // path over hiding something the user can't see.
        #expect(nextHotkeyAction(isVisible: false, isKey: true) == .show)
    }
}

/// Locks down when the footer's "esc to close" hint is shown. The hint must
/// only appear when ESC actually does what it says — i.e. the panel is key
/// and no overlay is active. Overlays own their own ESC semantics (palette
/// sub-mode pop, switcher dismiss) so showing the hint over them would lie
/// to the user. Hint is also wrong when the panel isn't key, since ESC
/// won't reach us. See spec `foreground-and-focus.md` §5.
@Suite("shouldShowEscHint visibility")
struct ShouldShowEscHintTests {
    @Test("No overlay + panel is key → visible")
    func noOverlayAndKeyShowsHint() {
        #expect(shouldShowEscHint(activeOverlay: .none, panelIsKey: true) == true)
    }

    @Test("No overlay + panel not key → hidden")
    func noOverlayButNotKeyHidesHint() {
        // User clicked Safari; ESC there won't dismiss our panel, so the
        // hint would be a lie if we kept it on screen.
        #expect(shouldShowEscHint(activeOverlay: .none, panelIsKey: false) == false)
    }

    @Test("Palette overlay active → hidden")
    func paletteOverlayHidesHint() {
        // Palette's ESC pops sub-modes / dismisses itself, not the panel.
        #expect(shouldShowEscHint(activeOverlay: .palette, panelIsKey: true) == false)
    }

    @Test("Switcher overlay active → hidden")
    func switcherOverlayHidesHint() {
        // Switcher's ESC dismisses the switcher; hint would mis-describe it.
        #expect(shouldShowEscHint(activeOverlay: .switcher, panelIsKey: true) == false)
    }

    @Test("Both flags off → hidden (smoke)")
    func bothFlagsOffHidesHint() {
        // Smoke case: neither precondition met; nothing should render.
        #expect(shouldShowEscHint(activeOverlay: .palette, panelIsKey: false) == false)
    }
}
