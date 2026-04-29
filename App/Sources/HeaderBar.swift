import MarcdownCore
import SwiftUI

struct HeaderBar: View {
    let title: String
    let onCommandPalette: () -> Void
    let onQuickSwitcher: () -> Void
    let onNewNote: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .center)
                HStack(spacing: 4) {
                    Spacer()
                    Button(action: onCommandPalette) {
                        Image(systemName: "command")
                    }
                    .accessibilityLabel("Command Palette")
                    .raycastTooltip(label: "Command Palette", shortcut: ["⌘", "K"])
                    Button(action: onQuickSwitcher) {
                        Image(systemName: "list.bullet")
                    }
                    .accessibilityLabel("Browse Notes")
                    .raycastTooltip(label: "Browse Notes", shortcut: ["⌘", "P"])
                    Button(action: onNewNote) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New Note")
                    .raycastTooltip(label: "New Note", shortcut: ["⌘", "N"])
                }
                .buttonStyle(IconButtonStyle())
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .frame(height: 28)
            Divider()
        }
    }
}

/// Raycast-style icon button: 28×28 cell with a rounded hover/press background.
/// Each button instance owns its own hover state, so hovers do not leak between adjacent cells.
private struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Wrapper(configuration: configuration)
    }

    private struct Wrapper: View {
        let configuration: Configuration
        @State private var isHovering = false

        private var backgroundOpacity: Double {
            if configuration.isPressed { return 0.14 }
            if isHovering { return 0.08 }
            return 0
        }

        var body: some View {
            configuration.label
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(backgroundOpacity))
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .onHover { hovering in
                    if hovering {
                        withAnimation(.easeOut(duration: 0.08)) { isHovering = true }
                    } else {
                        isHovering = false
                    }
                }
        }
    }
}
