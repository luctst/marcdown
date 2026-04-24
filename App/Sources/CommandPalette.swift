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
            queryFieldFocused = true
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
                    moveSelection(-1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
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

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if filtered.isEmpty {
                        Text("No matching actions")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.top, 40)
                    }
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, action in
                        row(for: action, isSelected: index == selectedIndex)
                            .id(action.id)
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                if hovering { selectedIndex = index }
                            }
                            .accessibilityAddTraits(.isButton)
                            .onTapGesture {
                                action.handler()
                                onDismiss()
                            }
                    }
                }
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

    private func commitSelection() {
        guard filtered.indices.contains(selectedIndex) else { return }
        filtered[selectedIndex].handler()
        onDismiss()
    }

    // MARK: - Filtering

    static func filter(actions: [PaletteAction], query: String) -> [PaletteAction] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return actions }
        let needle = trimmed.lowercased()
        return actions.filter { $0.title.lowercased().contains(needle) }
    }
}
