import Foundation

/// Information about an available preview update.
public struct PreviewUpdateInfo: Sendable {
    /// The unique identifier of the new preview.
    public let previewId: String

    /// The display name of the preview.
    public let displayName: String?

    /// The version string of the preview.
    public let version: String?

    /// The bundle identifier of the preview.
    public let bundleIdentifier: String

    /// The git branch associated with the preview.
    public let gitBranch: String?

    /// The URL to download the preview.
    public let downloadURL: URL

    public init(
        previewId: String,
        displayName: String?,
        version: String?,
        bundleIdentifier: String,
        gitBranch: String?,
        downloadURL: URL
    ) {
        self.previewId = previewId
        self.displayName = displayName
        self.version = version
        self.bundleIdentifier = bundleIdentifier
        self.gitBranch = gitBranch
        self.downloadURL = downloadURL
    }
}
