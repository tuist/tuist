import Foundation
import MockableTest
import TuistSupport
import TuistSupportTesting
import XCTest

@testable import TuistServer

final class AnalyticsArtifactUploadServiceTests: TuistTestCase {
    private var subject: AnalyticsArtifactUploadService!
    private var fileArchiverFactory: MockFileArchivingFactorying!
    private var multipartUploadStartAnalyticsService: MockMultipartUploadStartAnalyticsServicing!
    private var multipartUploadGenerateURLAnalyticsService: MockMultipartUploadGenerateURLAnalyticsServicing!
    private var multipartUploadArtifactService: MockMultipartUploadArtifactServicing!
    private var multipartUploadCompleteAnalyticsService: MockMultipartUploadCompleteAnalyticsServicing!

    override func setUp() {
        super.setUp()

        fileArchiverFactory = .init()
        multipartUploadStartAnalyticsService = .init()
        multipartUploadGenerateURLAnalyticsService = .init()
        multipartUploadArtifactService = .init()
        multipartUploadCompleteAnalyticsService = .init()

        subject = AnalyticsArtifactUploadService(
            fileHandler: fileHandler,
            fileArchiver: fileArchiverFactory,
            multipartUploadStartAnalyticsService: multipartUploadStartAnalyticsService,
            multipartUploadGenerateURLAnalyticsService: multipartUploadGenerateURLAnalyticsService,
            multipartUploadArtifactService: multipartUploadArtifactService,
            multipartUploadCompleteAnalyticsService: multipartUploadCompleteAnalyticsService
        )
    }

    override func tearDown() {
        fileArchiverFactory = nil
        multipartUploadStartAnalyticsService = nil
        multipartUploadGenerateURLAnalyticsService = nil
        multipartUploadArtifactService = nil
        multipartUploadCompleteAnalyticsService = nil

        super.tearDown()
    }

    func test_upload_analytics_artifact() async throws {
        // Given
        let temporaryDirectory = try temporaryPath()
        let artifactPath = temporaryDirectory.appending(component: "artifact.bundle")
        try FileHandler.shared.touch(artifactPath)

        let serverURL: URL = .test()

        let fileArchiver = MockFileArchiving()
        given(fileArchiverFactory)
            .makeFileArchiver(for: .value([artifactPath]))
            .willReturn(fileArchiver)

        let artifactArchivePath = temporaryDirectory.appending(component: "artifact.zip")

        given(fileArchiver)
            .zip(name: .value("artifact"))
            .willReturn(artifactArchivePath)

        given(multipartUploadStartAnalyticsService)
            .uploadAnalyticsArtifact(
                commandEventId: .value(1),
                serverURL: .value(serverURL)
            )
            .willReturn("upload-id")

        given(multipartUploadArtifactService)
            .multipartUploadArtifact(
                artifactPath: .value(artifactArchivePath),
                generateUploadURL: .any
            )
            .willReturn([(etag: "etag", partNumber: 1)])

        given(multipartUploadCompleteAnalyticsService)
            .uploadAnalyticsArtifact(
                commandEventId: .value(1),
                uploadId: .value("upload-id"),
                parts: .matching { parts in
                    parts.map(\.etag) == ["etag"] && parts.map(\.partNumber) == [1]
                },
                serverURL: .value(serverURL)
            )
            .willReturn(())

        // When / Then
        try await subject.uploadAnalyticsArtifact(
            artifactPath: artifactPath,
            commandEventId: 1,
            serverURL: serverURL
        )
    }
}
