import FileSystem
import Foundation
import Mockable
import Testing
import TuistGit
import TuistServer
import TuistSupport
import TuistTesting

@testable import TuistServer

struct PreviewsUploadServiceTests {
    private var subject: PreviewsUploadService!

    private let fileSystem = FileSystem()
    private let fileArchiver = MockFileArchiving()
    private let fileUnarchiver = MockFileUnarchiving()
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

        given(fileArchiverFactory)
            .makeFileUnarchiver(for: .any)
            .willReturn(fileUnarchiver)

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
            .uploadPreview(
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
            .willReturn(.test())

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

    @Test func upload_single_app_bundle() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) {
            temporaryDirectory in
            // Given
            let preview = temporaryDirectory.appending(component: "App.app")
            try await fileSystem.makeDirectory(at: preview)

            given(fileArchiver)
                .zip(name: .any)
                .willReturn(temporaryDirectory.appending(component: "App.zip"))

            var multipartUploadCapturedGenerateUploadURLCallback:
                ((MultipartUploadArtifactPart) async throws -> String)!
            given(multipartUploadArtifactService)
                .multipartUploadArtifact(
                    artifactPath: .value(temporaryDirectory.appending(component: "App.zip")),
                    generateUploadURL: .matching { callback in
                        multipartUploadCapturedGenerateUploadURLCallback = callback
                        return true
                    },
                    updateProgress: .any
                )
                .willReturn([(etag: "etag", partNumber: 1)])

            let shareURL = URL.test()

            // When
            let got = try await subject.uploadPreview(
                .appBundles([.test(path: preview)]),
                path: temporaryDirectory,
                fullHandle: "tuist/tuist",
                serverURL: serverURL,
                updateProgress: { _ in }
            )

            // Then
            #expect(
                got == .test(
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

    @Test func upload_multiple_app_bundles_individually() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) {
            temporaryDirectory in
            // Given
            let preview1 = temporaryDirectory.appending(component: "App1.app")
            let preview2 = temporaryDirectory.appending(component: "App2.app")
            try await fileSystem.makeDirectory(at: preview1)
            try await fileSystem.makeDirectory(at: preview2)

            let app1ArchivePath = temporaryDirectory.appending(component: "App1.zip")
            let app2ArchivePath = temporaryDirectory.appending(component: "App2.zip")

            given(fileArchiver)
                .zip(name: .value("App1.app"))
                .willReturn(app1ArchivePath)
            given(fileArchiver)
                .zip(name: .value("App2.app"))
                .willReturn(app2ArchivePath)

            given(multipartUploadArtifactService)
                .multipartUploadArtifact(
                    artifactPath: .any,
                    generateUploadURL: .any,
                    updateProgress: .any
                )
                .willReturn([(etag: "etag", partNumber: 1)])

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
                .willReturn(PreviewUpload(previewId: "preview-id", uploadId: "upload-id"))

            given(multipartUploadCompletePreviewsService)
                .completePreviewUpload(
                    .any,
                    uploadId: .any,
                    parts: .any,
                    fullHandle: .any,
                    serverURL: .any
                )
                .willReturn(.test(id: "preview-id", url: shareURL))

            // When
            _ = try await subject.uploadPreview(
                .appBundles([.test(path: preview1), .test(path: preview2)]),
                path: temporaryDirectory,
                fullHandle: "tuist/tuist",
                serverURL: serverURL,
                updateProgress: { _ in }
            )

            // Then
            verify(multipartUploadStartPreviewsService)
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
                .called(2)

            verify(multipartUploadArtifactService)
                .multipartUploadArtifact(
                    artifactPath: .value(app1ArchivePath),
                    generateUploadURL: .any,
                    updateProgress: .any
                )
                .called(1)

            verify(multipartUploadArtifactService)
                .multipartUploadArtifact(
                    artifactPath: .value(app2ArchivePath),
                    generateUploadURL: .any,
                    updateProgress: .any
                )
                .called(1)
        }
    }

    @Test func upload_ipa() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) {
            temporaryDirectory in
            // Given
            let preview = temporaryDirectory.appending(component: "App.ipa")
            try await fileSystem.makeDirectory(at: preview)

            let unzippedPath = temporaryDirectory.appending(component: "Payload")
            let appPath = unzippedPath.appending(component: "App.app")
            try await fileSystem.makeDirectory(at: appPath)
            let iconPath = appPath.appending(component: "AppIcon60x60@2x.png")
            try await fileSystem.touch(iconPath)

            given(fileUnarchiver)
                .unzip()
                .willReturn(unzippedPath)

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
                .willReturn(.test(ref: nil, branch: "main", sha: "commit-sha"))

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

            let icon = temporaryDirectory.appending(component: "AppIcon60x60@2x.png")
            try await fileSystem.touch(icon)

            given(uploadPreviewIconService)
                .uploadPreviewIcon(.any, preview: .any, serverURL: .any, fullHandle: .any)
                .willReturn()

            // When
            let got = try await subject.uploadPreview(
                .ipa(
                    .test(
                        path: preview,
                        infoPlist: .test(
                            supportedPlatforms: [.device(.iOS)],
                            bundleIcons: .test(
                                primaryIcon: .test(
                                    iconFiles: [
                                        "AppIcon60x60",
                                    ]
                                )
                            )
                        )
                    )
                ),
                path: temporaryDirectory,
                fullHandle: "tuist/tuist",
                serverURL: serverURL,
                updateProgress: { _ in }
            )

            // Then
            #expect(
                got == .test(
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
                    version: .value("1.0"),
                    bundleIdentifier: .value("io.tuist.App"),
                    supportedPlatforms: .value([.device(.iOS)]),
                    gitBranch: .value("main"),
                    gitCommitSHA: .value("commit-sha"),
                    fullHandle: .value("tuist/tuist"),
                    serverURL: .value(serverURL)
                )
                .called(1)

            verify(uploadPreviewIconService)
                .uploadPreviewIcon(
                    .value(iconPath),
                    preview: .any,
                    serverURL: .any,
                    fullHandle: .any
                )
                .called(1)
        }
    }
}
