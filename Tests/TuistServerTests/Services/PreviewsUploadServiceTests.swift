import Foundation
import Mockable
import TuistSupport
import TuistSupportTesting
import XCTest

@testable import TuistServer

final class PreviewsUploadServiceTests: TuistUnitTestCase {
    private var subject: PreviewsUploadService!

    private var fileArchiver: MockFileArchiving!
    private var multipartUploadStartPreviewsService: MockMultipartUploadStartPreviewsServicing!
    private var multipartUploadGenerateURLPreviewsService: MockMultipartUploadGenerateURLPreviewsServicing!
    private var multipartUploadArtifactService: MockMultipartUploadArtifactServicing!
    private var multipartUploadCompletePreviewsService: MockMultipartUploadCompletePreviewsServicing!
    private var multipartUploadCapturedGenerateUploadURLCallback: ((MultipartUploadArtifactPart) async throws -> String)!
    private var uploadPreviewIconService: MockUploadPreviewIconServicing!

    private let serverURL: URL = .test()
    private let shareURL: URL = .test()

    override func setUp() {
        super.setUp()

        let fileArchiverFactory = MockFileArchivingFactorying()
        multipartUploadStartPreviewsService = .init()
        multipartUploadGenerateURLPreviewsService = .init()
        multipartUploadArtifactService = .init()
        multipartUploadCompletePreviewsService = .init()
        uploadPreviewIconService = .init()

        subject = PreviewsUploadService(
            fileSystem: fileSystem,
            fileArchiver: fileArchiverFactory,
            retryProvider: RetryProvider(),
            multipartUploadStartPreviewsService: multipartUploadStartPreviewsService,
            multipartUploadGenerateURLPreviewsService: multipartUploadGenerateURLPreviewsService,
            multipartUploadArtifactService: multipartUploadArtifactService,
            multipartUploadCompletePreviewsService: multipartUploadCompletePreviewsService,
            uploadPreviewIconService: uploadPreviewIconService
        )

        fileArchiver = MockFileArchiving()
        given(fileArchiverFactory)
            .makeFileArchiver(for: .any)
            .willReturn(fileArchiver)

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
            .willReturn(.test(url: shareURL))

        given(multipartUploadArtifactService)
            .multipartUploadArtifact(
                artifactPath: .any,
                generateUploadURL: .matching { callback in
                    self.multipartUploadCapturedGenerateUploadURLCallback = callback
                    return true
                }
            )
            .willReturn([(etag: "etag", partNumber: 1)])

        given(multipartUploadGenerateURLPreviewsService)
            .uploadPreviews(
                .value("preview-id"),
                partNumber: .value(1),
                uploadId: .value("upload-id"),
                fullHandle: .value("tuist/tuist"),
                serverURL: .value(serverURL),
                contentLength: .value(20)
            )
            .willReturn("https://tuist.dev/upload-url")
    }

    override func tearDown() {
        fileArchiver = nil
        multipartUploadStartPreviewsService = nil
        multipartUploadGenerateURLPreviewsService = nil
        multipartUploadArtifactService = nil
        multipartUploadCompletePreviewsService = nil

        super.tearDown()
    }

    func test_upload_app_bundle() async throws {
        // Given
        let preview = try temporaryPath().appending(component: "App.app")
        try FileHandler.shared.touch(preview)

        let artifactArchivePath = preview.parentDirectory.appending(component: "previews.zip")

        given(fileArchiver)
            .zip(name: .value("previews.zip"))
            .willReturn(artifactArchivePath)

        given(multipartUploadStartPreviewsService)
            .startPreviewsMultipartUpload(
                type: .any,
                displayName: .value("App"),
                version: .any,
                bundleIdentifier: .any,
                supportedPlatforms: .value([.simulator(.iOS)]),
                fullHandle: .value("tuist/tuist"),
                serverURL: .value(serverURL)
            )
            .willReturn(
                PreviewUpload(previewId: "preview-id", uploadId: "upload-id")
            )

        let shareURL = URL.test()

        // When
        let got = try await subject.uploadPreviews(
            .appBundles([preview]),
            displayName: "App",
            version: nil,
            bundleIdentifier: nil,
            icon: nil,
            supportedPlatforms: [.simulator(.iOS)],
            fullHandle: "tuist/tuist",
            serverURL: serverURL
        )

        // Then
        XCTAssertEqual(
            got,
            .test(
                id: "preview-id",
                url: shareURL
            )
        )
        let gotMultipartUploadURL = try await multipartUploadCapturedGenerateUploadURLCallback(MultipartUploadArtifactPart(
            number: 1,
            contentLength: 20
        ))
        XCTAssertEqual(gotMultipartUploadURL, "https://tuist.dev/upload-url")
    }

    func test_upload_ipa() async throws {
        // Given
        let preview = try temporaryPath().appending(component: "App.ipa")
        try FileHandler.shared.touch(preview)

        given(multipartUploadStartPreviewsService)
            .startPreviewsMultipartUpload(
                type: .value(.ipa),
                displayName: .value("App"),
                version: .value("1.0.0"),
                bundleIdentifier: .value("com.my.app"),
                supportedPlatforms: .value([.device(.iOS)]),
                fullHandle: .value("tuist/tuist"),
                serverURL: .value(serverURL)
            )
            .willReturn(
                PreviewUpload(previewId: "preview-id", uploadId: "upload-id")
            )

        let shareURL = URL.test()

        let icon = try temporaryPath().appending(component: "icon.png")
        try await fileSystem.touch(icon)

        given(uploadPreviewIconService)
            .uploadPreviewIcon(.any, preview: .any, serverURL: .any, fullHandle: .any)
            .willReturn()

        // When
        let got = try await subject.uploadPreviews(
            .ipa(preview),
            displayName: "App",
            version: "1.0.0",
            bundleIdentifier: "com.my.app",
            icon: icon,
            supportedPlatforms: [.device(.iOS)],
            fullHandle: "tuist/tuist",
            serverURL: serverURL
        )

        // Then
        XCTAssertEqual(
            got,
            .test(
                id: "preview-id",
                url: shareURL
            )
        )
        let gotMultipartUploadURL = try await multipartUploadCapturedGenerateUploadURLCallback(MultipartUploadArtifactPart(
            number: 1,
            contentLength: 20
        ))
        XCTAssertEqual(gotMultipartUploadURL, "https://tuist.dev/upload-url")

        verify(uploadPreviewIconService)
            .uploadPreviewIcon(
                .value(icon),
                preview: .any,
                serverURL: .any,
                fullHandle: .any
            )
            .called(1)
    }
}
