import SwiftUI
import TuistNoora

struct PreviewTrackChip: View {
    let title: String
    let track: String?
    let count: Int?
    let selectedTrack: String?
    let action: () -> Void

    private var isSelected: Bool {
        track.map { selectedTrack?.caseInsensitiveCompare($0) == .orderedSame }
            ?? (selectedTrack == nil)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Noora.Spacing.spacing2) {
                Text(title)
                    .foregroundStyle(isSelected ? .white : Noora.Colors.surfaceLabelPrimary)
                if let count {
                    Text(count.formatted())
                        .foregroundStyle(isSelected ? .white.opacity(0.65) : Noora.Colors.surfaceLabelSecondary)
                }
            }
            .font(.subheadline)
            .padding(.horizontal, Noora.Spacing.spacing4)
            .padding(.vertical, Noora.Spacing.spacing2)
            .background(
                isSelected ? Noora.Colors.buttonPrimaryBackground : Noora.Colors.surfaceBackgroundTertiary,
                in: Capsule()
            )
            .overlay(Capsule().strokeBorder(Noora.Colors.neutralGray24Alpha, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(track ?? "All tracks")
        .accessibilityValue(count.map { "\($0) previews" } ?? "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(track.map { "preview-track-\($0)" } ?? "preview-track-all")
    }
}
