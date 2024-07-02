import Foundation
import Mockable
import Path
import TuistSupport
import XcodeGraph

@Mockable
public protocol BuildsUploadServicing {
    func uploadBuild(
        _ buildPath: AbsolutePath,
        serverURL: URL
    ) async throws
}

public final class BuildsUploadService: BuildsUploadServicing {
    private let fileHandler: FileHandling
    private let fileArchiver: FileArchivingFactorying
    private let retryProvider: RetryProviding
    private let multipartUploadStartBuildsService: MultipartUploadStartBuildsServicing
    private let multipartUploadGenerateURLBuildsService: MultipartUploadGenerateURLBuildsServicing
    private let multipartUploadArtifactService: MultipartUploadArtifactServicing
    private let multipartUploadCompleteBuildsService: MultipartUploadCompleteBuildsServicing

    public convenience init() {
        self.init(
            fileHandler: FileHandler.shared,
            fileArchiver: FileArchivingFactory(),
            retryProvider: RetryProvider(),
            multipartUploadStartBuildsService: MultipartUploadStartBuildsService(),
            multipartUploadGenerateURLBuildsService:
            MultipartUploadGenerateURLBuildsService(),
            multipartUploadArtifactService: MultipartUploadArtifactService(),
            multipartUploadCompleteBuildsService:
            MultipartUploadCompleteBuildsService()
        )
    }

    init(
        fileHandler: FileHandling,
        fileArchiver: FileArchivingFactorying,
        retryProvider: RetryProviding,
        multipartUploadStartBuildsService: MultipartUploadStartBuildsServicing,
        multipartUploadGenerateURLBuildsService: MultipartUploadGenerateURLBuildsServicing,
        multipartUploadArtifactService: MultipartUploadArtifactServicing,
        multipartUploadCompleteBuildsService: MultipartUploadCompleteBuildsServicing
    ) {
        self.fileHandler = fileHandler
        self.fileArchiver = fileArchiver
        self.retryProvider = retryProvider
        self.multipartUploadStartBuildsService = multipartUploadStartBuildsService
        self.multipartUploadGenerateURLBuildsService = multipartUploadGenerateURLBuildsService
        self.multipartUploadArtifactService = multipartUploadArtifactService
        self.multipartUploadCompleteBuildsService = multipartUploadCompleteBuildsService
    }

    public func uploadBuild(
        _ buildPath: AbsolutePath,
        serverURL: URL
    ) async throws {
        // TODO: Create this via a service
        let buildId = UUID().uuidString
        
        let buildPath = try fileArchiver.makeFileArchiver(for: [buildPath]).zip(name: buildPath.basenameWithoutExt)

        try await retryProvider.runWithRetries { [self] in
            let uploadId = try await multipartUploadStartBuildsService.startBuildsMultipartUpload(
                buildId,
                serverURL: serverURL
            )

            let parts = try await multipartUploadArtifactService.multipartUploadArtifact(
                artifactPath: buildPath,
                generateUploadURL: { partNumber in
                    try await self.multipartUploadGenerateURLBuildsService.uploadBuilds(
                        buildId,
                        partNumber: partNumber,
                        uploadId: uploadId,
                        serverURL: serverURL
                    )
                }
            )

            try await multipartUploadCompleteBuildsService.uploadBuildsArtifact(
                buildId,
                uploadId: uploadId,
                parts: parts,
                serverURL: serverURL
            )
            
            // TODO: Return the URL from the server and from the BuildService
            
            if #available(macOS 13.0, *) {
                logger.notice("App uploaded – share it with other using the following link: \(serverURL.appending(components: "builds", buildId).absoluteString)")
            } else {
                // Fallback on earlier versions
            }
        }
    }
}
