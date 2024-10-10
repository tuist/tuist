import Foundation
import Mockable
import Path
import TuistSupport
import XcodeGraph
import TuistAutomation
import FileSystem

@Mockable
public protocol PreviewsUploadServicing {
    func uploadPreviews(
        displayName: String,
        version: String?,
        appId: String?,
        previewPaths: [AbsolutePath],
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
    private let appBundleLoader: AppBundleLoading

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
            appBundleLoader: AppBundleLoader()
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
        appBundleLoader: AppBundleLoading
    ) {
        self.fileSystem = fileSystem
        self.fileArchiver = fileArchiver
        self.retryProvider = retryProvider
        self.multipartUploadStartPreviewsService = multipartUploadStartPreviewsService
        self.multipartUploadGenerateURLPreviewsService = multipartUploadGenerateURLPreviewsService
        self.multipartUploadArtifactService = multipartUploadArtifactService
        self.multipartUploadCompletePreviewsService = multipartUploadCompletePreviewsService
        self.appBundleLoader = appBundleLoader
    }

    public func uploadPreviews(
        displayName: String,
        version: String?,
        appId: String?,
        previewPaths: [AbsolutePath],
        fullHandle: String,
        serverURL: URL
    ) async throws -> Preview {
        let buildPath: AbsolutePath
        let previewType: PreviewType
        if previewPaths.count == 1, previewPaths[0].extension == "ipa" {
            buildPath = previewPaths[0]
            previewType = .archive
        } else {
            buildPath = try await fileArchiver.makeFileArchiver(for: previewPaths).zip(name: "previews.zip")
            previewType = .bundle
        }

        return try await retryProvider.runWithRetries {
            let previewUpload = try await multipartUploadStartPreviewsService.startPreviewsMultipartUpload(
                type: previewType,
                displayName: displayName,
                version: version,
                appId: appId,
                fullHandle: fullHandle,
                serverURL: serverURL
            )

            let parts = try await multipartUploadArtifactService.multipartUploadArtifact(
                artifactPath: buildPath,
                generateUploadURL: { partNumber in
                    try await self.multipartUploadGenerateURLPreviewsService.uploadPreviews(
                        previewUpload.previewId,
                        partNumber: partNumber,
                        uploadId: previewUpload.uploadId,
                        fullHandle: fullHandle,
                        serverURL: serverURL
                    )
                }
            )

            let previewURL = try await multipartUploadCompletePreviewsService.completePreviewUpload(
                previewUpload.previewId,
                uploadId: previewUpload.uploadId,
                parts: parts,
                fullHandle: fullHandle,
                serverURL: serverURL
            )

            return Preview(
                id: previewUpload.previewId,
                url: previewURL
            )
        }
    }
}
