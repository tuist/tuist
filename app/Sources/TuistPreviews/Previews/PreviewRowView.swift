import Foundation
import NukeUI
import SwiftUI
import TuistNoora
import TuistServer

struct PreviewRowView: View {
    let preview: ServerPreview
    @State private var isLoading = false

    private let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
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
                .cornerRadius(Noora.CornerRadius.medium)
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: Noora.Spacing.spacing2) {
                    HStack(spacing: Noora.Spacing.spacing4) {
                        if let commitSHA = preview.gitCommitSHA {
                            HStack(spacing: Noora.Spacing.spacing1) {
                                NooraIcon(.timelineEvent)
                                    .foregroundColor(Noora.Colors.surfaceLabelSecondary)
                                    .frame(width: 12, height: 12)
                                Text(String(commitSHA.prefix(7)))
                                    .font(.caption2)
                                    .foregroundColor(Noora.Colors.surfaceLabelSecondary)
                            }
                        }

                        Spacer()
                    }

                    Text(preview.displayName ?? "App")
                        .font(.headline.weight(.medium))
                        .foregroundColor(Noora.Colors.surfaceLabelPrimary)
                        .lineLimit(1)

                    HStack(spacing: Noora.Spacing.spacing4) {
                        HStack(spacing: Noora.Spacing.spacing1) {
                            NooraIcon(.history)
                                .foregroundColor(Noora.Colors.surfaceLabelSecondary)
                                .frame(width: 12, height: 12)
                            Text(relativeDateFormatter.localizedString(for: preview.insertedAt, relativeTo: Date()))
                                .font(.caption2)
                                .foregroundColor(Noora.Colors.surfaceLabelSecondary)
                        }

                        if let branch = preview.gitBranch {
                            HStack(spacing: Noora.Spacing.spacing1) {
                                NooraIcon(.gitBranch)
                                    .foregroundColor(Noora.Colors.surfaceLabelSecondary)
                                    .frame(width: 12, height: 12)
                                Text(branch)
                                    .font(.caption2)
                                    .foregroundColor(Noora.Colors.surfaceLabelSecondary)
                            }
                        }
                    }
                }

                NooraButton(
                    title: "Run",
                    isLoading: isLoading,
                    isDisabled: !preview.appBuilds
                        .contains(where: { $0.type == .ipa && $0.supportedPlatforms.contains(.device(.iOS)) })
                ) {
                    isLoading = true
                    let url =
                        URL(string: "itms-services://?action=download-manifest&url=\(preview.url.absoluteString)/manifest.plist")!
                    UIApplication.shared.open(url)

                    Task {
                        // It takes some time for the alert to install the app to appear
                        // We don't have a way to hook into the alert displaying, so we're using a hardcoded value to signal that
                        // something was triggered.
                        try await Task.sleep(for: .seconds(2))
                        isLoading = false
                    }
                }
            }
            .padding(Noora.Spacing.spacing5)

            NooraDivider()
        }
    }
}
