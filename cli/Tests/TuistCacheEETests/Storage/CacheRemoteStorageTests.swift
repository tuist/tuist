import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import OpenAPIRuntime
import Path
import Testing
import TuistCore
import TuistServer
import TuistSupport
import XcodeGraph

@testable import TuistCacheEE
@testable import TuistSupport
@testable import TuistTesting

struct CacheRemoteStorageTests {
    private struct TestError: Equatable, Error, LocalizedError {
        var description: String

        init(_ description: String = "") {
            self.description = description
        }
    }

    private var subject: CacheRemoteStorage!
    private var downloader: MockCacheRemoteStorageDownloading!
    private let fullHandle = "tuist/tuist"
    private var cacheExistsService: MockCacheExistsServicing!
    private var getCacheService: MockGetCacheServicing!
    private var getCacheActionItemService: MockGetCacheActionItemServicing!
    private var uploadCacheActionItemService: MockUploadCacheActionItemServicing!
    private var multipartUploadStartCacheService: MockMultipartUploadStartCacheServicing!
    private var multipartUploadGenerateURLCacheService:
        MockMultipartUploadGenerateURLCacheServicing!
    private var multipartUploadCompleteCacheService: MockMultipartUploadCompleteCacheServicing!
    private var cacheDirectoriesProvider: MockCacheDirectoriesProviding!
    private var artifactSigner: ArtifactSigner!
    private var retryProvider: RetryProviding!
    private var multipartUploadArtifactService: MockMultipartUploadArtifactServicing!
    private var fileSystem: FileSysteming!

    init() throws {
        downloader = MockCacheRemoteStorageDownloading()
        cacheExistsService = MockCacheExistsServicing()
        getCacheService = MockGetCacheServicing()
        getCacheActionItemService = MockGetCacheActionItemServicing()
        uploadCacheActionItemService = MockUploadCacheActionItemServicing()
        multipartUploadStartCacheService = MockMultipartUploadStartCacheServicing()
        multipartUploadGenerateURLCacheService = MockMultipartUploadGenerateURLCacheServicing()
        multipartUploadCompleteCacheService = MockMultipartUploadCompleteCacheServicing()
        cacheDirectoriesProvider = .init()
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .any)
            .willReturn(temporaryDirectory)
        artifactSigner = ArtifactSigner()
        retryProvider = RetryProvider()
        multipartUploadArtifactService = .init()
        fileSystem = FileSystem()

        subject = CacheRemoteStorage(
            fullHandle: fullHandle,
            url: Constants.URLs.production,
            fileArchiverFactory: FileArchivingFactory(),
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            cacheExistsService: cacheExistsService,
            getCacheService: getCacheService,
            getCacheActionItemService: getCacheActionItemService,
            uploadCacheActionItemService: uploadCacheActionItemService,
            artifactSigner: artifactSigner,
            fileHandler: FileHandler.shared,
            fileSystem: fileSystem,
            multipartUploadStartCacheService: multipartUploadStartCacheService,
            multipartUploadGenerateURLCacheService: multipartUploadGenerateURLCacheService,
            multipartUploadCompleteCacheService: multipartUploadCompleteCacheService,
            downloader: downloader,
            retryProvider: retryProvider,
            multipartUploadArtifactService: multipartUploadArtifactService,
            concurrencyLimit: 15
        )
    }

    @Test(.inTemporaryDirectory) func fetch_when_macro_artifact_exists() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let macroPath = temporaryDirectory.appending(component: "target.macro")
        try FileHandler.shared.touch(macroPath)
        let zipPath = try await FileArchiver(paths: [macroPath]).zip(name: "test")

        let serverCacheArtifact = ServerCacheArtifact.test()

        given(getCacheService).getCache(
            serverURL: .value(Constants.URLs.production),
            projectId: .value(fullHandle),
            hash: .value("hash"),
            name: .value("target"),
            cacheCategory: .value(.binaries)
        ).willReturn(serverCacheArtifact)
        given(downloader).download(url: .value(serverCacheArtifact.url)).willReturn(zipPath)

        // When
        let got = try await subject.fetch(
            Set([.init(name: "target", hash: "hash")]),
            cacheCategory: .binaries
        )

        // Then
        let path = try #require(
            got[.test(name: "target", hash: "hash", source: .remote, cacheCategory: .binaries)]
        )
        let exists = try await fileSystem.exists(path)
        #expect(exists == true)
        #expect(try artifactSigner.isValid(path) == true)
    }

    @Test(.inTemporaryDirectory) func fetch_when_framework_artifact_exists() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let frameworkPath = temporaryDirectory.appending(component: "target.framework")
        try FileHandler.shared.createFolder(frameworkPath)
        let zipPath = try await FileArchiver(paths: [frameworkPath]).zip(name: "test")

        let serverCacheArtifact = ServerCacheArtifact.test()

        given(getCacheService).getCache(
            serverURL: .value(Constants.URLs.production),
            projectId: .value(fullHandle),
            hash: .value("hash"),
            name: .value("target"),
            cacheCategory: .value(.binaries)
        ).willReturn(serverCacheArtifact)
        given(downloader).download(url: .value(serverCacheArtifact.url)).willReturn(zipPath)

        // When
        let got = try await subject.fetch(
            Set([.init(name: "target", hash: "hash")]),
            cacheCategory: .binaries
        )

        // Then
        let path = try #require(
            got[.test(name: "target", hash: "hash", source: .remote, cacheCategory: .binaries)]
        )
        let exists = try await fileSystem.exists(path)
        #expect(exists == true)
        #expect(try artifactSigner.isValid(path) == true)
    }

    @Test(.inTemporaryDirectory) func fetch_when_get_cache_returns_internal_server_error()
        async throws
    {
        // Given
        given(getCacheService)
            .getCache(
                serverURL: .any,
                projectId: .any,
                hash: .any,
                name: .any,
                cacheCategory: .any
            )
            .willThrow(GetCacheServiceError.unknownError(500))

        // When
        let got = try await subject.fetch(
            Set([.init(name: "target", hash: "hash")]),
            cacheCategory: .binaries
        )

        // Then
        #expect(got == [:])
    }

    @Test(.inTemporaryDirectory)
    func fetch_when_get_cache_aciton_item_returns_internal_server_error() async throws {
        // Given
        given(getCacheActionItemService)
            .getCacheActionItem(
                serverURL: .any,
                fullHandle: .any,
                hash: .any
            )
            .willThrow(GetCacheActionItemServiceError.unknownError(500))

        // When
        let got = try await subject.fetch(
            Set([.init(name: "target", hash: "hash")]),
            cacheCategory: .selectiveTests
        )

        // Then
        #expect(got == [:])
    }

    @Test(.withMockedLogger(), .inTemporaryDirectory)
    func fetch_when_framework_artifacts_with_same_hash() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let frameworkOnePath = temporaryDirectory.appending(components: "frameworkOne.framework")
        try await fileSystem.makeDirectory(at: frameworkOnePath)
        let zipPathOne = try await FileArchiver(paths: [frameworkOnePath]).zip(name: "test-one")
        let frameworkTwoPath = temporaryDirectory.appending(component: "frameworkTwo.framework")
        try await fileSystem.makeDirectory(at: frameworkTwoPath)
        let zipPathTwo = try await FileArchiver(paths: [frameworkTwoPath]).zip(name: "test-two")

        let serverCacheArtifactOne = ServerCacheArtifact.test(
            url: URL(string: "https://tuist.dev/storage/framework-one")!
        )
        let serverCacheArtifactTwo = ServerCacheArtifact.test(
            url: URL(string: "https://tuist.dev/storage/framework-two")!
        )

        given(getCacheService).getCache(
            serverURL: .value(Constants.URLs.production),
            projectId: .value(fullHandle),
            hash: .value("hash"),
            name: .value("frameworkOne"),
            cacheCategory: .value(.binaries)
        ).willReturn(serverCacheArtifactOne)
        given(getCacheService).getCache(
            serverURL: .value(Constants.URLs.production),
            projectId: .value(fullHandle),
            hash: .value("hash"),
            name: .value("frameworkTwo"),
            cacheCategory: .value(.binaries)
        ).willReturn(serverCacheArtifactTwo)
        given(downloader).download(url: .value(serverCacheArtifactOne.url)).willReturn(zipPathOne)
        given(downloader).download(url: .value(serverCacheArtifactTwo.url)).willReturn(zipPathTwo)

        // When
        let got = try await subject.fetch(
            Set(
                [
                    CacheStorableItem(name: "frameworkOne", hash: "hash"),
                    CacheStorableItem(name: "frameworkTwo", hash: "hash"),
                ]
            ),
            cacheCategory: .binaries
        )

        // Then
        let pathOne = try #require(
            got[
                .test(name: "frameworkOne", hash: "hash", source: .remote, cacheCategory: .binaries)
            ]
        )
        let existsOne = try await fileSystem.exists(pathOne)
        #expect(existsOne == true)
        #expect(try artifactSigner.isValid(pathOne) == true)
        let pathTwo = try #require(
            got[
                .test(name: "frameworkTwo", hash: "hash", source: .remote, cacheCategory: .binaries)
            ]
        )
        let existsTwo = try await fileSystem.exists(pathTwo)
        #expect(existsTwo == true)
        #expect(try artifactSigner.isValid(pathTwo) == true)
        #expect(pathOne != pathTwo)
    }

    @Test(.inTemporaryDirectory) func fetch_when_bundle_artifact_exists() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let bundlePath = temporaryDirectory.appending(component: "target.bundle")
        try FileHandler.shared.createFolder(bundlePath)
        let zipPath = try await FileArchiver(paths: [bundlePath]).zip(name: "test")

        let serverCacheArtifact = ServerCacheArtifact.test()

        given(getCacheService).getCache(
            serverURL: .value(Constants.URLs.production),
            projectId: .value(fullHandle),
            hash: .value("hash"),
            name: .value("target"),
            cacheCategory: .value(.binaries)
        ).willReturn(serverCacheArtifact)
        given(downloader).download(url: .value(serverCacheArtifact.url)).willReturn(zipPath)

        // When
        let got = try await subject.fetch(
            Set([.init(name: "target", hash: "hash")]),
            cacheCategory: .binaries
        )

        // Then
        let path = try #require(
            got[.test(name: "target", hash: "hash", source: .remote, cacheCategory: .binaries)]
        )
        let exists = try await fileSystem.exists(path)
        #expect(exists == true)
        #expect(try artifactSigner.isValid(path) == true)
    }

    @Test(.inTemporaryDirectory) func fetch_when_xcframework_artifact_exists() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let xcframeworkPath = temporaryDirectory.appending(component: "target.xcframework")
        try FileHandler.shared.createFolder(xcframeworkPath)
        let zipPath = try await FileArchiver(paths: [xcframeworkPath]).zip(name: "test")

        let serverCacheArtifact = ServerCacheArtifact.test()

        given(getCacheService).getCache(
            serverURL: .value(Constants.URLs.production),
            projectId: .value(fullHandle),
            hash: .value("hash"),
            name: .value("target"),
            cacheCategory: .value(.binaries)
        ).willReturn(serverCacheArtifact)
        given(downloader).download(url: .value(serverCacheArtifact.url)).willReturn(zipPath)

        // When
        let got = try await subject.fetch(
            Set([.init(name: "target", hash: "hash")]),
            cacheCategory: .binaries
        )

        // Then
        let path = try #require(
            got[.test(name: "target", hash: "hash", source: .remote, cacheCategory: .binaries)]
        )
        let exists = try await fileSystem.exists(path)
        #expect(exists == true)
        #expect(try artifactSigner.isValid(path) == true)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedLogger(),
        .withScopedAlertController()
    ) func fetch_when_artifact_invalid_exists() async throws {
        // Given
        let zipPath = try await FileArchiver(paths: []).zip(name: "test") // Invalid

        let serverCacheArtifact = ServerCacheArtifact.test()

        given(getCacheService).getCache(
            serverURL: .value(Constants.URLs.production),
            projectId: .value(fullHandle),
            hash: .value("hash"),
            name: .value("target"),
            cacheCategory: .value(.binaries)
        ).willReturn(serverCacheArtifact)
        given(downloader).download(url: .value(serverCacheArtifact.url)).willReturn(zipPath)

        // When
        let got = try await subject.fetch(
            Set([.init(name: "target", hash: "hash")]), cacheCategory: .binaries
        )

        // Then
        #expect(got.isEmpty == true)
        #expect(AlertController.current.warnings().map(\.message)
            .map { $0.plain() } ==
            [
                "Skipping fetching binaries due to an unexpected error: The downloaded artifact with hash \'hash\' has an incorrect format and doesn\'t contain xcframework, framework, bundle, or macro",
            ]
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedLogger(),
        .withScopedAlertController()
    ) func fetch_get_url_service_errors() async throws {
        // Given
        let error = TestError()

        given(getCacheService).getCache(
            serverURL: .value(Constants.URLs.production),
            projectId: .value(fullHandle),
            hash: .value("hash"),
            name: .value("target"),
            cacheCategory: .value(.binaries)
        ).willThrow(error)

        // When
        let got = try await subject.fetch(
            Set([.init(name: "target", hash: "hash")]), cacheCategory: .binaries
        )

        // Then
        #expect(got.isEmpty == true)
        #expect(AlertController.current.warnings().map(\.message)
            .map { $0.plain() } == ["Skipping fetching binaries due to an unexpected error: \(error.localizedDescription)"]
        )
    }

    @Test(.inTemporaryDirectory, .withMockedLogger(), .withScopedAlertController())
    func fetch_when_client_throws_no_connection_error() async throws {
        // Given
        given(getCacheService).getCache(
            serverURL: .value(Constants.URLs.production),
            projectId: .value(fullHandle),
            hash: .value("hash"),
            name: .value("target"),
            cacheCategory: .value(.binaries)
        ).willThrow(
            ClientError(
                operationID: "some-id",
                operationInput: {} as Sendable,
                causeDescription: "Cause",
                underlyingError: TestError(
                    "The Internet connection appears to be offline"
                )
            )
        )

        // When
        let got = try await subject.fetch(
            Set([.init(name: "target", hash: "hash")]), cacheCategory: .binaries
        )

        // Then
        #expect(got.isEmpty == true)
        #expect(AlertController.current.warnings().map(\.message)
            .map { $0.plain() } == ["You seem to be offline, skipping fetching remote binaries..."]
        )
    }

    @Test(.inTemporaryDirectory, .withMockedLogger(), .withScopedAlertController())
    func fetch_when_client_throws_server_unreachable_error() async throws {
        // Given
        given(getCacheService).getCache(
            serverURL: .value(Constants.URLs.production),
            projectId: .value(fullHandle),
            hash: .value("hash"),
            name: .value("target"),
            cacheCategory: .value(.binaries)
        ).willThrow(
            ClientError(
                operationID: "some-id",
                operationInput: {} as Sendable,
                causeDescription: "cause",
                underlyingError: TestError(
                    "Could not connect to the server"
                )
            )
        )

        // When
        let got = try await subject.fetch(
            Set([.init(name: "target", hash: "hash")]), cacheCategory: .binaries
        )

        // Then
        #expect(got.isEmpty == true)
        #expect(AlertController.current.warnings().map(\.message)
            .map { $0.plain() } == ["The Tuist server is unreachable, skipping fetching remote binaries"]
        )
    }

    @Test(.inTemporaryDirectory, .withMockedLogger(), .withScopedAlertController())
    func fetch_when_client_throws_unknown_client_error() async throws {
        // Given
        let error = ClientError(
            operationID: "some-id",
            operationInput: {} as Sendable,
            causeDescription: "cause",
            underlyingError: TestError(
                "Request timed out."
            )
        )
        given(getCacheService).getCache(
            serverURL: .value(Constants.URLs.production),
            projectId: .value(fullHandle),
            hash: .value("hash"),
            name: .value("target"),
            cacheCategory: .value(.binaries)
        ).willThrow(
            error
        )

        // When
        let got = try await subject.fetch(
            Set([.init(name: "target", hash: "hash")]), cacheCategory: .binaries
        )

        // Then
        #expect(got.isEmpty == true)
        #expect(AlertController.current.warnings().map(\.message)
            .map { $0.plain() } ==
            ["Skipping fetching binaries due to an unexpected error: \(error.underlyingError.localizedDescription)"]
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedLogger(),
        .withScopedAlertController()
    ) func fetch_get_url_downloader_errors() async throws {
        // Given
        let error = TestError()
        let serverCacheArtifact = ServerCacheArtifact.test()

        given(getCacheService).getCache(
            serverURL: .value(Constants.URLs.production),
            projectId: .value(fullHandle),
            hash: .value("hash"),
            name: .value("target"),
            cacheCategory: .value(.binaries)
        ).willReturn(serverCacheArtifact)
        given(downloader).download(url: .value(serverCacheArtifact.url)).willThrow(error)

        // When
        let got = try await subject.fetch(
            Set([.init(name: "target", hash: "hash")]), cacheCategory: .binaries
        )

        // Then
        #expect(got.isEmpty == true)
        #expect(AlertController.current.warnings().map(\.message)
            .map { $0.plain() } == ["Skipping fetching binaries due to an unexpected error: \(error.localizedDescription)"]
        )
    }

    @Test(.inTemporaryDirectory) func test_store() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let macroPath = temporaryDirectory.appending(component: "macro.macro")
        try FileHandler.shared.touch(macroPath)
        given(multipartUploadStartCacheService).uploadCache(
            serverURL: .value(Constants.URLs.production),
            projectId: .value(fullHandle),
            hash: .value("hash"),
            name: .value("target"),
            cacheCategory: .value(.binaries)
        ).willReturn("upload-id")
        given(multipartUploadGenerateURLCacheService)
            .uploadCache(
                serverURL: .value(Constants.URLs.production),
                projectId: .value(fullHandle),
                hash: .value("hash"),
                name: .value("target"),
                cacheCategory: .value(.binaries),
                uploadId: .value("upload-id"),
                partNumber: .value(1),
                contentLength: .value(20)
            )
            .willReturn("https://tuist.dev/upload")
        var generateUploadURLCallback: ((MultipartUploadArtifactPart) async throws -> String)!
        given(multipartUploadArtifactService)
            .multipartUploadArtifact(
                artifactPath: .any,
                generateUploadURL: .matching {
                    generateUploadURLCallback = $0
                    return true
                },
                updateProgress: .any
            )
            .willReturn([(etag: "etag", partNumber: 1)])
        given(multipartUploadCompleteCacheService).uploadCache(
            serverURL: .value(Constants.URLs.production),
            projectId: .value(fullHandle),
            hash: .value("hash"),
            name: .value("target"),
            cacheCategory: .value(.binaries),
            uploadId: .value("upload-id"),
            parts: .matching { values in
                values.contains(where: { $0.etag == "etag" && $0.partNumber == 1 })
            }
        ).willReturn(())

        // When/Then
        try await subject.store(
            [.init(name: "target", hash: "hash"): [macroPath]], cacheCategory: .binaries
        )
    }

    @Test(.inTemporaryDirectory)
    func store_when_multipart_upload_start_cache_service_throws_internal_server_error()
        async throws
    {
        // Given
        let binaryPath = try #require(FileSystem.temporaryTestDirectory)
        given(multipartUploadStartCacheService).uploadCache(
            serverURL: .value(Constants.URLs.production),
            projectId: .value(fullHandle),
            hash: .value("hash"),
            name: .value("target"),
            cacheCategory: .value(.binaries)
        ).willThrow(
            MultipartUploadStartCacheServiceError.unknownError(500)
        )

        // When / Then
        try await subject.store(
            [.init(name: "target", hash: "hash"): [binaryPath]], cacheCategory: .binaries
        )
    }

    @Test(.inTemporaryDirectory, .withMockedLogger())
    func store_when_client_throws_no_connection_error() async throws {
        // Given
        let binaryPath = try #require(FileSystem.temporaryTestDirectory)
        given(multipartUploadStartCacheService).uploadCache(
            serverURL: .value(Constants.URLs.production),
            projectId: .value(fullHandle),
            hash: .value("hash"),
            name: .value("target"),
            cacheCategory: .value(.binaries)
        ).willThrow(
            ClientError(
                operationID: "some-id",
                operationInput: {} as Sendable,
                causeDescription: "cause",
                underlyingError: TestError(
                    "The Internet connection appears to be offline"
                )
            )
        )

        // When
        try await subject.store(
            [.init(name: "target", hash: "hash"): [binaryPath]], cacheCategory: .binaries
        )

        // Then
        TuistTest.expectLogs("You seem to be offline, skipping storing remote binaries")
    }

    @Test(.inTemporaryDirectory, .withMockedLogger())
    func store_when_client_throws_server_unreachable_error() async throws {
        // Given
        let binaryPath = try #require(FileSystem.temporaryTestDirectory)
        given(multipartUploadStartCacheService).uploadCache(
            serverURL: .value(Constants.URLs.production),
            projectId: .value(fullHandle),
            hash: .value("hash"),
            name: .value("target"),
            cacheCategory: .value(.binaries)
        ).willThrow(
            ClientError(
                operationID: "some-id",
                operationInput: {} as Sendable,
                causeDescription: "cause",
                underlyingError: TestError(
                    "Could not connect to the server"
                )
            )
        )

        // When
        try await subject.store(
            [.init(name: "target", hash: "hash"): [binaryPath]], cacheCategory: .binaries
        )

        // Then
        TuistTest.expectLogs(
            "The Tuist server is unreachable, skipping storing remote binaries"
        )
    }

    @Test(.inTemporaryDirectory, .withMockedLogger())
    func store_when_client_throws_unknown_client_error() async throws {
        // Given
        let binaryPath = try #require(FileSystem.temporaryTestDirectory)
        given(multipartUploadStartCacheService).uploadCache(
            serverURL: .value(Constants.URLs.production),
            projectId: .value(fullHandle),
            hash: .value("hash"),
            name: .value("target"),
            cacheCategory: .value(.binaries)
        ).willThrow(
            ClientError(
                operationID: "some-id",
                operationInput: {} as Sendable,
                causeDescription: "cause",
                underlyingError: TestError(
                    "Request timed out."
                )
            )
        )

        // When
        try await subject.store(
            [.init(name: "target", hash: "hash"): [binaryPath]], cacheCategory: .binaries
        )

        // Then
        TuistTest.expectLogs("Request timed out.")
    }
}
