import FileSystem
import Foundation
import Mockable
#if canImport(TuistAppleArchiver)
    import TuistAppleArchiver
#endif
import TuistCore
import TuistHTTP
import TuistServer
import TuistSupport
import TuistTesting
import XCTest

@testable import TuistServer

final class AnalyticsArtifactUploadServiceTests: TuistTestCase {
    private var subject: AnalyticsArtifactUploadService!
    private var xcresultToolController: MockXCResultToolControlling!
    private var fileArchiverFactory: MockFileArchivingFactorying!
    private var multipartUploadStartAnalyticsService: MockMultipartUploadStartAnalyticsServicing!
    private var multipartUploadGenerateURLAnalyticsService:
        MockMultipartUploadGenerateURLAnalyticsServicing!
    private var multipartUploadArtifactService: MockMultipartUploadArtifactServicing!
    private var multipartUploadCompleteAnalyticsService:
        MockMultipartUploadCompleteAnalyticsServicing!
    private var completeAnalyticsArtifactsUploadsService:
        MockCompleteAnalyticsArtifactsUploadsServicing!
    #if canImport(TuistAppleArchiver)
        private var appleArchiver: MockAppleArchiving!
    #endif

    override func setUp() {
        super.setUp()

        let fileSystem = FileSystem()
        xcresultToolController = .init()
        fileArchiverFactory = .init()
        multipartUploadStartAnalyticsService = .init()
        multipartUploadGenerateURLAnalyticsService = .init()
        multipartUploadArtifactService = .init()
        multipartUploadCompleteAnalyticsService = .init()
        completeAnalyticsArtifactsUploadsService = .init()
        #if canImport(TuistAppleArchiver)
            appleArchiver = .init()
            subject = AnalyticsArtifactUploadService(
                fileSystem: fileSystem,
                xcresultToolController: xcresultToolController,
                fileArchiver: fileArchiverFactory,
                fullHandleService: FullHandleService(),
                multipartUploadStartAnalyticsService: multipartUploadStartAnalyticsService,
                multipartUploadGenerateURLAnalyticsService: multipartUploadGenerateURLAnalyticsService,
                multipartUploadArtifactService: multipartUploadArtifactService,
                multipartUploadCompleteAnalyticsService: multipartUploadCompleteAnalyticsService,
                completeAnalyticsArtifactsUploadsService: completeAnalyticsArtifactsUploadsService,
                appleArchiver: appleArchiver
            )
        #else
            subject = AnalyticsArtifactUploadService(
                fileSystem: fileSystem,
                xcresultToolController: xcresultToolController,
                fileArchiver: fileArchiverFactory,
                fullHandleService: FullHandleService(),
                multipartUploadStartAnalyticsService: multipartUploadStartAnalyticsService,
                multipartUploadGenerateURLAnalyticsService: multipartUploadGenerateURLAnalyticsService,
                multipartUploadArtifactService: multipartUploadArtifactService,
                multipartUploadCompleteAnalyticsService: multipartUploadCompleteAnalyticsService,
                completeAnalyticsArtifactsUploadsService: completeAnalyticsArtifactsUploadsService
            )
        #endif
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
        try await FileSystem().touch(resultBundle)
        let accountHandle = "account-\(UUID().uuidString)"
        let projectHandle = "project-\(UUID().uuidString)"

        let serverURL: URL = .test()
        let commandEventID = UUID().uuidString

        #if canImport(TuistAppleArchiver)
            // On macOS the result_bundle path goes through AppleArchive, not the zip
            // `FileArchiver`. Stub compress to write an .aar file so the downstream
            // multipart pipeline has a real file to work with.
            given(appleArchiver)
                .compress(directory: .value(resultBundle), to: .any, excludePatterns: .value([]))
                .willProduce { _, archivePath, _ in
                    try Data("fake-aar".utf8).write(to: archivePath.url)
                }
        #else
            let fileArchiver = MockFileArchiving()
            given(fileArchiverFactory)
                .makeFileArchiver(for: .value([resultBundle]))
                .willReturn(fileArchiver)

            let artifactArchivePath = temporaryDirectory.appending(component: "artifact.zip")

            given(fileArchiver)
                .zip(name: .value("artifact"))
                .willReturn(artifactArchivePath)
        #endif

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
        #if canImport(TuistAppleArchiver)
            given(multipartUploadArtifactService)
                .multipartUploadArtifact(
                    artifactPath: .matching { $0.extension == "aar" },
                    generateUploadURL: .matching { callback in
                        generateUploadURLCallback = callback
                        return true
                    },
                    updateProgress: .any
                )
                .willReturn([(etag: "etag", partNumber: 1)])
        #else
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
        #endif

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
        try await subject.uploadAndAnalyzeResultBundle(
            resultBundle,
            accountHandle: accountHandle,
            projectHandle: projectHandle,
            commandEventId: commandEventID,
            serverURL: serverURL
        )

        let gotUploadPartURL = try await generateUploadURLCallback(
            .init(number: 1, contentLength: 20)
        )
        XCTAssertEqual(gotUploadPartURL, uploadPartURL)
    }

    func test_upload_session() async throws {
        // Given
        let temporaryDirectory = try temporaryPath()
        let sessionDirectory = temporaryDirectory.appending(component: "session")
        try await FileSystem().makeDirectory(at: sessionDirectory)
        try await FileSystem().touch(sessionDirectory.appending(component: "logs.txt"))
        try await FileSystem().touch(sessionDirectory.appending(component: "network.har"))

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
