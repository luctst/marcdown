import MarcdownCore
import SwiftUI

struct HeaderBar: View {
    let title: String
    let onCommandPalette: () -> Void
    let onQuickSwitcher: () -> Void
    let onNewNote: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                HStack(spacing: 4) {
                    Button(action: onCommandPalette) {
                        Image(systemName: "command")
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Command Palette")
                    Button(action: onQuickSwitcher) {
                        Image(systemName: "list.bullet")
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Browse Notes")
                    Button(action: onNewNote) {
                        Image(systemName: "plus")
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("New Note")
                }
                .buttonStyle(.borderless)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            Divider()
        }
    }
}
