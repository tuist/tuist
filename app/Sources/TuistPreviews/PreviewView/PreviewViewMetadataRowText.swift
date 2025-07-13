import Foundation
import SwiftUI
import TuistNoora

struct PreviewViewMetadataRowText: View {
    let content: String

    init(_ content: String) {
        self.content = content
    }

    var body: some View {
        Text(content)
            .font(.body.weight(.medium))
            .foregroundStyle(Noora.Colors.surfaceLabelPrimary)
            .padding(Noora.Spacing.spacing2)
    }
}
