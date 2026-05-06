import SwiftUI

@MainActor
struct PaletteAction: Identifiable {
    let id: String
    let title: String
    let icon: String
    let shortcutLabel: String
    let handler: @MainActor () -> Void
}

struct CommandPalette: View {
    let actions: [PaletteAction]
    let onDismiss: () -> Void

    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    /// True while the user is driving selection from the keyboard. Cleared on
    /// genuine mouse motion (`onContinuousHover`). Used to suppress
    /// `onHover`-driven selection updates that would otherwise yank the
    /// highlight back to whichever row the cursor happens to be parked over.
    @State private var isUsingKeyboard: Bool = false
    @FocusState private var queryFieldFocused: Bool

    private var filtered: [PaletteAction] {
        CommandPalette.filter(actions: actions, query: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            list
        }
        .frame(width: 520, height: 340)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.separator, lineWidth: 1)
        )
        .shadow(radius: 30, y: 10)
        .onAppear {
            selectedIndex = 0
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
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search for actions...", text: $query)
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
                    onDismiss()
                    return .handled
                }
                .onChange(of: query) { _, _ in
                    selectedIndex = 0
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var list: some View {
        if filtered.isEmpty {
            Text("No matching actions")
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
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, action in
                        row(for: action, isSelected: index == selectedIndex)
                            .id(action.id)
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                guard !isUsingKeyboard else { return }
                                if hovering { selectedIndex = index }
                            }
                            .accessibilityAddTraits(.isButton)
                            .onTapGesture {
                                action.handler()
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
                withAnimation(.easeOut(duration: 0.08)) {
                    proxy.scrollTo(filtered[newValue].id, anchor: .center)
                }
            }
        }
    }

    private func row(for action: PaletteAction, isSelected: Bool) -> some View {
        HStack {
            Image(systemName: action.icon)
                .frame(width: 20)
            Text(action.title)
                .font(.system(size: 13))
            Spacer()
            Text(action.shortcutLabel)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(.quaternary))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
    }

    private func moveSelection(_ delta: Int) {
        guard !filtered.isEmpty else { return }
        let count = filtered.count
        selectedIndex = (selectedIndex + delta + count) % count
    }

    /// Handlers own their post-action overlay state — they may dismiss the
    /// palette or chain into another overlay. `onDismiss` is reserved for the
    /// Esc-key and backdrop-tap paths where the user cancelled without acting.
    private func commitSelection() {
        guard filtered.indices.contains(selectedIndex) else { return }
        filtered[selectedIndex].handler()
    }

    // MARK: - Filtering

    static func filter(actions: [PaletteAction], query: String) -> [PaletteAction] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return actions }
        let needle = trimmed.lowercased()
        return actions.filter { $0.title.lowercased().contains(needle) }
    }
}
