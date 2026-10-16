import SwiftUI
import TuistNoora

public struct PreviewsEmptyStateView: View {
    let title: String
    let subtitle: String

    public init(title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(spacing: Noora.Spacing.spacing6) {
            Image("iPhoneMockup")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 120, height: 240)
                .shadow(color: Color.black.opacity(0.09), radius: 4.28, x: 0, y: 3.67)
                .shadow(color: Color.black.opacity(0.08), radius: 8.56, x: 0, y: 17.11)
                .shadow(color: Color.black.opacity(0.05), radius: 11.0, x: 0, y: 37.89)
                .shadow(color: Color.black.opacity(0.01), radius: 13.45, x: 0, y: 66.0)
                .padding(.top, Noora.Spacing.spacing8)

            Text(title)
                .font(.title3.weight(.medium))
                .foregroundColor(Noora.Colors.surfaceLabelSecondary)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(Noora.Colors.surfaceLabelSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Noora.Spacing.spacing8)
        .padding(.horizontal, Noora.Spacing.spacing7)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Noora.Colors.surfaceBackgroundPrimary)
    }
}
