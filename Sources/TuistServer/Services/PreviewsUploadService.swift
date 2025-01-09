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
            uploadPreviewIconService: UploadPreviewIconService()
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
        uploadPreviewIconService: UploadPreviewIconServicing
    ) {
        self.fileSystem = fileSystem
        self.fileArchiver = fileArchiver
        self.retryProvider = retryProvider
        self.multipartUploadStartPreviewsService = multipartUploadStartPreviewsService
        self.multipartUploadGenerateURLPreviewsService = multipartUploadGenerateURLPreviewsService
        self.multipartUploadArtifactService = multipartUploadArtifactService
        self.multipartUploadCompletePreviewsService = multipartUploadCompletePreviewsService
        self.uploadPreviewIconService = uploadPreviewIconService
    }

    public func uploadPreviews(
        _ previewUploadType: PreviewUploadType,
        displayName: String,
        version: String?,
        bundleIdentifier: String?,
        icon: AbsolutePath?,
        supportedPlatforms: [DestinationType],
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

        let preview = try await retryProvider.runWithRetries {
            let previewUpload = try await multipartUploadStartPreviewsService.startPreviewsMultipartUpload(
                type: previewType,
                displayName: displayName,
                version: version,
                bundleIdentifier: bundleIdentifier,
                supportedPlatforms: supportedPlatforms,
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
