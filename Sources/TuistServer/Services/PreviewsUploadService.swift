import Foundation
import Mockable
import Path
import TuistSupport
import XcodeGraph

@Mockable
public protocol PreviewsUploadServicing {
    func uploadPreviews(
        displayName: String,
        previewPaths: [AbsolutePath],
        fullHandle: String,
        serverURL: URL
    ) async throws -> Preview
}

public final class PreviewsUploadService: PreviewsUploadServicing {
    private let fileHandler: FileHandling
    private let fileArchiver: FileArchivingFactorying
    private let retryProvider: RetryProviding
    private let multipartUploadStartPreviewsService: MultipartUploadStartPreviewsServicing
    private let multipartUploadGenerateURLPreviewsService: MultipartUploadGenerateURLPreviewsServicing
    private let multipartUploadArtifactService: MultipartUploadArtifactServicing
    private let multipartUploadCompletePreviewsService: MultipartUploadCompletePreviewsServicing

    public convenience init() {
        self.init(
            fileHandler: FileHandler.shared,
            fileArchiver: FileArchivingFactory(),
            retryProvider: RetryProvider(),
            multipartUploadStartPreviewsService: MultipartUploadStartPreviewsService(),
            multipartUploadGenerateURLPreviewsService:
            MultipartUploadGenerateURLPreviewsService(),
            multipartUploadArtifactService: MultipartUploadArtifactService(),
            multipartUploadCompletePreviewsService:
            MultipartUploadCompletePreviewsService()
        )
    }

    init(
        fileHandler: FileHandling,
        fileArchiver: FileArchivingFactorying,
        retryProvider: RetryProviding,
        multipartUploadStartPreviewsService: MultipartUploadStartPreviewsServicing,
        multipartUploadGenerateURLPreviewsService: MultipartUploadGenerateURLPreviewsServicing,
        multipartUploadArtifactService: MultipartUploadArtifactServicing,
        multipartUploadCompletePreviewsService: MultipartUploadCompletePreviewsServicing
    ) {
        self.fileHandler = fileHandler
        self.fileArchiver = fileArchiver
        self.retryProvider = retryProvider
        self.multipartUploadStartPreviewsService = multipartUploadStartPreviewsService
        self.multipartUploadGenerateURLPreviewsService = multipartUploadGenerateURLPreviewsService
        self.multipartUploadArtifactService = multipartUploadArtifactService
        self.multipartUploadCompletePreviewsService = multipartUploadCompletePreviewsService
    }

    public func uploadPreviews(
        displayName: String,
        previewPaths: [AbsolutePath],
        fullHandle: String,
        serverURL: URL
    ) async throws -> Preview {
        let buildPath = try fileArchiver.makeFileArchiver(for: previewPaths).zip(name: "previews.zip")

        return try await retryProvider.runWithRetries { [self] in
            let previewUpload = try await multipartUploadStartPreviewsService.startPreviewsMultipartUpload(
                displayName: displayName,
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
