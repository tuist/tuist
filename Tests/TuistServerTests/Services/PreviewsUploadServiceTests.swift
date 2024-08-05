import Foundation
import MockableTest
import TuistSupport
import TuistSupportTesting
import XcodeGraph
import XCTest

@testable import TuistServer

final class PreviewsUploadServiceTests: TuistTestCase {
    private var subject: PreviewsUploadService!

    private var fileArchiverFactory: MockFileArchivingFactorying!
    private var multipartUploadStartPreviewsService: MockMultipartUploadStartPreviewsServicing!
    private var multipartUploadGenerateURLPreviewsService: MockMultipartUploadGenerateURLPreviewsServicing!
    private var multipartUploadArtifactService: MockMultipartUploadArtifactServicing!
    private var multipartUploadCompletePreviewsService: MockMultipartUploadCompletePreviewsServicing!

    override func setUp() {
        super.setUp()

        fileArchiverFactory = .init()
        multipartUploadStartPreviewsService = .init()
        multipartUploadGenerateURLPreviewsService = .init()
        multipartUploadArtifactService = .init()
        multipartUploadCompletePreviewsService = .init()

        subject = PreviewsUploadService(
            fileHandler: fileHandler,
            fileArchiver: fileArchiverFactory,
            retryProvider: RetryProvider(),
            multipartUploadStartPreviewsService: multipartUploadStartPreviewsService,
            multipartUploadGenerateURLPreviewsService: multipartUploadGenerateURLPreviewsService,
            multipartUploadArtifactService: multipartUploadArtifactService,
            multipartUploadCompletePreviewsService: multipartUploadCompletePreviewsService
        )
    }

    override func tearDown() {
        fileArchiverFactory = nil
        multipartUploadStartPreviewsService = nil
        multipartUploadGenerateURLPreviewsService = nil
        multipartUploadArtifactService = nil
        multipartUploadCompletePreviewsService = nil

        super.tearDown()
    }

    func test_upload_app_builds() async throws {
        // Given
        let preview = try temporaryPath().appending(component: "App.app")
        try FileHandler.shared.touch(preview)

        let serverURL: URL = .test()

        let fileArchiver = MockFileArchiving()
        given(fileArchiverFactory)
            .makeFileArchiver(for: .value([preview]))
            .willReturn(fileArchiver)

        let artifactArchivePath = preview.parentDirectory.appending(component: "previews.zip")

        given(fileArchiver)
            .zip(name: .value("previews.zip"))
            .willReturn(artifactArchivePath)

        given(multipartUploadStartPreviewsService)
            .startPreviewsMultipartUpload(
                fullHandle: .value("tuist/tuist"),
                serverURL: .value(serverURL)
            )
            .willReturn(
                PreviewUpload(previewId: "preview-id", uploadId: "upload-id")
            )

        given(multipartUploadArtifactService)
            .multipartUploadArtifact(
                artifactPath: .value(artifactArchivePath),
                generateUploadURL: .any
            )
            .willReturn([(etag: "etag", partNumber: 1)])

        let shareURL = URL.test()
        given(multipartUploadCompletePreviewsService)
            .completePreviewUpload(
                .value("preview-id"),
                uploadId: .value("upload-id"),
                parts: .matching { parts in
                    parts.map(\.etag) == ["etag"] && parts.map(\.partNumber) == [1]
                },
                fullHandle: .value("tuist/tuist"),
                serverURL: .value(serverURL)
            )
            .willReturn(shareURL)

        // When
        let got = try await subject.uploadPreviews(
            [preview],
            fullHandle: "tuist/tuist",
            serverURL: serverURL
        )

        // Then
        XCTAssertEqual(got, shareURL)
    }
}
