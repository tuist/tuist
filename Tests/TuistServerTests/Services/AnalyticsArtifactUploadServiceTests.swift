import Foundation
import MockableTest
import TuistSupport
import TuistSupportTesting
import XcodeGraph
import XCTest

@testable import TuistServer

final class AnalyticsArtifactUploadServiceTests: TuistTestCase {
    private var subject: AnalyticsArtifactUploadService!
    private var xcresultToolController: MockXCResultToolControlling!
    private var fileArchiverFactory: MockFileArchivingFactorying!
    private var multipartUploadStartAnalyticsService: MockMultipartUploadStartAnalyticsServicing!
    private var multipartUploadGenerateURLAnalyticsService: MockMultipartUploadGenerateURLAnalyticsServicing!
    private var multipartUploadArtifactService: MockMultipartUploadArtifactServicing!
    private var multipartUploadCompleteAnalyticsService: MockMultipartUploadCompleteAnalyticsServicing!
    private var completeAnalyticsArtifactsUploadsService: MockCompleteAnalyticsArtifactsUploadsServicing!

    override func setUp() {
        super.setUp()

        xcresultToolController = .init()
        fileArchiverFactory = .init()
        multipartUploadStartAnalyticsService = .init()
        multipartUploadGenerateURLAnalyticsService = .init()
        multipartUploadArtifactService = .init()
        multipartUploadCompleteAnalyticsService = .init()
        completeAnalyticsArtifactsUploadsService = .init()

        subject = AnalyticsArtifactUploadService(
            fileHandler: fileHandler,
            xcresultToolController: xcresultToolController,
            fileArchiver: fileArchiverFactory,
            retryProvider: RetryProvider(),
            multipartUploadStartAnalyticsService: multipartUploadStartAnalyticsService,
            multipartUploadGenerateURLAnalyticsService: multipartUploadGenerateURLAnalyticsService,
            multipartUploadArtifactService: multipartUploadArtifactService,
            multipartUploadCompleteAnalyticsService: multipartUploadCompleteAnalyticsService,
            completeAnalyticsArtifactsUploadsService: completeAnalyticsArtifactsUploadsService
        )
    }

    override func tearDown() {
        fileArchiverFactory = nil
        multipartUploadStartAnalyticsService = nil
        multipartUploadGenerateURLAnalyticsService = nil
        multipartUploadArtifactService = nil
        multipartUploadCompleteAnalyticsService = nil
        completeAnalyticsArtifactsUploadsService = nil

        super.tearDown()
    }

    func test_upload_analytics_artifact() async throws {
        // Given
        let temporaryDirectory = try temporaryPath()
        let resultBundle = temporaryDirectory.appending(component: "artifact.bundle")
        try FileHandler.shared.touch(resultBundle)

        let serverURL: URL = .test()

        let fileArchiver = MockFileArchiving()
        given(fileArchiverFactory)
            .makeFileArchiver(for: .value([resultBundle]))
            .willReturn(fileArchiver)

        let artifactArchivePath = temporaryDirectory.appending(component: "artifact.zip")

        given(fileArchiver)
            .zip(name: .value("artifact"))
            .willReturn(artifactArchivePath)

        given(multipartUploadStartAnalyticsService)
            .uploadAnalyticsArtifact(
                .value(.init(type: .resultBundle)),
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
                .any,
                commandEventId: .value(1),
                uploadId: .value("upload-id"),
                parts: .matching { parts in
                    parts.map(\.etag) == ["etag"] && parts.map(\.partNumber) == [1]
                },
                serverURL: .value(serverURL)
            )
            .willReturn(())

        given(multipartUploadStartAnalyticsService)
            .uploadAnalyticsArtifact(
                .value(.init(type: .invocationRecord)),
                commandEventId: .value(1),
                serverURL: .value(serverURL)
            )
            .willReturn("upload-id")

        given(multipartUploadArtifactService)
            .multipartUploadArtifact(
                artifactPath: .value(resultBundle.parentDirectory.appending(component: "invocation_record.json")),
                generateUploadURL: .any
            )
            .willReturn([(etag: "etag", partNumber: 1)])

        given(xcresultToolController)
            .resultBundleObject(.value(resultBundle))
            .willReturn(invocationRecordMockString)

        let testResultBundleObjectId =
            "0~8YCjlb3k7BnCmnR4_ZFg18UnVp4hOkZw8KiWEX8RunY_pe9wBaIbW90Jo1HePHl7st5Le_nRyAP4_dSvsdxYpw=="

        given(xcresultToolController)
            .resultBundleObject(.value(resultBundle), id: .value(testResultBundleObjectId))
            .willReturn("{}")

        given(multipartUploadStartAnalyticsService)
            .uploadAnalyticsArtifact(
                .value(.init(type: .resultBundleObject, name: testResultBundleObjectId)),
                commandEventId: .value(1),
                serverURL: .value(serverURL)
            )
            .willReturn("upload-id")

        given(completeAnalyticsArtifactsUploadsService)
            .completeAnalyticsArtifactsUploads(
                modules: .any,
                commandEventId: .any,
                serverURL: .value(serverURL)
            )
            .willReturn()

        given(multipartUploadArtifactService)
            .multipartUploadArtifact(
                artifactPath: .value(resultBundle.parentDirectory.appending(component: "\(testResultBundleObjectId).json")),
                generateUploadURL: .any
            )
            .willReturn([(etag: "etag", partNumber: 1)])

        // When / Then
        try await subject.uploadResultBundle(
            resultBundle,
            targetHashes: [
                GraphTarget(
                    path: try temporaryPath(),
                    target: .test(),
                    project: .test()
                ): "target-hash",
            ],
            graphPath: try temporaryPath(),
            commandEventId: 1,
            serverURL: serverURL
        )
    }
}
