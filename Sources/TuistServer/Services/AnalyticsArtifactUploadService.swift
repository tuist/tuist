import Foundation
import Mockable
import TSCBasic
import TuistSupport

@Mockable
public protocol AnalyticsArtifactUploadServicing {
    func uploadAnalyticsArtifact(
        artifactPath: AbsolutePath,
        commandEventId: Int,
        serverURL: URL
    ) async throws
}

public final class AnalyticsArtifactUploadService: AnalyticsArtifactUploadServicing {
    private let fileHandler: FileHandling
    private let fileArchiver: FileArchivingFactorying
    private let retryProvider: RetryProviding
    private let multipartUploadStartAnalyticsService: MultipartUploadStartAnalyticsServicing
    private let multipartUploadGenerateURLAnalyticsService: MultipartUploadGenerateURLAnalyticsServicing
    private let multipartUploadArtifactService: MultipartUploadArtifactServicing
    private let multipartUploadCompleteAnalyticsService: MultipartUploadCompleteAnalyticsServicing

    public init(
        fileHandler: FileHandling = FileHandler.shared,
        fileArchiver: FileArchivingFactorying = FileArchivingFactory(),
        retryProvider: RetryProviding = RetryProvider(),
        multipartUploadStartAnalyticsService: MultipartUploadStartAnalyticsServicing = MultipartUploadStartAnalyticsService(),
        multipartUploadGenerateURLAnalyticsService: MultipartUploadGenerateURLAnalyticsServicing =
            MultipartUploadGenerateURLAnalyticsService(),
        multipartUploadArtifactService: MultipartUploadArtifactServicing = MultipartUploadArtifactService(),
        multipartUploadCompleteAnalyticsService: MultipartUploadCompleteAnalyticsServicing =
            MultipartUploadCompleteAnalyticsService()
    ) {
        self.fileHandler = fileHandler
        self.fileArchiver = fileArchiver
        self.retryProvider = retryProvider
        self.multipartUploadStartAnalyticsService = multipartUploadStartAnalyticsService
        self.multipartUploadGenerateURLAnalyticsService = multipartUploadGenerateURLAnalyticsService
        self.multipartUploadArtifactService = multipartUploadArtifactService
        self.multipartUploadCompleteAnalyticsService = multipartUploadCompleteAnalyticsService
    }

    public func uploadAnalyticsArtifact(
        artifactPath: AbsolutePath,
        commandEventId: Int,
        serverURL: URL
    ) async throws {
        let artifactArchivePath = try fileArchiver.makeFileArchiver(for: [artifactPath])
            .zip(name: artifactPath.basenameWithoutExt)

        try await retryProvider.runWithRetries { [self] in
            let uploadId = try await multipartUploadStartAnalyticsService.uploadAnalyticsArtifact(
                commandEventId: commandEventId,
                serverURL: serverURL
            )

            let parts = try await multipartUploadArtifactService.multipartUploadArtifact(
                artifactPath: artifactArchivePath,
                generateUploadURL: { partNumber in
                    try await self.multipartUploadGenerateURLAnalyticsService.uploadAnalytics(
                        commandEventId: commandEventId,
                        partNumber: partNumber,
                        uploadId: uploadId,
                        serverURL: serverURL
                    )
                }
            )

            try await multipartUploadCompleteAnalyticsService.uploadAnalyticsArtifact(
                commandEventId: commandEventId,
                uploadId: uploadId,
                parts: parts,
                serverURL: serverURL
            )
        }
    }
}
