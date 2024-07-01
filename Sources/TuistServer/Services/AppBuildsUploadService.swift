import Foundation
import Mockable
import Path
import TuistSupport
import XcodeGraph

@Mockable
public protocol AppBuildsUploadServicing {
    func uploadAppBuilds(
        _ appBuildPaths: [AbsolutePath],
        fullHandle: String,
        serverURL: URL
    ) async throws -> URL
}

public final class AppBuildsUploadService: AppBuildsUploadServicing {
    private let fileHandler: FileHandling
    private let fileArchiver: FileArchivingFactorying
    private let retryProvider: RetryProviding
    private let multipartUploadStartAppBuildsService: MultipartUploadStartAppBuildsServicing
    private let multipartUploadGenerateURLAppBuildsService: MultipartUploadGenerateURLAppBuildsServicing
    private let multipartUploadArtifactService: MultipartUploadArtifactServicing
    private let multipartUploadCompleteAppBuildsService: MultipartUploadCompleteAppBuildsServicing

    public convenience init() {
        self.init(
            fileHandler: FileHandler.shared,
            fileArchiver: FileArchivingFactory(),
            retryProvider: RetryProvider(),
            multipartUploadStartAppBuildsService: MultipartUploadStartAppBuildsService(),
            multipartUploadGenerateURLAppBuildsService:
            MultipartUploadGenerateURLAppBuildsService(),
            multipartUploadArtifactService: MultipartUploadArtifactService(),
            multipartUploadCompleteAppBuildsService:
            MultipartUploadCompleteBuildsService()
        )
    }

    init(
        fileHandler: FileHandling,
        fileArchiver: FileArchivingFactorying,
        retryProvider: RetryProviding,
        multipartUploadStartAppBuildsService: MultipartUploadStartAppBuildsServicing,
        multipartUploadGenerateURLAppBuildsService: MultipartUploadGenerateURLAppBuildsServicing,
        multipartUploadArtifactService: MultipartUploadArtifactServicing,
        multipartUploadCompleteAppBuildsService: MultipartUploadCompleteAppBuildsServicing
    ) {
        self.fileHandler = fileHandler
        self.fileArchiver = fileArchiver
        self.retryProvider = retryProvider
        self.multipartUploadStartAppBuildsService = multipartUploadStartAppBuildsService
        self.multipartUploadGenerateURLAppBuildsService = multipartUploadGenerateURLAppBuildsService
        self.multipartUploadArtifactService = multipartUploadArtifactService
        self.multipartUploadCompleteAppBuildsService = multipartUploadCompleteAppBuildsService
    }

    public func uploadAppBuilds(
        _ appBuildPaths: [AbsolutePath],
        fullHandle: String,
        serverURL: URL
    ) async throws -> URL {
        let buildPath = try fileArchiver.makeFileArchiver(for: appBuildPaths).zip(name: "app-builds.zip")

        return try await retryProvider.runWithRetries { [self] in
            let appBuildUpload = try await multipartUploadStartAppBuildsService.startAppBuildsMultipartUpload(
                fullHandle: fullHandle,
                serverURL: serverURL
            )

            let parts = try await multipartUploadArtifactService.multipartUploadArtifact(
                artifactPath: buildPath,
                generateUploadURL: { partNumber in
                    try await self.multipartUploadGenerateURLAppBuildsService.uploadAppBuilds(
                        appBuildUpload.appBuildId,
                        partNumber: partNumber,
                        uploadId: appBuildUpload.uploadId,
                        fullHandle: fullHandle,
                        serverURL: serverURL
                    )
                }
            )

            return try await multipartUploadCompleteAppBuildsService.completeAppBuildUpload(
                appBuildUpload.appBuildId,
                uploadId: appBuildUpload.uploadId,
                parts: parts,
                fullHandle: fullHandle,
                serverURL: serverURL
            )
        }
    }
}
