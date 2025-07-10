import Foundation
import SwiftUI
import TuistNoora

struct ExternalLinkRow: View {
    @Environment(\.openURL) private var openURL

    let title: String
    let url: URL

    var body: some View {
        Button(action: {
            openURL(url)
        }) {
            HStack {
                Text(title)
                    .font(.body)
                    .foregroundColor(Noora.Colors.surfaceLabelPrimary)
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .font(.title3.weight(.regular))
                    .foregroundColor(Noora.Colors.surfaceLabelTertiary)
            }
        }
    }
}
