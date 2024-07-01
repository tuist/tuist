import Foundation
import MockableTest
import TuistSupport
import TuistSupportTesting
import XcodeGraph
import XCTest

@testable import TuistServer

final class AppBuildsUploadServiceTests: TuistTestCase {
    private var subject: AppBuildsUploadService!

    private var fileArchiverFactory: MockFileArchivingFactorying!
    private var multipartUploadStartAppBuildsService: MockMultipartUploadStartAppBuildsServicing!
    private var multipartUploadGenerateURLAppBuildsService: MockMultipartUploadGenerateURLAppBuildsServicing!
    private var multipartUploadArtifactService: MockMultipartUploadArtifactServicing!
    private var multipartUploadCompleteAppBuildsService: MockMultipartUploadCompleteAppBuildsServicing!

    override func setUp() {
        super.setUp()

        fileArchiverFactory = .init()
        multipartUploadStartAppBuildsService = .init()
        multipartUploadGenerateURLAppBuildsService = .init()
        multipartUploadArtifactService = .init()
        multipartUploadCompleteAppBuildsService = .init()

        subject = AppBuildsUploadService(
            fileHandler: fileHandler,
            fileArchiver: fileArchiverFactory,
            retryProvider: RetryProvider(),
            multipartUploadStartAppBuildsService: multipartUploadStartAppBuildsService,
            multipartUploadGenerateURLAppBuildsService: multipartUploadGenerateURLAppBuildsService,
            multipartUploadArtifactService: multipartUploadArtifactService,
            multipartUploadCompleteAppBuildsService: multipartUploadCompleteAppBuildsService
        )
    }

    override func tearDown() {
        fileArchiverFactory = nil
        multipartUploadStartAppBuildsService = nil
        multipartUploadGenerateURLAppBuildsService = nil
        multipartUploadArtifactService = nil
        multipartUploadCompleteAppBuildsService = nil

        super.tearDown()
    }

    func test_upload_app_builds() async throws {
        // Given
        let appBuild = try temporaryPath().appending(component: "App.app")
        try FileHandler.shared.touch(appBuild)

        let serverURL: URL = .test()

        let fileArchiver = MockFileArchiving()
        given(fileArchiverFactory)
            .makeFileArchiver(for: .value([appBuild]))
            .willReturn(fileArchiver)

        let artifactArchivePath = appBuild.parentDirectory.appending(component: "app-builds.zip")

        given(fileArchiver)
            .zip(name: .value("app-builds.zip"))
            .willReturn(artifactArchivePath)

        given(multipartUploadStartAppBuildsService)
            .startAppBuildsMultipartUpload(
                fullHandle: .value("tuist/tuist"),
                serverURL: .value(serverURL)
            )
            .willReturn(
                AppBuildUpload(appBuildId: "app-build-id", uploadId: "upload-id")
            )

        given(multipartUploadArtifactService)
            .multipartUploadArtifact(
                artifactPath: .value(artifactArchivePath),
                generateUploadURL: .any
            )
            .willReturn([(etag: "etag", partNumber: 1)])

        let shareURL = URL.test()
        given(multipartUploadCompleteAppBuildsService)
            .completeAppBuildUpload(
                .value("app-build-id"),
                uploadId: .value("upload-id"),
                parts: .matching { parts in
                    parts.map(\.etag) == ["etag"] && parts.map(\.partNumber) == [1]
                },
                fullHandle: .value("tuist/tuist"),
                serverURL: .value(serverURL)
            )
            .willReturn(shareURL)

        // When
        let got = try await subject.uploadAppBuilds(
            [appBuild],
            fullHandle: "tuist/tuist",
            serverURL: serverURL
        )

        // Then
        XCTAssertEqual(got, shareURL)
    }
}
