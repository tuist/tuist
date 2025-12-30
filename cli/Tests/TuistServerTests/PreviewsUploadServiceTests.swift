import Command
import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Testing
import TuistCore
import TuistGit
import TuistServer
import TuistSupport
import TuistTesting

@testable import TuistServer

struct PreviewsUploadServiceTests {
    private let subject: PreviewsUploadService

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
    private let commandRunner = MockCommandRunning()
    private let precompiledMetadataProvider = MockPrecompiledMetadataProvider()

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
            gitController: gitController,
            commandRunner: commandRunner,
            precompiledMetadataProvider: precompiledMetadataProvider
        )

        given(fileArchiverFactory)
            .makeFileArchiver(for: .any)
            .willReturn(fileArchiver)

        given(fileArchiverFactory)
            .makeFileUnarchiver(for: .any)
            .willReturn(fileUnarchiver)

        given(multipartUploadCompletePreviewsService)
            .completePreviewUpload(
                .value("app-build-id"),
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
                .value("app-build-id"),
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
                buildVersion: .any,
                bundleIdentifier: .any,
                supportedPlatforms: .any,
                gitBranch: .any,
                gitCommitSHA: .any,
                gitRef: .any,
                binaryId: .any,
                fullHandle: .any,
                serverURL: .any,
                track: .any
            )
            .willReturn(
                AppBuildUpload(appBuildId: "app-build-id", uploadId: "upload-id")
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

            precompiledMetadataProvider.uuidsStub = { _ in [UUID()] }

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
                track: nil,
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
                    buildVersion: .any,
                    bundleIdentifier: .any,
                    supportedPlatforms: .value([.simulator(.iOS)]),
                    gitBranch: .any,
                    gitCommitSHA: .any,
                    gitRef: .any,
                    binaryId: .any,
                    fullHandle: .value("tuist/tuist"),
                    serverURL: .value(serverURL),
                    track: .value(nil)
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

            precompiledMetadataProvider.uuidsStub = { _ in [UUID()] }

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
                    buildVersion: .any,
                    bundleIdentifier: .any,
                    supportedPlatforms: .any,
                    gitBranch: .any,
                    gitCommitSHA: .any,
                    gitRef: .any,
                    binaryId: .any,
                    fullHandle: .any,
                    serverURL: .any,
                    track: .any
                )
                .willReturn(AppBuildUpload(appBuildId: "app-build-id", uploadId: "upload-id"))

            given(multipartUploadCompletePreviewsService)
                .completePreviewUpload(
                    .any,
                    uploadId: .any,
                    parts: .any,
                    fullHandle: .any,
                    serverURL: .any
                )
                .willReturn(.test(id: "app-build-id", url: shareURL))

            // When
            _ = try await subject.uploadPreview(
                .appBundles([.test(path: preview1), .test(path: preview2)]),
                path: temporaryDirectory,
                fullHandle: "tuist/tuist",
                serverURL: serverURL,
                track: nil,
                updateProgress: { _ in }
            )

            // Then
            verify(multipartUploadStartPreviewsService)
                .startPreviewsMultipartUpload(
                    type: .any,
                    displayName: .any,
                    version: .any,
                    buildVersion: .any,
                    bundleIdentifier: .any,
                    supportedPlatforms: .any,
                    gitBranch: .any,
                    gitCommitSHA: .any,
                    gitRef: .any,
                    binaryId: .any,
                    fullHandle: .any,
                    serverURL: .any,
                    track: .any
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

            let unzippedPath = temporaryDirectory.appending(component: "unzipped")
            let appPath = unzippedPath.appending(components: ["Payload", "App.app"])
            try await fileSystem.makeDirectory(at: appPath)
            let iconPath = appPath.appending(component: "AppIcon60x60@2x.png")
            try await fileSystem.touch(iconPath)

            given(fileUnarchiver)
                .unzip()
                .willReturn(unzippedPath)

            precompiledMetadataProvider.uuidsStub = { _ in [UUID()] }

            gitController.reset()
            given(gitController)
                .gitInfo(workingDirectory: .any)
                .willReturn(.test(ref: "git-ref", branch: "main", sha: "commit-sha"))

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

            given(commandRunner)
                .run(
                    arguments: .any,
                    environment: .any,
                    workingDirectory: .any
                )
                .willReturn(
                    .init(
                        unfolding: {
                            nil
                        }
                    )
                )

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
                track: nil,
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
                    buildVersion: .value("1"),
                    bundleIdentifier: .value("dev.tuist.App"),
                    supportedPlatforms: .value([.device(.iOS)]),
                    gitBranch: .value("main"),
                    gitCommitSHA: .value("commit-sha"),
                    gitRef: .value("git-ref"),
                    binaryId: .any,
                    fullHandle: .value("tuist/tuist"),
                    serverURL: .value(serverURL),
                    track: .value(nil)
                )
                .called(1)

            verify(uploadPreviewIconService)
                .uploadPreviewIcon(
                    .any,
                    preview: .any,
                    serverURL: .any,
                    fullHandle: .any
                )
                .called(1)
        }
    }

    @Test(.inTemporaryDirectory) func upload_app_bundle_extracts_binary_id() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        // Given
        let appName = "TestApp"
        let preview = temporaryDirectory.appending(component: "\(appName).app")
        try await fileSystem.makeDirectory(at: preview)

        let expectedUUID = UUID()

        given(fileArchiver)
            .zip(name: .any)
            .willReturn(temporaryDirectory.appending(component: "\(appName).zip"))

        precompiledMetadataProvider.uuidsStub = { path in
            if path == preview.appending(component: appName) {
                return [expectedUUID]
            }
            return []
        }

        given(multipartUploadArtifactService)
            .multipartUploadArtifact(
                artifactPath: .any,
                generateUploadURL: .any,
                updateProgress: .any
            )
            .willReturn([(etag: "etag", partNumber: 1)])

        // When
        _ = try await subject.uploadPreview(
            .appBundles([.test(path: preview, infoPlist: .test(name: appName))]),
            path: temporaryDirectory,
            fullHandle: "tuist/tuist",
            serverURL: serverURL,
            track: nil,
            updateProgress: { _ in }
        )

        // Then
        verify(multipartUploadStartPreviewsService)
            .startPreviewsMultipartUpload(
                type: .any,
                displayName: .any,
                version: .any,
                buildVersion: .any,
                bundleIdentifier: .any,
                supportedPlatforms: .any,
                gitBranch: .any,
                gitCommitSHA: .any,
                gitRef: .any,
                binaryId: .value(expectedUUID.uuidString),
                fullHandle: .any,
                serverURL: .any,
                track: .any
            )
            .called(1)
    }

    @Test(.inTemporaryDirectory) func upload_app_bundle_throws_when_uuid_not_found() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        // Given
        let appName = "TestApp"
        let preview = temporaryDirectory.appending(component: "\(appName).app")
        try await fileSystem.makeDirectory(at: preview)

        given(fileArchiver)
            .zip(name: .any)
            .willReturn(temporaryDirectory.appending(component: "\(appName).zip"))

        precompiledMetadataProvider.uuidsStub = { _ in [] }

        // When / Then
        await #expect(throws: PreviewsUploadServiceError.binaryIdNotFound(preview.appending(component: appName))) {
            try await subject.uploadPreview(
                .appBundles([.test(path: preview, infoPlist: .test(name: appName))]),
                path: temporaryDirectory,
                fullHandle: "tuist/tuist",
                serverURL: serverURL,
                track: nil,
                updateProgress: { _ in }
            )
        }
    }

    @Test(.inTemporaryDirectory) func upload_ipa_extracts_binary_id() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        // Given
        let preview = temporaryDirectory.appending(component: "App.ipa")
        try await fileSystem.makeDirectory(at: preview)

        let unzippedPath = temporaryDirectory.appending(component: "unzipped")
        let appPath = unzippedPath.appending(components: ["Payload", "App.app"])
        try await fileSystem.makeDirectory(at: appPath)

        let expectedUUID = UUID()

        given(fileUnarchiver)
            .unzip()
            .willReturn(unzippedPath)

        precompiledMetadataProvider.uuidsStub = { path in
            if path == appPath.appending(component: "App") {
                return [expectedUUID]
            }
            return []
        }

        given(multipartUploadArtifactService)
            .multipartUploadArtifact(
                artifactPath: .any,
                generateUploadURL: .any,
                updateProgress: .any
            )
            .willReturn([(etag: "etag", partNumber: 1)])

        // When
        _ = try await subject.uploadPreview(
            .ipa(.test(path: preview, infoPlist: .test(name: "App"))),
            path: temporaryDirectory,
            fullHandle: "tuist/tuist",
            serverURL: serverURL,
            track: nil,
            updateProgress: { _ in }
        )

        // Then
        verify(multipartUploadStartPreviewsService)
            .startPreviewsMultipartUpload(
                type: .value(.ipa),
                displayName: .any,
                version: .any,
                buildVersion: .any,
                bundleIdentifier: .any,
                supportedPlatforms: .any,
                gitBranch: .any,
                gitCommitSHA: .any,
                gitRef: .any,
                binaryId: .value(expectedUUID.uuidString),
                fullHandle: .any,
                serverURL: .any,
                track: .any
            )
            .called(1)
    }

    @Test(.inTemporaryDirectory) func upload_ipa_throws_when_app_bundle_not_found() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        // Given
        let preview = temporaryDirectory.appending(component: "App.ipa")
        try await fileSystem.makeDirectory(at: preview)

        let unzippedPath = temporaryDirectory.appending(component: "unzipped")
        try await fileSystem.makeDirectory(at: unzippedPath)

        given(fileUnarchiver)
            .unzip()
            .willReturn(unzippedPath)

        // When / Then
        await #expect(throws: PreviewsUploadServiceError.appBundleNotFound(preview)) {
            try await subject.uploadPreview(
                .ipa(.test(path: preview, infoPlist: .test(name: "App"))),
                path: temporaryDirectory,
                fullHandle: "tuist/tuist",
                serverURL: serverURL,
                track: nil,
                updateProgress: { _ in }
            )
        }
    }
}
