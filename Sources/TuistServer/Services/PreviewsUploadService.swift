import FileSystem
import Foundation
import Mockable
import Path
import TuistCore
import TuistSupport

public enum PreviewUploadType: Equatable {
    case ipa(AbsolutePath)
    case appBundles([AbsolutePath])
}

@Mockable
public protocol PreviewsUploadServicing {
    func uploadPreviews(
        _ previewUploadType: PreviewUploadType,
        displayName: String,
        version: String?,
        bundleIdentifier: String?,
        icon: AbsolutePath?,
        supportedPlatforms: [DestinationType],
        path: AbsolutePath,
        fullHandle: String,
        serverURL: URL
    ) async throws -> Preview
}

public struct PreviewsUploadService: PreviewsUploadServicing {
    private let fileSystem: FileSysteming
    private let fileArchiver: FileArchivingFactorying
    private let retryProvider: RetryProviding
    private let multipartUploadStartPreviewsService: MultipartUploadStartPreviewsServicing
    private let multipartUploadGenerateURLPreviewsService: MultipartUploadGenerateURLPreviewsServicing
    private let multipartUploadArtifactService: MultipartUploadArtifactServicing
    private let multipartUploadCompletePreviewsService: MultipartUploadCompletePreviewsServicing
    private let uploadPreviewIconService: UploadPreviewIconServicing
    private let gitController: GitControlling

    public init() {
        self.init(
            fileSystem: FileSystem(),
            fileArchiver: FileArchivingFactory(),
            retryProvider: RetryProvider(),
            multipartUploadStartPreviewsService: MultipartUploadStartPreviewsService(),
            multipartUploadGenerateURLPreviewsService:
            MultipartUploadGenerateURLPreviewsService(),
            multipartUploadArtifactService: MultipartUploadArtifactService(),
            multipartUploadCompletePreviewsService:
            MultipartUploadCompletePreviewsService(),
            uploadPreviewIconService: UploadPreviewIconService(),
            gitController: GitController()
        )
    }

    init(
        fileSystem: FileSysteming,
        fileArchiver: FileArchivingFactorying,
        retryProvider: RetryProviding,
        multipartUploadStartPreviewsService: MultipartUploadStartPreviewsServicing,
        multipartUploadGenerateURLPreviewsService: MultipartUploadGenerateURLPreviewsServicing,
        multipartUploadArtifactService: MultipartUploadArtifactServicing,
        multipartUploadCompletePreviewsService: MultipartUploadCompletePreviewsServicing,
        uploadPreviewIconService: UploadPreviewIconServicing,
        gitController: GitControlling
    ) {
        self.fileSystem = fileSystem
        self.fileArchiver = fileArchiver
        self.retryProvider = retryProvider
        self.multipartUploadStartPreviewsService = multipartUploadStartPreviewsService
        self.multipartUploadGenerateURLPreviewsService = multipartUploadGenerateURLPreviewsService
        self.multipartUploadArtifactService = multipartUploadArtifactService
        self.multipartUploadCompletePreviewsService = multipartUploadCompletePreviewsService
        self.uploadPreviewIconService = uploadPreviewIconService
        self.gitController = gitController
    }

    public func uploadPreviews(
        _ previewUploadType: PreviewUploadType,
        displayName: String,
        version: String?,
        bundleIdentifier: String?,
        icon: AbsolutePath?,
        supportedPlatforms: [DestinationType],
        path: AbsolutePath,
        fullHandle: String,
        serverURL: URL
    ) async throws -> Preview {
        let previewType: PreviewType
        let buildPath: AbsolutePath
        switch previewUploadType {
        case let .ipa(ipaPath):
            buildPath = ipaPath
            previewType = .ipa
        case let .appBundles(previewPaths):
            buildPath = try await fileArchiver.makeFileArchiver(for: previewPaths).zip(name: "previews.zip")
            previewType = .appBundle
        }

        let gitCommitSHA: String?
        let gitBranch: String?
        if gitController.isInGitRepository(workingDirectory: path) {
            if gitController.hasCurrentBranchCommits(workingDirectory: path) {
                gitCommitSHA = try gitController.currentCommitSHA(workingDirectory: path)
            } else {
                gitCommitSHA = nil
            }

            gitBranch = try gitController.currentBranch(workingDirectory: path)
        } else {
            gitCommitSHA = nil
            gitBranch = nil
        }

        let preview = try await retryProvider.runWithRetries {
            let previewUpload = try await multipartUploadStartPreviewsService.startPreviewsMultipartUpload(
                type: previewType,
                displayName: displayName,
                version: version,
                bundleIdentifier: bundleIdentifier,
                supportedPlatforms: supportedPlatforms,
                gitBranch: gitBranch,
                gitCommitSHA: gitCommitSHA,
                fullHandle: fullHandle,
                serverURL: serverURL
            )

            let parts = try await multipartUploadArtifactService.multipartUploadArtifact(
                artifactPath: buildPath,
                generateUploadURL: { part in
                    try await multipartUploadGenerateURLPreviewsService.uploadPreviews(
                        previewUpload.previewId,
                        partNumber: part.number,
                        uploadId: previewUpload.uploadId,
                        fullHandle: fullHandle,
                        serverURL: serverURL,
                        contentLength: part.contentLength
                    )
                }
            )

            return try await multipartUploadCompletePreviewsService.completePreviewUpload(
                previewUpload.previewId,
                uploadId: previewUpload.uploadId,
                parts: parts,
                fullHandle: fullHandle,
                serverURL: serverURL
            )
        }

        if let icon {
            try await uploadPreviewIconService.uploadPreviewIcon(
                icon,
                preview: preview,
                serverURL: serverURL,
                fullHandle: fullHandle
            )
        }

        return preview
    }
}
