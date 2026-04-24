import MarcdownCore
import SwiftUI

/// Command-palette style note switcher. Shown as an overlay inside the panel
/// when the user presses ⌘P.
struct QuickSwitcher: View {
    let notes: [NoteSummary]
    let onOpen: (URL) -> Void
    let onDismiss: () -> Void
    let currentNote: URL?

    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var queryFieldFocused: Bool

    private var filtered: [ScoredNote] {
        QuickSwitcher.filter(notes: notes, query: query)
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
            TextField("Find a note", text: $query)
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
                        Text("No matching notes")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.top, 40)
                    }
                    ForEach(Array(filtered.enumerated()), id: \.element.note.id) { index, scored in
                        row(for: scored.note, isSelected: index == selectedIndex)
                            .id(scored.note.id)
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                if hovering { selectedIndex = index }
                            }
                            .accessibilityAddTraits(.isButton)
                            .onTapGesture {
                                onOpen(scored.note.id)
                            }
                    }
                }
            }
            .onChange(of: selectedIndex) { _, newValue in
                guard filtered.indices.contains(newValue) else { return }
                withAnimation(.easeOut(duration: 0.08)) {
                    proxy.scrollTo(filtered[newValue].note.id, anchor: .center)
                }
            }
        }
    }

    private func row(for note: NoteSummary, isSelected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if !note.preview.isEmpty {
                    Text(note.preview)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text("\(note.characterCount) characters")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if note.id == currentNote {
                Text("Current")
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.2)))
            }
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
        onOpen(filtered[selectedIndex].note.id)
    }

    // MARK: - Filtering

    struct ScoredNote: Equatable {
        let note: NoteSummary
        let score: Int
    }

    static func filter(notes: [NoteSummary], query: String) -> [ScoredNote] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            // No query: preserve modifiedAt-desc order from the index.
            return notes.map { ScoredNote(note: $0, score: 0) }
        }
        let needle = trimmed.lowercased()
        var results: [ScoredNote] = []
        for note in notes {
            let title = note.title.lowercased()
            let preview = note.preview.lowercased()

            var score = 0
            if title == needle { score += 100 }
            if title.hasPrefix(needle) { score += 40 }
            if title.contains(needle) { score += 20 }
            if preview.contains(needle) { score += 5 }

            if score > 0 {
                results.append(ScoredNote(note: note, score: score))
            }
        }
        results.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.note.modifiedAt > $1.note.modifiedAt
        }
        return results
    }
}

