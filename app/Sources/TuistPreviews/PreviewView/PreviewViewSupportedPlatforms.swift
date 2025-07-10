import Foundation
import SwiftUI
import TuistNoora
import TuistSimulator

struct PreviewViewSupportedPlatforms: View {
    let supportedPlatforms: [DestinationType]

    var body: some View {
        VStack(alignment: .leading, spacing: Noora.Spacing.spacing4) {
            HStack {
                Text("Supported platforms")
                    .font(.title2.weight(.medium))
                    .foregroundColor(Noora.Colors.surfaceLabelPrimary)
                Spacer()
            }

            FlowLayout(spacing: Noora.Spacing.spacing5) {
                ForEach(supportedPlatforms, id: \.self) { platform in
                    platformPill(for: platform)
                }
            }
        }
    }

    private func platformPill(for platform: DestinationType) -> some View {
        HStack(spacing: Noora.Spacing.spacing1) {
            NooraIcon(platformIcon(for: platform))
                .frame(width: 20, height: 20)
                .foregroundColor(Noora.Colors.surfaceLabelPrimary)
            Text(platformTitle(for: platform))
                .font(.subheadline.weight(.medium))
                .foregroundColor(Noora.Colors.surfaceLabelPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, Noora.Spacing.spacing4)
        .padding(.vertical, Noora.Spacing.spacing2)
        .background(Noora.Colors.surfaceBackgroundSecondary)
        .cornerRadius(Noora.CornerRadius.small)
    }

    private func platformTitle(for platform: DestinationType) -> String {
        switch platform {
        case let .device(platform):
            return platform.caseValue
        case let .simulator(platform):
            return "\(platform.caseValue) Simulator"
        }
    }

    private func platformIcon(for platform: DestinationType) -> NooraIcon.Icon {
        switch platform {
        case .device(.iOS): .deviceMobile
        case .simulator(.iOS): .deviceMobileShare
        case .device(.macOS), .simulator(.macOS): .deviceLaptop
        case .device(.tvOS): .deviceDesktop
        case .simulator(.tvOS): .deviceDesktopShare
        case .device(.visionOS): .deviceVisionPro
        case .simulator(.visionOS): .deviceVisionProShare
        case .device(.watchOS): .deviceWatch
        case .simulator(.watchOS): .deviceWatchShare
        }
    }
}
