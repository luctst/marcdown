import Foundation
import Testing

@testable import Marcdown

/// Locks down the pure logic that supports the palette's sub-mode (export
/// format chooser). The view layer is SwiftUI and not unit-testable, but the
/// state-transition function and the action-list synthesizer must remain
/// pure so they can be exercised here without mounting any view.
@MainActor
@Suite("CommandPalette sub-mode pure logic")
struct CommandPaletteSubModeTests {
    // MARK: - paletteSubModeAfterEscape

    @Test("⎋ from root returns nil so the palette dismisses")
    func escapeFromRootReturnsNilToDismiss() {
        #expect(paletteSubModeAfterEscape(current: .root) == nil)
    }

    @Test("⎋ from exportFormat pops back to root instead of dismissing")
    func escapeFromExportFormatPopsToRoot() {
        #expect(paletteSubModeAfterEscape(current: .exportFormat) == .root)
    }

    // MARK: - makeFormatChooserActions

    @Test("Format chooser exposes exactly three rows")
    func formatChooserHasThreeActions() {
        let actions = makeFormatChooserActions(onExport: { _ in })
        #expect(actions.count == 3)
    }

    @Test("Format chooser rows are ordered Markdown, HTML, PDF")
    func formatChooserActionsAreOrderedMarkdownHtmlPdf() {
        let actions = makeFormatChooserActions(onExport: { _ in })
        #expect(actions.map(\.id) == ["export-md", "export-html", "export-pdf"])
    }

    @Test("Format chooser titles match the design tokens")
    func formatChooserTitlesMatchDesignTokens() {
        let actions = makeFormatChooserActions(onExport: { _ in })
        #expect(actions.map(\.title) == ["Markdown", "HTML", "PDF"])
    }

    @Test("Format chooser icons match the design tokens (plan §3b)")
    func formatChooserIconsMatchDesignTokens() {
        let actions = makeFormatChooserActions(onExport: { _ in })
        #expect(actions.map(\.icon) == [
            "doc.plaintext",
            "chevron.left.forwardslash.chevron.right",
            "doc.richtext",
        ])
    }

    @Test("Format chooser rows have no keyboard shortcut label")
    func formatChooserShortcutsAreEmpty() {
        let actions = makeFormatChooserActions(onExport: { _ in })
        #expect(actions.allSatisfy { $0.shortcutLabel == "" })
    }

    @Test("Format chooser rows are leaf kind, not submenus")
    func formatChooserActionsAreLeafKind() {
        let actions = makeFormatChooserActions(onExport: { _ in })
        for action in actions {
            if case .leaf = action.kind {
                continue
            } else {
                Issue.record("Expected .leaf kind for action \(action.id), got submenu")
            }
        }
    }

    @Test("Invoking the Markdown row calls onExport with .markdown")
    func invokingMarkdownActionCallsOnExportWithMarkdown() {
        let captured = Captured()
        let actions = makeFormatChooserActions(onExport: { captured.format = $0 })

        actions[0].handler?()

        #expect(captured.format == .markdown)
    }

    @Test("Invoking the HTML row calls onExport with .html")
    func invokingHtmlActionCallsOnExportWithHtml() {
        let captured = Captured()
        let actions = makeFormatChooserActions(onExport: { captured.format = $0 })

        actions[1].handler?()

        #expect(captured.format == .html)
    }

    @Test("Invoking the PDF row calls onExport with .pdf")
    func invokingPdfActionCallsOnExportWithPdf() {
        let captured = Captured()
        let actions = makeFormatChooserActions(onExport: { captured.format = $0 })

        actions[2].handler?()

        #expect(captured.format == .pdf)
    }

    // MARK: - PaletteActionKind smoke

    @Test("Leaf action exposes its closure through the handler property")
    func leafActionExposesHandlerThroughComputedProperty() {
        let fired = Fired()
        let action = PaletteAction(
            id: "leaf",
            title: "Leaf",
            icon: "circle",
            shortcutLabel: ""
        ) {
            fired.value = true
        }

        #expect(action.handler != nil)
        action.handler?()
        #expect(fired.value == true)
    }

    @Test("Submenu action has no handler closure")
    func submenuActionHasNilHandler() {
        let action = PaletteAction(
            id: "x",
            title: "x",
            icon: "x",
            shortcutLabel: "",
            kind: .submenu(.exportFormat)
        )

        #expect(action.handler == nil)
    }

    // MARK: - Spies

    /// Reference-type spy so @MainActor closures can record the format they
    /// were invoked with without `inout` capture.
    @MainActor
    private final class Captured {
        var format: ExportFormat?
    }

    /// Reference-type flag spy for the leaf-handler smoke test.
    @MainActor
    private final class Fired {
        var value = false
    }
}
