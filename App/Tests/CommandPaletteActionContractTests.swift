import Foundation
import Testing

@testable import Marcdown

/// Locks down the contract: each `PaletteAction` handler is solely responsible
/// for the overlay state after it runs. `CommandPalette.commitSelection` and
/// the row tap gesture must NOT chain a dismissal after `handler()` — if they
/// do, the "Browse Notes" action's switch to `.switcher` gets clobbered back
/// to `.none` (see fix/panel-action-bugs).
///
/// Each test invokes a handler directly, in isolation, and asserts the final
/// overlay state. A regression that re-introduces a chained `onDismiss()` in
/// `CommandPalette` would have to also revert these handlers' explicit
/// `setOverlay(.none)` calls to keep these tests passing — and the
/// "browse-notes" assertion in particular fails the moment anything overrides
/// the handler's intent with `.none`.
@MainActor
@Suite("PaletteAction handler -> ActiveOverlay contract")
struct CommandPaletteActionContractTests {
    /// Spies on the overlay state mutated by handlers. Other side effects
    /// (newNote, duplicate, delete, prev, next, triggerFind) are stubbed with
    /// no-ops because this contract only covers the post-action overlay value.
    private func makeActions(capturing observed: Observed) -> [PaletteAction] {
        makePaletteActions(
            setOverlay: { observed.overlay = $0 },
            newNote: {},
            triggerFind: {},
            duplicate: {},
            delete: {},
            prev: {},
            next: {}
        )
    }

    private func handler(for id: String, in actions: [PaletteAction]) -> (@MainActor () -> Void)? {
        actions.first(where: { $0.id == id })?.handler
    }

    @Test("new-note handler dismisses the overlay")
    func newNoteDismissesOverlay() {
        let observed = Observed()
        let actions = makeActions(capturing: observed)

        handler(for: "new-note", in: actions)?()

        #expect(observed.overlay == .none)
    }

    /// THE REGRESSION TEST. Before fix/panel-action-bugs, pressing Enter on
    /// "Browse Notes" left `activeOverlay == .none` because `commitSelection`
    /// chained `onDismiss()` after `handler()`. The handler under test must
    /// produce `.switcher` so that the only way to break it is to either
    /// re-introduce a chained dismiss in the call site or change the handler's
    /// own intent — both of which this assertion catches.
    @Test("browse-notes handler opens the switcher overlay")
    func browseNotesOpensSwitcher() {
        let observed = Observed()
        let actions = makeActions(capturing: observed)

        handler(for: "browse-notes", in: actions)?()

        #expect(observed.overlay == .switcher)
    }

    @Test("find handler dismisses the overlay")
    func findDismissesOverlay() {
        let observed = Observed()
        let actions = makeActions(capturing: observed)

        handler(for: "find", in: actions)?()

        #expect(observed.overlay == .none)
    }

    @Test("duplicate handler dismisses the overlay")
    func duplicateDismissesOverlay() {
        let observed = Observed()
        let actions = makeActions(capturing: observed)

        handler(for: "duplicate", in: actions)?()

        #expect(observed.overlay == .none)
    }

    @Test("delete handler dismisses the overlay")
    func deleteDismissesOverlay() {
        let observed = Observed()
        let actions = makeActions(capturing: observed)

        handler(for: "delete", in: actions)?()

        #expect(observed.overlay == .none)
    }

    @Test("prev-note handler dismisses the overlay")
    func prevNoteDismissesOverlay() {
        let observed = Observed()
        let actions = makeActions(capturing: observed)

        handler(for: "prev-note", in: actions)?()

        #expect(observed.overlay == .none)
    }

    @Test("next-note handler dismisses the overlay")
    func nextNoteDismissesOverlay() {
        let observed = Observed()
        let actions = makeActions(capturing: observed)

        handler(for: "next-note", in: actions)?()

        #expect(observed.overlay == .none)
    }

    /// Reference-type spy so the @MainActor closure can mutate observed state
    /// without `inout` capture gymnastics.
    @MainActor
    private final class Observed {
        var overlay: ActiveOverlay = .none
    }
}
