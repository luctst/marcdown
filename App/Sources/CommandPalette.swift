import SwiftUI

/// Sub-modes inside the command palette. The palette presents either the root
/// action list or a focused sub-flow (e.g. the export-format chooser). ⎋ pops
/// from a sub-mode back to root before dismissing.
enum PaletteSubMode: Equatable, Sendable {
    case root
    case exportFormat
    /// Opened by typing `/` at the start of a line: only the Markdown rows.
    case blockInsert
}

/// Three flavors of palette action: a leaf invokes a closure, a submenu
/// transitions the palette into a sub-mode rather than dispatching work, and
/// a reference is a non-actionable informational row (e.g. markdown syntax
/// docs). Reference rows render but are skipped by keyboard nav and produce a
/// no-op when committed.
enum PaletteActionKind: Sendable {
    case leaf(@MainActor () -> Void)
    case submenu(PaletteSubMode)
    case reference
}

/// Visual + filtering grouping for palette rows. Section headers render above
/// each non-empty group; nav skips header rows. Existing call-sites that omit
/// the field land in `.commands` so the data-model change is non-breaking.
enum PaletteSection: Sendable, Equatable, Hashable {
    case commands
    case markdown
}

@MainActor
struct PaletteAction: Identifiable {
    let id: String
    let title: String
    let icon: String
    let shortcutLabel: String
    let kind: PaletteActionKind
    let section: PaletteSection

    /// Trailing-closure init that constructs a leaf action. Preserves the
    /// existing call-site shape used by `makePaletteActions` and the existing
    /// tests in `CommandPaletteFilterTests` and `CommandPaletteActionContractTests`.
    init(
        id: String,
        title: String,
        icon: String,
        shortcutLabel: String,
        section: PaletteSection = .commands,
        _ handler: @escaping @MainActor () -> Void
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.shortcutLabel = shortcutLabel
        self.kind = .leaf(handler)
        self.section = section
    }

    /// Init for non-leaf actions (`.submenu`, `.reference`). Existing call-sites
    /// that only pass `kind: .submenu(...)` keep working — `section` defaults to
    /// `.commands`.
    init(
        id: String,
        title: String,
        icon: String,
        shortcutLabel: String,
        kind: PaletteActionKind,
        section: PaletteSection = .commands
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.shortcutLabel = shortcutLabel
        self.kind = kind
        self.section = section
    }

    /// Leaf-only convenience accessor used by tests that spy on handlers.
    /// Returns nil for `.submenu` and `.reference` cases.
    var handler: (@MainActor () -> Void)? {
        if case .leaf(let h) = kind { return h }
        return nil
    }

    /// True for rows the user can commit (Enter / click). False for rows that
    /// exist purely as in-palette documentation. Used by keyboard nav and the
    /// commit path to skip non-actionable rows.
    var isActionable: Bool {
        switch kind {
        case .leaf, .submenu: return true
        case .reference: return false
        }
    }
}

/// Pure ⎋-key state-transition helper. Returns the next sub-mode or `nil` to
/// signal "the palette should dismiss". Extracted as a free function so the
/// state machine can be unit-tested without mounting any view.
@MainActor
func paletteSubModeAfterEscape(current: PaletteSubMode) -> PaletteSubMode? {
    switch current {
    case .root: return nil
    case .exportFormat: return .root
    case .blockInsert: return nil
    }
}

/// Pure helper used by ↑/↓ navigation to find the next row from `from`,
/// walking the list by `delta` (±1 in practice) and wrapping at the edges.
/// Returns `nil` when the list is empty.
///
/// Every filtered row is reachable — including `.reference` rows. The Enter
/// behavior on a `.reference` row remains a no-op (handled in `invoke`), but
/// the highlight must still be able to land there so the user can scroll
/// through the markdown reference using only the keyboard.
@MainActor
func nextIndex(in actions: [PaletteAction], from: Int, delta: Int) -> Int? {
    guard !actions.isEmpty else { return nil }
    let count = actions.count
    let step = delta == 0 ? 1 : delta
    let base = ((from % count) + count) % count
    return (base + step + count) % count
}

/// Pure helper used to land `selectedIndex` on the first row when the list
/// mounts or the filter changes. Returns `nil` for an empty list.
@MainActor
func firstIndex(in actions: [PaletteAction]) -> Int? {
    actions.indices.first
}

/// Builds the three rows shown when the palette is in `.exportFormat`. Each
/// row is a leaf that invokes `onExport` with its corresponding `ExportFormat`.
/// Pure factory — no view dependencies — so the contract is unit-tested.
@MainActor
func makeFormatChooserActions(
    onExport: @escaping @MainActor (ExportFormat) -> Void
) -> [PaletteAction] {
    [
        PaletteAction(
            id: "export-md",
            title: "Markdown",
            icon: "doc.plaintext",
            shortcutLabel: ""
        ) { onExport(.markdown) },
        PaletteAction(
            id: "export-html",
            title: "HTML",
            icon: "chevron.left.forwardslash.chevron.right",
            shortcutLabel: ""
        ) { onExport(.html) },
        PaletteAction(
            id: "export-pdf",
            title: "PDF",
            icon: "doc.richtext",
            shortcutLabel: ""
        ) { onExport(.pdf) },
    ]
}

struct CommandPalette: View {
    let actions: [PaletteAction]
    /// Lifted to a binding so the AppKit `EscapeKeyMonitor` in `PanelRootView`
    /// can pop the sub-mode before the local NSEvent monitor consumes the
    /// keystroke. Keeping it here as `@State` would let the monitor collapse
    /// the entire palette out from under a sub-mode.
    @Binding var subMode: PaletteSubMode
    let onDismiss: () -> Void
    let onExport: @MainActor (ExportFormat) -> Void

    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    /// True while the user is driving selection from the keyboard. Cleared on
    /// genuine mouse motion (`onContinuousHover`). Used to suppress
    /// `onHover`-driven selection updates that would otherwise yank the
    /// highlight back to whichever row the cursor happens to be parked over.
    @State private var isUsingKeyboard: Bool = false
    @FocusState private var queryFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The action list rendered for the current sub-mode. In `.exportFormat`
    /// the list is synthesized from `makeFormatChooserActions` so the chooser
    /// rows are leaf actions that delegate back to `onExport`.
    private var displayedActions: [PaletteAction] {
        switch subMode {
        case .root:
            return actions
        case .exportFormat:
            return makeFormatChooserActions(onExport: onExport)
        case .blockInsert:
            return actions.filter { $0.section == .markdown }
        }
    }

    private var filtered: [PaletteAction] {
        CommandPalette.filter(actions: displayedActions, query: query)
    }

    private var searchPlaceholder: String {
        switch subMode {
        case .root: return "Search for actions..."
        case .exportFormat: return "Choose a format"
        case .blockInsert: return "Insert block"
        }
    }

    private var searchLeadingIcon: String {
        switch subMode {
        case .root: return "command"
        case .exportFormat: return "square.and.arrow.up"
        case .blockInsert: return "slash.circle"
        }
    }

    private var emptyStateCopy: String {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        switch subMode {
        case .root:
            return "No matching actions"
        case .exportFormat:
            return trimmed.isEmpty
                ? "No matching formats"
                : "No matches for \"\(trimmed)\""
        case .blockInsert:
            return "No matching blocks"
        }
    }

    private var searchAccessibilityLabel: String {
        let count = filtered.count
        let plural = count == 1 ? "" : "s"
        switch subMode {
        case .root:
            return "Search actions, \(count) result\(plural)"
        case .exportFormat:
            return "Choose a format, \(count) result\(plural)"
        case .blockInsert:
            return "Insert block, \(count) result\(plural)"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            list
                .id(subMode)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    )
                )
        }
        .frame(maxWidth: 520, maxHeight: 340)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.separator, lineWidth: 1)
        )
        .shadow(radius: 30, y: 10)
        .onAppear {
            selectedIndex = firstIndex(in: filtered) ?? 0
            // Defer focus assignment by one runloop tick. When this overlay is
            // mounted as a result of dismissing another overlay (palette →
            // switcher), the previous TextField is still tearing down its
            // first-responder state on the same tick, and a synchronous
            // assignment here gets clobbered.
            Task { @MainActor in
                queryFieldFocused = true
            }
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: searchLeadingIcon)
                .foregroundStyle(.secondary)
            TextField(searchPlaceholder, text: $query)
                .textFieldStyle(.plain)
                .focused($queryFieldFocused)
                .onSubmit { commitSelection() }
                .onKeyPress(.upArrow) {
                    isUsingKeyboard = true
                    moveSelection(-1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    isUsingKeyboard = true
                    moveSelection(1)
                    return .handled
                }
                .onKeyPress(.escape) {
                    if let popped = paletteSubModeAfterEscape(current: subMode),
                        popped != subMode
                    {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                            subMode = popped
                        }
                        query = ""
                        selectedIndex = 0
                        return .handled
                    }
                    onDismiss()
                    return .handled
                }
                .onChange(of: query) { _, _ in
                    selectedIndex = firstIndex(in: filtered) ?? 0
                }
                .accessibilityLabel(searchAccessibilityLabel)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var list: some View {
        if filtered.isEmpty {
            Text(emptyStateCopy)
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            populatedList
        }
    }

    private var populatedList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(orderedSections, id: \.self) { section in
                        let rowsInSection = filtered.enumerated().filter { $0.element.section == section }
                        if !rowsInSection.isEmpty {
                            sectionHeader(for: section)
                            ForEach(rowsInSection, id: \.element.id) { index, action in
                                row(for: action, isSelected: index == selectedIndex)
                                    .id(action.id)
                                    .contentShape(Rectangle())
                                    .onHover { hovering in
                                        guard !isUsingKeyboard else { return }
                                        if hovering { selectedIndex = index }
                                    }
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityLabel(rowAccessibilityLabel(for: action))
                                    .accessibilityValue("Row \(index + 1) of \(filtered.count)")
                                    .onTapGesture {
                                        invoke(action)
                                    }
                            }
                        }
                    }
                }
            }
            .onContinuousHover { phase in
                // Genuine pointer motion clears the keyboard-priority flag so
                // hover-to-select behavior resumes once the user is back on
                // the trackpad/mouse.
                if case .active = phase { isUsingKeyboard = false }
            }
            .onChange(of: selectedIndex) { _, newValue in
                guard filtered.indices.contains(newValue) else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.08)) {
                    proxy.scrollTo(filtered[newValue].id, anchor: .center)
                }
            }
        }
    }

    /// Render order for sections. Commands first (primary affordance), Markdown
    /// reference second. Keeping this in one place makes the ordering decision
    /// reviewable in isolation — see plan §risk-2.
    private var orderedSections: [PaletteSection] { [.commands, .markdown] }

    @ViewBuilder
    private func sectionHeader(for section: PaletteSection) -> some View {
        Text(sectionTitle(for: section))
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionTitle(for section: PaletteSection) -> String {
        switch section {
        case .commands: return "COMMANDS"
        case .markdown: return "MARKDOWN"
        }
    }

    private func row(for action: PaletteAction, isSelected: Bool) -> some View {
        HStack {
            Image(systemName: action.icon)
                .frame(width: 20)
            Text(action.title)
                .font(.system(size: 13))
            Spacer()
            if !action.shortcutLabel.isEmpty {
                Text(action.shortcutLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.quaternary))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
    }

    private func rowAccessibilityLabel(for action: PaletteAction) -> String {
        if action.shortcutLabel.isEmpty {
            return action.title
        }
        return "\(action.title), \(action.shortcutLabel)"
    }

    private func moveSelection(_ delta: Int) {
        guard let next = nextIndex(in: filtered, from: selectedIndex, delta: delta)
        else { return }
        selectedIndex = next
    }

    /// Handlers own their post-action overlay state — leaf actions may dismiss
    /// the palette or chain into another overlay, while submenu actions
    /// transition this palette into a sub-mode. `onDismiss` is reserved for
    /// the Esc-key and backdrop-tap paths where the user cancelled outright.
    private func commitSelection() {
        guard filtered.indices.contains(selectedIndex) else { return }
        invoke(filtered[selectedIndex])
    }

    private func invoke(_ action: PaletteAction) {
        switch action.kind {
        case .leaf(let handler):
            handler()
        case .submenu(let target):
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                subMode = target
            }
            query = ""
            selectedIndex = 0
        case .reference:
            // Non-actionable in v1: palette stays open, no dispatch. See plan
            // §risks-1 for the v2 candidate ("insert syntax at cursor").
            break
        }
    }

    // MARK: - Filtering

    static func filter(actions: [PaletteAction], query: String) -> [PaletteAction] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return actions }
        let needle = trimmed.lowercased()
        return actions.filter { $0.title.lowercased().contains(needle) }
    }
}
