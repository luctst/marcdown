import Foundation
import Testing

@testable import Marcdown

@MainActor
@Suite("CommandPalette.filter")
struct CommandPaletteFilterTests {
    /// Builds a deterministic set of palette actions whose titles cover the
    /// scenarios we care about: case mismatch, partial substring, exact match,
    /// and a no-op handler so tests stay focused on filtering, not invocation.
    private func makeActions() -> [PaletteAction] {
        [
            PaletteAction(id: "new-note", title: "New Note", icon: "plus", shortcutLabel: "⌘N") {},
            PaletteAction(id: "browse-notes", title: "Browse Notes", icon: "list.bullet", shortcutLabel: "⌘P") {},
            PaletteAction(id: "find", title: "Find in Note", icon: "magnifyingglass", shortcutLabel: "⌘F") {},
            PaletteAction(id: "duplicate", title: "Duplicate Note", icon: "doc.on.doc", shortcutLabel: "⌘D") {},
            PaletteAction(id: "delete", title: "Delete Note", icon: "trash", shortcutLabel: "⇧⌘⌫") {},
        ]
    }

    @Test("Empty query returns all actions in original order")
    func emptyQueryReturnsAllInOrder() {
        let actions = makeActions()
        let result = CommandPalette.filter(actions: actions, query: "")
        #expect(result.map(\.id) == actions.map(\.id))
    }

    @Test("Whitespace-only query is treated as empty")
    func whitespaceQueryIsTreatedAsEmpty() {
        let actions = makeActions()
        let result = CommandPalette.filter(actions: actions, query: "   ")
        #expect(result.map(\.id) == actions.map(\.id))
    }

    @Test("Substring match is case-insensitive")
    func caseInsensitiveSubstringMatch() {
        let actions = makeActions()
        let result = CommandPalette.filter(actions: actions, query: "NOTE")
        // "New Note", "Browse Notes", "Find in Note", "Duplicate Note", "Delete Note"
        #expect(result.map(\.id) == ["new-note", "browse-notes", "find", "duplicate", "delete"])
    }

    @Test("Query with no matches returns an empty array")
    func noMatchesReturnsEmpty() {
        let actions = makeActions()
        let result = CommandPalette.filter(actions: actions, query: "zzzz")
        #expect(result.isEmpty)
    }

    @Test("Leading and trailing whitespace are trimmed before matching")
    func trimmingWhitespace() {
        let actions = makeActions()
        let result = CommandPalette.filter(actions: actions, query: "  browse  ")
        #expect(result.map(\.id) == ["browse-notes"])
    }

    @Test("Multiple matches are returned in original order")
    func multipleMatchesPreserveOriginalOrder() {
        let actions = makeActions()
        // "Note" appears in titles 1, 2, 3, 4, 5 — all of them, original order.
        let result = CommandPalette.filter(actions: actions, query: "note")
        #expect(result.map(\.id) == actions.map(\.id))
    }
}
