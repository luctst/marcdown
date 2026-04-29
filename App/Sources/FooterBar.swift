import SwiftUI

struct FooterBar: View {
    let characterCount: Int

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
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
