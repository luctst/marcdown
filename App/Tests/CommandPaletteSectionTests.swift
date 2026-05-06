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

    // MARK: - makeMarkdownReferenceRows factory

    @Test("Markdown reference factory returns exactly 10 rows")
    func markdownReferenceRowsCount() {
        let rows = makeMarkdownReferenceRows()
        #expect(rows.count == 10)
    }

    @Test("Markdown reference rows are tagged section .markdown")
    func markdownReferenceRowsAreTaggedMarkdown() {
        let rows = makeMarkdownReferenceRows()
        #expect(rows.allSatisfy { $0.section == .markdown })
    }

    @Test("Markdown reference rows are kind .reference")
    func markdownReferenceRowsAreReferenceKind() {
        let rows = makeMarkdownReferenceRows()
        for row in rows {
            if case .reference = row.kind {
                continue
            } else {
                Issue.record("Expected .reference kind for row \(row.id)")
            }
        }
    }

    @Test("Markdown reference row titles match plan §3 ordering")
    func markdownReferenceRowsTitlesMatchPlan() {
        let rows = makeMarkdownReferenceRows()
        #expect(
            rows.map(\.title) == [
                "Bold",
                "Italic",
                "Heading",
                "List",
                "Ordered list",
                "Inline code",
                "Code block",
                "Link",
                "Quote",
                "Strikethrough",
            ])
    }

    @Test("Markdown reference row syntax chips match plan §3")
    func markdownReferenceRowsShortcutLabelsMatchPlan() {
        let rows = makeMarkdownReferenceRows()
        #expect(
            rows.map(\.shortcutLabel) == [
                "**x**",
                "*x*",
                "# x",
                "- x",
                "1. x",
                "`x`",
                "```x```",
                "[x](y)",
                "> x",
                "~~x~~",
            ])
    }

    @Test("Markdown reference row ids are unique and stable")
    func markdownReferenceRowIdsAreUnique() {
        let rows = makeMarkdownReferenceRows()
        let ids = Set(rows.map(\.id))
        #expect(ids.count == rows.count)
    }

    // MARK: - makePaletteActions composition

    @Test("makePaletteActions appends markdown reference rows after commands")
    func makePaletteActionsAppendsMarkdownRows() {
        let actions = makePaletteActions(
            setOverlay: { _ in },
            newNote: {},
            triggerFind: {},
            duplicate: {},
            delete: {},
            prev: {},
            next: {}
        )

        let commandIds = actions.filter { $0.section == .commands }.map(\.id)
        let markdownIds = actions.filter { $0.section == .markdown }.map(\.id)

        // Commands appear in their existing order, then markdown rows.
        #expect(commandIds.first == "new-note")
        #expect(commandIds.last == "export")
        #expect(markdownIds.count == 10)

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
            next: {}
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
        let rows = makeMarkdownReferenceRows()
        #expect(rows.allSatisfy { !$0.isActionable })
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

    // MARK: - nextActionableIndex

    /// Builds a tiny mixed list to exercise the nav helper without touching
    /// the real factory. Index layout:
    ///   0: leaf-A (actionable)
    ///   1: ref-1  (skip)
    ///   2: ref-2  (skip)
    ///   3: leaf-B (actionable)
    private func mixedActions() -> [PaletteAction] {
        [
            PaletteAction(id: "leaf-A", title: "Leaf A", icon: "a", shortcutLabel: "") {},
            PaletteAction(id: "ref-1", title: "Ref 1", icon: "r", shortcutLabel: "**x**", kind: .reference, section: .markdown),
            PaletteAction(id: "ref-2", title: "Ref 2", icon: "r", shortcutLabel: "*x*", kind: .reference, section: .markdown),
            PaletteAction(id: "leaf-B", title: "Leaf B", icon: "b", shortcutLabel: "") {},
        ]
    }

    @Test("Down-arrow from a leaf skips reference rows to the next leaf")
    func downSkipsReferenceRows() {
        let actions = mixedActions()
        // From index 0 (leaf-A), +1 should land on leaf-B at index 3.
        #expect(nextActionableIndex(in: actions, from: 0, delta: 1) == 3)
    }

    @Test("Down-arrow wraps from last leaf back to first leaf")
    func downWrapsToFirstActionable() {
        let actions = mixedActions()
        // From index 3 (leaf-B), +1 should wrap to leaf-A at index 0.
        #expect(nextActionableIndex(in: actions, from: 3, delta: 1) == 0)
    }

    @Test("Up-arrow from first leaf wraps to last actionable, skipping refs")
    func upWrapsAndSkips() {
        let actions = mixedActions()
        // From index 0 (leaf-A), -1 should wrap to leaf-B at index 3.
        #expect(nextActionableIndex(in: actions, from: 0, delta: -1) == 3)
    }

    @Test("nextActionableIndex returns nil when no row is actionable")
    func noActionableReturnsNil() {
        let actions: [PaletteAction] = [
            PaletteAction(id: "ref-1", title: "Ref 1", icon: "r", shortcutLabel: "x", kind: .reference, section: .markdown),
            PaletteAction(id: "ref-2", title: "Ref 2", icon: "r", shortcutLabel: "y", kind: .reference, section: .markdown),
        ]
        #expect(nextActionableIndex(in: actions, from: 0, delta: 1) == nil)
    }

    @Test("nextActionableIndex returns nil for an empty list")
    func emptyListReturnsNil() {
        #expect(nextActionableIndex(in: [], from: 0, delta: 1) == nil)
    }

    // MARK: - firstActionableIndex

    @Test("firstActionableIndex skips leading reference rows")
    func firstActionableSkipsRefs() {
        let actions: [PaletteAction] = [
            PaletteAction(id: "ref-1", title: "Ref 1", icon: "r", shortcutLabel: "x", kind: .reference, section: .markdown),
            PaletteAction(id: "leaf", title: "Leaf", icon: "a", shortcutLabel: "") {},
        ]
        #expect(firstActionableIndex(in: actions) == 1)
    }

    @Test("firstActionableIndex returns nil when no row is actionable")
    func firstActionableNoneReturnsNil() {
        let actions: [PaletteAction] = [
            PaletteAction(id: "ref-1", title: "Ref 1", icon: "r", shortcutLabel: "x", kind: .reference, section: .markdown)
        ]
        #expect(firstActionableIndex(in: actions) == nil)
    }
}
