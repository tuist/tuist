import Foundation
import SwiftUI
import TuistNoora
import TuistServer

struct PreviewViewCreatedByBadge: View {
    let preview: ServerPreview

    var body: some View {
        HStack(spacing: Noora.Spacing.spacing2) {
            NooraIcon(preview.createdFromCI ? .settings : .user)
                .foregroundStyle(Noora.Colors.badgeInformationLabel)
                .frame(width: 20, height: 20)
            Text(createdBy)
                .font(.body.weight(.medium))
                .foregroundStyle(Noora.Colors.badgeInformationLabel)
        }
        .padding(Noora.Spacing.spacing2)
        .background(Noora.Colors.badgeInformationBackground)
        .cornerRadius(Noora.CornerRadius.medium)
    }

    private var createdBy: String {
        if preview.createdFromCI {
            "CI"
        } else {
            preview.createdBy?.handle ?? "Unknown"
        }
    }
}
