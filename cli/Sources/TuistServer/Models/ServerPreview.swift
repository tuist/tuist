import Foundation
import TuistSimulator
import XcodeGraph

public struct ServerPreview: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let url: URL
    public let qrCodeURL: URL
    public let iconURL: URL
    public let bundleIdentifier: String?
    public var displayName: String?
    public let gitCommitSHA: String?
    public let gitBranch: String?
    public let appBuilds: [AppBuild]
    public let supportedPlatforms: [DestinationType]
    public let insertedAt: Date
}

extension ServerPreview {
    private static let dateFormatter = ISO8601DateFormatter()

    init?(_ preview: Components.Schemas.Preview) {
        id = preview.id
        guard let url = URL(string: preview.url),
              let qrCodeURL = URL(string: preview.qr_code_url),
              let iconURL = URL(string: preview.icon_url),
              let insertedAt = Self.dateFormatter.date(from: preview.inserted_at)
        else { return nil }
        self.url = url
        self.qrCodeURL = qrCodeURL
        self.iconURL = iconURL
        bundleIdentifier = preview.bundle_identifier
        displayName = preview.display_name
        gitCommitSHA = preview.git_commit_sha
        gitBranch = preview.git_branch
        appBuilds = preview.builds.compactMap(AppBuild.init)
        supportedPlatforms = preview.supported_platforms.map(DestinationType.init)
        self.insertedAt = insertedAt
    }
}

#if DEBUG
    extension ServerPreview {
        public static func test(
            id: String = "preview-id",
            url: URL = URL(string: "https://tuist.dev/tuist/tuist/previews/preview-id")!,
            // swiftlint:disable:this force_try,
            qrCodeURL: URL =
                URL(string: "https://tuist.dev/tuist/tuist/previews/preview-id/qr-code.svg")!,
            // swiftlint:disable:this force_try
            iconURL: URL =
                URL(string: "https://tuist.dev/tuist/tuist/previews/preview-id/icon.png")!,
            // swiftlint:disable:this force_try
            bundleIdentifier: String? = "dev.tuist.app",
            displayName: String? = "App",
            gitCommitSHA: String? = nil,
            gitBranch: String? = nil,
            appBuilds: [AppBuild] = [
                .test(),
            ],
            supportedPlatforms: [DestinationType] = [
                .device(.iOS),
                .simulator(.iOS),
            ],
            insertedAt: Date = Date(timeIntervalSince1970: 0)
        ) -> Self {
            .init(
                id: id,
                url: url,
                qrCodeURL: qrCodeURL,
                iconURL: iconURL,
                bundleIdentifier: bundleIdentifier,
                displayName: displayName,
                gitCommitSHA: gitCommitSHA,
                gitBranch: gitBranch,
                appBuilds: appBuilds,
                supportedPlatforms: supportedPlatforms,
                insertedAt: insertedAt
            )
        }
    }
#endif
