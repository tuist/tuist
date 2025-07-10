import Foundation
import SwiftUI
import TuistNoora

struct PreviewViewMetadataRow<Content: View>: View {
    let title: String
    let content: () -> Content
    var body: some View {
        HStack {
            Text(title)
                .font(.body)
                .foregroundColor(Noora.Colors.surfaceLabelSecondary)

            Spacer()

            content()
        }
        .padding(.vertical, Noora.Spacing.spacing5)
    }
}
