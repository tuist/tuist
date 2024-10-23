import FileSystem
import Foundation
import Mockable
import Path
import TuistSupport
import XcodeGraph

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
            MultipartUploadCompletePreviewsService()
        )
    }

    init(
        fileSystem: FileSysteming,
        fileArchiver: FileArchivingFactorying,
        retryProvider: RetryProviding,
        multipartUploadStartPreviewsService: MultipartUploadStartPreviewsServicing,
        multipartUploadGenerateURLPreviewsService: MultipartUploadGenerateURLPreviewsServicing,
        multipartUploadArtifactService: MultipartUploadArtifactServicing,
        multipartUploadCompletePreviewsService: MultipartUploadCompletePreviewsServicing
    ) {
        self.fileSystem = fileSystem
        self.fileArchiver = fileArchiver
        self.retryProvider = retryProvider
        self.multipartUploadStartPreviewsService = multipartUploadStartPreviewsService
        self.multipartUploadGenerateURLPreviewsService = multipartUploadGenerateURLPreviewsService
        self.multipartUploadArtifactService = multipartUploadArtifactService
        self.multipartUploadCompletePreviewsService = multipartUploadCompletePreviewsService
    }

    public func uploadPreviews(
        _ previewUploadType: PreviewUploadType,
        displayName: String,
        version: String?,
        bundleIdentifier: String?,
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

        return try await retryProvider.runWithRetries {
            let previewUpload = try await multipartUploadStartPreviewsService.startPreviewsMultipartUpload(
                type: previewType,
                displayName: displayName,
                version: version,
                bundleIdentifier: bundleIdentifier,
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
    }
}
