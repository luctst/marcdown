import SwiftUI

struct FooterBar: View {
    let characterCount: Int
    /// True only when the panel is key and no overlay is active. Driven by
    /// `shouldShowEscHint` so the hint never lies (overlays own their own ESC
    /// semantics; ESC outside the panel doesn't reach us at all).
    var showEscHint: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                if showEscHint {
                    Text("esc to close")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text("\(characterCount) characters")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
    }
}
