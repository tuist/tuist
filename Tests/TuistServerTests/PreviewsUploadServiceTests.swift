import FileSystem
import Foundation
import Mockable
import Testing
import TuistServer
import TuistSupport
import TuistTesting

@testable import TuistServer

struct PreviewsUploadServiceTests {
    private var subject: PreviewsUploadService!

    private let fileSystem = FileSystem()
    private let fileArchiver = MockFileArchiving()
    private let multipartUploadStartPreviewsService = MockMultipartUploadStartPreviewsServicing()
    private let multipartUploadGenerateURLPreviewsService =
        MockMultipartUploadGenerateURLPreviewsServicing()
    private let multipartUploadArtifactService = MockMultipartUploadArtifactServicing()
    private let multipartUploadCompletePreviewsService =
        MockMultipartUploadCompletePreviewsServicing()
    private let uploadPreviewIconService = MockUploadPreviewIconServicing()
    private let gitController = MockGitControlling()

    private let serverURL: URL = .test()
    private let shareURL: URL = .test()

    init() {
        let fileArchiverFactory = MockFileArchivingFactorying()

        subject = PreviewsUploadService(
            fileSystem: fileSystem,
            fileArchiver: fileArchiverFactory,
            retryProvider: RetryProvider(),
            multipartUploadStartPreviewsService: multipartUploadStartPreviewsService,
            multipartUploadGenerateURLPreviewsService: multipartUploadGenerateURLPreviewsService,
            multipartUploadArtifactService: multipartUploadArtifactService,
            multipartUploadCompletePreviewsService: multipartUploadCompletePreviewsService,
            uploadPreviewIconService: uploadPreviewIconService,
            gitController: gitController
        )

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

        given(gitController)
            .isInGitRepository(workingDirectory: .any)
            .willReturn(false)

        given(gitController)
            .gitInfo(workingDirectory: .any)
            .willReturn((ref: nil, branch: nil, sha: nil))

        given(multipartUploadStartPreviewsService)
            .startPreviewsMultipartUpload(
                type: .any,
                displayName: .any,
                version: .any,
                bundleIdentifier: .any,
                supportedPlatforms: .any,
                gitBranch: .any,
                gitCommitSHA: .any,
                fullHandle: .any,
                serverURL: .any
            )
            .willReturn(
                PreviewUpload(previewId: "preview-id", uploadId: "upload-id")
            )
    }

    @Test func upload_app_bundle() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) {
            temporaryDirectory in
            // Given
            let preview = temporaryDirectory.appending(component: "App.app")
            try FileHandler.shared.touch(preview)

            let artifactArchivePath = preview.parentDirectory.appending(component: "previews.zip")

            given(fileArchiver)
                .zip(name: .value("previews.zip"))
                .willReturn(artifactArchivePath)

            var multipartUploadCapturedGenerateUploadURLCallback:
                ((MultipartUploadArtifactPart) async throws -> String)!
            given(multipartUploadArtifactService)
                .multipartUploadArtifact(
                    artifactPath: .any,
                    generateUploadURL: .matching { callback in
                        multipartUploadCapturedGenerateUploadURLCallback = callback
                        return true
                    },
                    updateProgress: .any
                )
                .willReturn([(etag: "etag", partNumber: 1)])

            let shareURL = URL.test()

            // When
            let got = try await subject.uploadPreviews(
                .appBundles([preview]),
                displayName: "App",
                version: nil,
                bundleIdentifier: nil,
                icon: nil,
                supportedPlatforms: [.simulator(.iOS)],
                path: temporaryDirectory,
                fullHandle: "tuist/tuist",
                serverURL: serverURL,
                updateProgress: { _ in }
            )

            // Then
            #expect(
                got
                    == .test(
                        id: "preview-id",
                        url: shareURL
                    )
            )
            let gotMultipartUploadURL = try await multipartUploadCapturedGenerateUploadURLCallback(
                MultipartUploadArtifactPart(
                    number: 1,
                    contentLength: 20
                )
            )
            #expect(
                gotMultipartUploadURL == "https://tuist.dev/upload-url"
            )
            verify(multipartUploadStartPreviewsService)
                .startPreviewsMultipartUpload(
                    type: .any,
                    displayName: .value("App"),
                    version: .any,
                    bundleIdentifier: .any,
                    supportedPlatforms: .value([.simulator(.iOS)]),
                    gitBranch: .any,
                    gitCommitSHA: .any,
                    fullHandle: .value("tuist/tuist"),
                    serverURL: .value(serverURL)
                )
                .called(1)
        }
    }

    @Test func upload_ipa() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) {
            temporaryDirectory in
            // Given
            let preview = temporaryDirectory.appending(component: "App.ipa")
            try await fileSystem.touch(preview)

            gitController.reset()
            given(gitController)
                .isInGitRepository(workingDirectory: .any)
                .willReturn(true)
            given(gitController)
                .hasCurrentBranchCommits(workingDirectory: .any)
                .willReturn(true)
            given(gitController)
                .currentCommitSHA(workingDirectory: .any)
                .willReturn("commit-sha")
            given(gitController)
                .gitInfo(workingDirectory: .any)
                .willReturn((ref: nil, branch: "main", sha: "commit-sha"))

            var multipartUploadCapturedGenerateUploadURLCallback:
                ((MultipartUploadArtifactPart) async throws -> String)!
            given(multipartUploadArtifactService)
                .multipartUploadArtifact(
                    artifactPath: .any,
                    generateUploadURL: .matching { callback in
                        multipartUploadCapturedGenerateUploadURLCallback = callback
                        return true
                    },
                    updateProgress: .any
                )
                .willReturn([(etag: "etag", partNumber: 1)])

            let shareURL = URL.test()

            let icon = temporaryDirectory.appending(component: "icon.png")
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
                path: temporaryDirectory,
                fullHandle: "tuist/tuist",
                serverURL: serverURL,
                updateProgress: { _ in }
            )

            // Then
            #expect(
                got
                    == .test(
                        id: "preview-id",
                        url: shareURL
                    )
            )
            let gotMultipartUploadURL = try await multipartUploadCapturedGenerateUploadURLCallback(
                MultipartUploadArtifactPart(
                    number: 1,
                    contentLength: 20
                )
            )
            #expect(
                gotMultipartUploadURL == "https://tuist.dev/upload-url"
            )

            verify(multipartUploadStartPreviewsService)
                .startPreviewsMultipartUpload(
                    type: .value(.ipa),
                    displayName: .value("App"),
                    version: .value("1.0.0"),
                    bundleIdentifier: .value("com.my.app"),
                    supportedPlatforms: .value([.device(.iOS)]),
                    gitBranch: .value("main"),
                    gitCommitSHA: .value("commit-sha"),
                    fullHandle: .value("tuist/tuist"),
                    serverURL: .value(serverURL)
                )
                .called(1)

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
}
