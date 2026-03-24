import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Testing
import TuistCore
import TuistServer
import TuistSupport
import TuistTesting

@testable import TuistServer

struct AnalyticsArtifactUploadServiceTests {
    private let subject: AnalyticsArtifactUploadService
    private let xcresultToolController: MockXCResultToolControlling
    private let fileArchiverFactory: MockFileArchivingFactorying
    private let multipartUploadStartAnalyticsService: MockMultipartUploadStartAnalyticsServicing
    private let multipartUploadGenerateURLAnalyticsService:
        MockMultipartUploadGenerateURLAnalyticsServicing!
    private let multipartUploadArtifactService: MockMultipartUploadArtifactServicing
    private let multipartUploadCompleteAnalyticsService:
        MockMultipartUploadCompleteAnalyticsServicing!
    private let completeAnalyticsArtifactsUploadsService:
        MockCompleteAnalyticsArtifactsUploadsServicing!

    init() {
        let fileSystem = FileSystem()
        xcresultToolController = .init()
        fileArchiverFactory = .init()
        multipartUploadStartAnalyticsService = .init()
        multipartUploadGenerateURLAnalyticsService = .init()
        multipartUploadArtifactService = .init()
        multipartUploadCompleteAnalyticsService = .init()
        completeAnalyticsArtifactsUploadsService = .init()
        subject = AnalyticsArtifactUploadService(
            fileSystem: fileSystem,
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

    @Test(.inTemporaryDirectory)
    func upload_analytics_artifact() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let resultBundle = temporaryDirectory.appending(component: "artifact.bundle")
        try FileHandler.shared.touch(resultBundle)
        let accountHandle = "account-\(UUID().uuidString)"
        let projectHandle = "project-\(UUID().uuidString)"

        let serverURL: URL = .test()
        let commandEventID = UUID().uuidString

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
                accountHandle: .value(accountHandle),
                projectHandle: .value(projectHandle),
                commandEventId: .value(commandEventID),
                serverURL: .value(serverURL)
            )
            .willReturn("upload-id")

        var generateUploadURLCallback: ((MultipartUploadArtifactPart) async throws -> String)!
        given(multipartUploadArtifactService)
            .multipartUploadArtifact(
                artifactPath: .value(artifactArchivePath),
                generateUploadURL: .matching { callback in
                    generateUploadURLCallback = callback
                    return true
                },
                updateProgress: .any
            )
            .willReturn([(etag: "etag", partNumber: 1)])

        given(multipartUploadCompleteAnalyticsService)
            .uploadAnalyticsArtifact(
                .any,
                accountHandle: .value(accountHandle),
                projectHandle: .value(projectHandle),
                commandEventId: .value(commandEventID),
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
                accountHandle: .value(accountHandle),
                projectHandle: .value(projectHandle),
                commandEventId: .value(commandEventID),
                serverURL: .value(serverURL)
            )
            .willReturn("upload-id")

        given(multipartUploadArtifactService)
            .multipartUploadArtifact(
                artifactPath: .matching { $0.basename == "invocation_record.json" },
                generateUploadURL: .any,
                updateProgress: .any
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
                accountHandle: .value(accountHandle),
                projectHandle: .value(projectHandle),
                commandEventId: .value(commandEventID),
                serverURL: .value(serverURL)
            )
            .willReturn("upload-id")

        given(completeAnalyticsArtifactsUploadsService)
            .completeAnalyticsArtifactsUploads(
                accountHandle: .value(accountHandle),
                projectHandle: .value(projectHandle),
                commandEventId: .any,
                serverURL: .value(serverURL)
            )
            .willReturn()

        given(multipartUploadArtifactService)
            .multipartUploadArtifact(
                artifactPath: .matching { $0.basename == "\(testResultBundleObjectId).json" },
                generateUploadURL: .any,
                updateProgress: .any
            )
            .willReturn([(etag: "etag", partNumber: 1)])
        let uploadPartURL = "https://tuist.io/upload-url"
        given(multipartUploadGenerateURLAnalyticsService)
            .uploadAnalytics(
                .value(
                    ServerCommandEvent.Artifact(
                        type: .resultBundle
                    )
                ),
                accountHandle: .value(accountHandle),
                projectHandle: .value(projectHandle),
                commandEventId: .value(commandEventID),
                partNumber: .value(1),
                uploadId: .value("upload-id"),
                serverURL: .value(serverURL),
                contentLength: .value(20)
            )
            .willReturn(uploadPartURL)

        // When / Then
        try await subject.uploadResultBundle(
            resultBundle,
            accountHandle: accountHandle,
            projectHandle: projectHandle,
            commandEventId: commandEventID,
            serverURL: serverURL
        )

        let gotUploadPartURL = try await generateUploadURLCallback(
            .init(number: 1, contentLength: 20)
        )
        #expect(gotUploadPartURL == uploadPartURL)
    }

    @Test(.inTemporaryDirectory)
    func upload_session() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let sessionDirectory = temporaryDirectory.appending(component: "session")
        try FileHandler.shared.createFolder(sessionDirectory)
        try FileHandler.shared.touch(sessionDirectory.appending(component: "logs.txt"))
        try FileHandler.shared.touch(sessionDirectory.appending(component: "network.har"))

        let accountHandle = "account-\(UUID().uuidString)"
        let projectHandle = "project-\(UUID().uuidString)"
        let serverURL: URL = .test()
        let commandEventID = UUID().uuidString

        let fileArchiver = MockFileArchiving()
        given(fileArchiverFactory)
            .makeFileArchiver(for: .value([sessionDirectory]))
            .willReturn(fileArchiver)

        let sessionArchivePath = temporaryDirectory.appending(component: "session.zip")
        given(fileArchiver)
            .zip(name: .value("session"))
            .willReturn(sessionArchivePath)

        given(multipartUploadStartAnalyticsService)
            .uploadAnalyticsArtifact(
                .value(.init(type: .session)),
                accountHandle: .value(accountHandle),
                projectHandle: .value(projectHandle),
                commandEventId: .value(commandEventID),
                serverURL: .value(serverURL)
            )
            .willReturn("upload-id")

        given(multipartUploadArtifactService)
            .multipartUploadArtifact(
                artifactPath: .value(sessionArchivePath),
                generateUploadURL: .any,
                updateProgress: .any
            )
            .willReturn([(etag: "etag", partNumber: 1)])

        given(multipartUploadCompleteAnalyticsService)
            .uploadAnalyticsArtifact(
                .value(.init(type: .session)),
                accountHandle: .value(accountHandle),
                projectHandle: .value(projectHandle),
                commandEventId: .value(commandEventID),
                uploadId: .value("upload-id"),
                parts: .matching { parts in
                    parts.map(\.etag) == ["etag"] && parts.map(\.partNumber) == [1]
                },
                serverURL: .value(serverURL)
            )
            .willReturn(())

        // When / Then
        try await subject.uploadSession(
            sessionDirectory,
            accountHandle: accountHandle,
            projectHandle: projectHandle,
            commandEventId: commandEventID,
            serverURL: serverURL
        )
    }
}
