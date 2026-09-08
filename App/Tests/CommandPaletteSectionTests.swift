import Foundation
import Testing

@testable import Marcdown

/// Locks down the section/reference data-model contract introduced for the
/// markdown reference rows. Pure-state assertions over `[PaletteAction]`; no
/// view layer.
@MainActor
@Suite("PaletteAction sections + reference kind")
struct CommandPaletteSectionTests {
    // MARK: - Default section

    @Test("Leaf init defaults section to .commands")
    func leafInitDefaultsToCommandsSection() {
        let action = PaletteAction(
            id: "leaf",
            title: "Leaf",
            icon: "circle",
            shortcutLabel: ""
        ) {}

        #expect(action.section == .commands)
    }

    @Test("Submenu init defaults section to .commands")
    func submenuInitDefaultsToCommandsSection() {
        let action = PaletteAction(
            id: "x",
            title: "x",
            icon: "x",
            shortcutLabel: "",
            kind: .submenu(.exportFormat)
        )

        #expect(action.section == .commands)
    }

    // MARK: - Reference kind

    @Test("Reference action has nil handler")
    func referenceActionHasNilHandler() {
        let action = PaletteAction(
            id: "ref",
            title: "Bold",
            icon: "bold",
            shortcutLabel: "**x**",
            kind: .reference,
            section: .markdown
        )

        #expect(action.handler == nil)
    }

    @Test("Reference action carries its assigned section")
    func referenceActionCarriesAssignedSection() {
        let action = PaletteAction(
            id: "ref",
            title: "Bold",
            icon: "bold",
            shortcutLabel: "**x**",
            kind: .reference,
            section: .markdown
        )

        #expect(action.section == .markdown)
    }

    // MARK: - makeMarkdownRows factory

    @Test("Markdown factory returns exactly 15 rows")
    func markdownRowsCount() {
        let rows = makeMarkdownRows(setOverlay: { _ in }, perform: { _ in })
        #expect(rows.count == 15)
    }

    @Test("Markdown rows are tagged section .markdown")
    func markdownRowsAreTaggedMarkdown() {
        let rows = makeMarkdownRows(setOverlay: { _ in }, perform: { _ in })
        #expect(rows.allSatisfy { $0.section == .markdown })
    }

    @Test("Markdown rows are leaf commands")
    func markdownRowsAreLeafKind() {
        let rows = makeMarkdownRows(setOverlay: { _ in }, perform: { _ in })
        #expect(rows.allSatisfy { $0.handler != nil })
    }

    @Test("Markdown row titles match the command order")
    func markdownRowsTitlesMatchPlan() {
        let rows = makeMarkdownRows(setOverlay: { _ in }, perform: { _ in })
        #expect(
            rows.map(\.title) == [
                "Bold",
                "Italic",
                "Heading 1",
                "Heading 2",
                "Heading 3",
                "Bullet list",
                "Numbered list",
                "Task list",
                "Quote",
                "Inline code",
                "Code block",
                "Link",
                "Strikethrough",
                "Highlight",
                "Divider",
            ])
    }

    @Test("Markdown row shortcut chips match the editor chord table")
    func markdownRowsShortcutLabelsMatchPlan() {
        let rows = makeMarkdownRows(setOverlay: { _ in }, perform: { _ in })
        #expect(
            rows.map(\.shortcutLabel) == [
                "⌘B",
                "⌘I",
                "⌥⌘1",
                "⌥⌘2",
                "⌥⌘3",
                "⇧⌘L",
                "⇧⌘N",
                "⇧⌘T",
                "⇧⌘B",
                "⌘E",
                "",
                "⇧⌘K",
                "⇧⌘X",
                "⇧⌘H",
                "",
            ])
    }

    @Test("Markdown row ids are unique and stable")
    func markdownRowIdsAreUnique() {
        let rows = makeMarkdownRows(setOverlay: { _ in }, perform: { _ in })
        let ids = Set(rows.map(\.id))
        #expect(ids.count == rows.count)
    }

    // MARK: - makePaletteActions composition

    @Test("makePaletteActions appends markdown rows after commands")
    func makePaletteActionsAppendsMarkdownRows() {
        let actions = makePaletteActions(
            setOverlay: { _ in },
            newNote: {},
            triggerFind: {},
            duplicate: {},
            delete: {},
            prev: {},
            next: {},
            perform: { _ in }
        )

        let commandIds = actions.filter { $0.section == .commands }.map(\.id)
        let markdownIds = actions.filter { $0.section == .markdown }.map(\.id)

        // Commands appear in their existing order, then markdown rows.
        #expect(commandIds.first == "new-note")
        #expect(commandIds.last == "export")
        #expect(markdownIds.count == 15)

        // Order: every command must precede every markdown row.
        let firstMarkdownIndex = actions.firstIndex(where: { $0.section == .markdown })
        let lastCommandIndex = actions.lastIndex(where: { $0.section == .commands })
        #expect(lastCommandIndex! < firstMarkdownIndex!)
    }

    @Test("makePaletteActions sets section .commands on existing rows")
    func makePaletteActionsTagsExistingRowsAsCommands() {
        let actions = makePaletteActions(
            setOverlay: { _ in },
            newNote: {},
            triggerFind: {},
            duplicate: {},
            delete: {},
            prev: {},
            next: {},
            perform: { _ in }
        )

        let existingCommandIds: Set<String> = [
            "new-note", "browse-notes", "find", "duplicate",
            "delete", "prev-note", "next-note", "export",
        ]
        for action in actions where existingCommandIds.contains(action.id) {
            #expect(action.section == .commands)
        }
    }

    // MARK: - isActionable contract

    @Test("Reference rows are not actionable")
    func referenceRowsAreNotActionable() {
        let action = PaletteAction(
            id: "ref",
            title: "Bold",
            icon: "bold",
            shortcutLabel: "**x**",
            kind: .reference,
            section: .markdown
        )
        #expect(!action.isActionable)
    }

    @Test("Markdown rows are actionable")
    func markdownRowsAreActionable() {
        let rows = makeMarkdownRows(setOverlay: { _ in }, perform: { _ in })
        #expect(rows.allSatisfy { $0.isActionable })
    }

    @Test("Leaf rows are actionable")
    func leafRowsAreActionable() {
        let action = PaletteAction(
            id: "leaf",
            title: "Leaf",
            icon: "circle",
            shortcutLabel: ""
        ) {}

        #expect(action.isActionable)
    }

    @Test("Submenu rows are actionable")
    func submenuRowsAreActionable() {
        let action = PaletteAction(
            id: "x",
            title: "x",
            icon: "x",
            shortcutLabel: "",
            kind: .submenu(.exportFormat)
        )

        #expect(action.isActionable)
    }

    // MARK: - nextIndex

    /// Builds a tiny mixed list to exercise the nav helper without touching
    /// the real factory. Index layout:
    ///   0: leaf-A (actionable)
    ///   1: ref-1  (reference, but still reachable)
    ///   2: ref-2  (reference, but still reachable)
    ///   3: leaf-B (actionable)
    private func mixedActions() -> [PaletteAction] {
        [
            PaletteAction(id: "leaf-A", title: "Leaf A", icon: "a", shortcutLabel: "") {},
            PaletteAction(
                id: "ref-1",
                title: "Ref 1",
                icon: "r",
                shortcutLabel: "**x**",
                kind: .reference,
                section: .markdown
            ),
            PaletteAction(
                id: "ref-2",
                title: "Ref 2",
                icon: "r",
                shortcutLabel: "*x*",
                kind: .reference,
                section: .markdown
            ),
            PaletteAction(id: "leaf-B", title: "Leaf B", icon: "b", shortcutLabel: "") {},
        ]
    }

    @Test("Down-arrow from a leaf lands on the next row, including reference rows")
    func downReachesReferenceRows() {
        let actions = mixedActions()
        // From index 0 (leaf-A), +1 should land on ref-1 at index 1 — reference
        // rows must be reachable so the user can scroll the markdown legend
        // with the keyboard.
        #expect(nextIndex(in: actions, from: 0, delta: 1) == 1)
    }

    @Test("Down-arrow walks through every row in order")
    func downWalksEveryRow() {
        let actions = mixedActions()
        #expect(nextIndex(in: actions, from: 1, delta: 1) == 2)
        #expect(nextIndex(in: actions, from: 2, delta: 1) == 3)
    }

    @Test("Down-arrow wraps from the last row back to the first")
    func downWrapsToFirst() {
        let actions = mixedActions()
        #expect(nextIndex(in: actions, from: 3, delta: 1) == 0)
    }

    @Test("Up-arrow wraps from the first row to the last")
    func upWrapsToLast() {
        let actions = mixedActions()
        #expect(nextIndex(in: actions, from: 0, delta: -1) == 3)
    }

    @Test("nextIndex returns a valid index even when every row is a reference")
    func referenceOnlyListIsTraversable() {
        let actions: [PaletteAction] = [
            PaletteAction(
                id: "ref-1",
                title: "Ref 1",
                icon: "r",
                shortcutLabel: "x",
                kind: .reference,
                section: .markdown
            ),
            PaletteAction(
                id: "ref-2",
                title: "Ref 2",
                icon: "r",
                shortcutLabel: "y",
                kind: .reference,
                section: .markdown
            ),
        ]
        // All rows are reachable now — Enter is still a no-op (covered
        // separately) but nav must not pin selection at index 0.
        #expect(nextIndex(in: actions, from: 0, delta: 1) == 1)
        #expect(nextIndex(in: actions, from: 1, delta: 1) == 0)
    }

    @Test("nextIndex returns nil for an empty list")
    func emptyListReturnsNil() {
        #expect(nextIndex(in: [], from: 0, delta: 1) == nil)
    }

    // MARK: - firstIndex

    @Test("firstIndex returns 0 for a non-empty list, regardless of kind")
    func firstIndexLandsOnFirstRow() {
        let actions: [PaletteAction] = [
            PaletteAction(
                id: "ref-1",
                title: "Ref 1",
                icon: "r",
                shortcutLabel: "x",
                kind: .reference,
                section: .markdown
            ),
            PaletteAction(id: "leaf", title: "Leaf", icon: "a", shortcutLabel: "") {},
        ]
        // No more "skip leading references" — the user must be able to land
        // on a reference row directly when the filter only matches refs.
        #expect(firstIndex(in: actions) == 0)
    }

    @Test("firstIndex returns nil for an empty list")
    func firstIndexEmptyReturnsNil() {
        let actions: [PaletteAction] = []
        #expect(firstIndex(in: actions) == nil)
    }
}
