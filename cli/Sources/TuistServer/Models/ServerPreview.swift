import Foundation
import TuistSimulator
import XcodeGraph

public struct ServerPreview: Sendable, Equatable, Codable, Identifiable, Hashable {
    public let id: String
    public let url: URL
    public let qrCodeURL: URL
    public let iconURL: URL
    public let deviceURL: URL
    public let version: Version?
    public let bundleIdentifier: String?
    public var displayName: String?
    public let gitCommitSHA: String?
    public let gitBranch: String?
    public let appBuilds: [AppBuild]
    public let supportedPlatforms: [DestinationType]
    public let createdFromCI: Bool
    public let createdBy: ServerAccount?
    public let insertedAt: Date
}

extension ServerPreview {
    private static let dateFormatter = ISO8601DateFormatter()

    init?(_ preview: Components.Schemas.Preview) {
        id = preview.id
        guard let url = URL(string: preview.url),
              let qrCodeURL = URL(string: preview.qr_code_url),
              let iconURL = URL(string: preview.icon_url),
              let deviceURL = URL(string: preview.device_url),
              let insertedAt = Self.dateFormatter.date(from: preview.inserted_at)
        else { return nil }
        self.url = url
        self.qrCodeURL = qrCodeURL
        self.iconURL = iconURL
        self.deviceURL = deviceURL
        if let version = preview.version {
            self.version = Version(string: version)
        } else {
            version = nil
        }
        bundleIdentifier = preview.bundle_identifier
        displayName = preview.display_name
        gitCommitSHA = preview.git_commit_sha
        gitBranch = preview.git_branch
        appBuilds = preview.builds.compactMap(AppBuild.init)
        supportedPlatforms = preview.supported_platforms.map(DestinationType.init)
        createdFromCI = preview.created_from_ci
        if let createdBy = preview.created_by {
            self.createdBy = ServerAccount(createdBy)
        } else {
            createdBy = nil
        }
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
            deviceURL: URL = URL(string: "https://tuist.dev/tuist/tuist/previews/preview-id")!,
            version: Version = "1.0.0",
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
            createdFromCI: Bool = false,
            createdBy: ServerAccount? = .test(),
            insertedAt: Date = Date(timeIntervalSince1970: 0)
        ) -> Self {
            .init(
                id: id,
                url: url,
                qrCodeURL: qrCodeURL,
                iconURL: iconURL,
                deviceURL: deviceURL,
                version: version,
                bundleIdentifier: bundleIdentifier,
                displayName: displayName,
                gitCommitSHA: gitCommitSHA,
                gitBranch: gitBranch,
                appBuilds: appBuilds,
                supportedPlatforms: supportedPlatforms,
                createdFromCI: createdFromCI,
                createdBy: createdBy,
                insertedAt: insertedAt
            )
        }
    }
#endif
