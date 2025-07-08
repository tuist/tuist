import Foundation
import NukeUI
import SwiftUI
import TuistNoora
import TuistServer

struct PreviewViewHeader: View {
    let preview: ServerPreview

    var body: some View {
        HStack(spacing: Noora.Spacing.spacing6) {
            LazyImage(url: preview.iconURL) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .scaledToFit()
                } else {
                    Image("PreviewIconPlaceholder")
                        .resizable()
                        .scaledToFit()
                }
            }
            .cornerRadius(Noora.CornerRadius.large)
            .frame(width: 92, height: 92)

            VStack(alignment: .leading, spacing: Noora.Spacing.spacing4) {
                VStack(alignment: .leading, spacing: Noora.Spacing.spacing2) {
                    Text(preview.displayName ?? "App")
                        .font(.title2.weight(.medium))
                        .foregroundColor(Noora.Colors.surfaceLabelPrimary)

                    if let version = preview.version {
                        Text("v\(version.description)")
                            .font(.caption)
                            .foregroundColor(Noora.Colors.surfaceLabelSecondary)
                    }
                }

                PreviewRunButton(preview: preview)
            }

            Spacer()
        }
    }
}
