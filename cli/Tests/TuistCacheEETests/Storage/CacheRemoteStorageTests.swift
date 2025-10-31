import FileSystem
import FileSystemTesting
import Foundation
import HTTPTypes
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
        given(downloader).download(item: .any, url: .value(serverCacheArtifact.url)).willReturn(zipPath)

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
        given(downloader).download(item: .any, url: .value(serverCacheArtifact.url)).willReturn(zipPath)

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

        // Verify that the downloaded zip file was removed after extraction
        let zipExists = try await fileSystem.exists(zipPath)
        #expect(zipExists == false, "Downloaded zip file should be removed after extraction")
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

    @Test(.inTemporaryDirectory, .withScopedAlertController())
    func fetch_cache_action_items_when_not_found() async throws {
        // Given
        given(getCacheActionItemService)
            .getCacheActionItem(
                serverURL: .any,
                fullHandle: .any,
                hash: .any
            )
            .willThrow(GetCacheActionItemServiceError.notFound("Cache action item not found"))

        // When
        let got = try await subject.fetch(
            Set([.init(name: "target", hash: "hash")]),
            cacheCategory: .selectiveTests
        )

        // Then
        #expect(got == [:])
        #expect(AlertController.current.warnings().isEmpty == true)
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
        given(downloader).download(item: .any, url: .value(serverCacheArtifactOne.url)).willReturn(zipPathOne)
        given(downloader).download(item: .any, url: .value(serverCacheArtifactTwo.url)).willReturn(zipPathTwo)

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
        given(downloader).download(item: .any, url: .value(serverCacheArtifact.url)).willReturn(zipPath)

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
        given(downloader).download(item: .any, url: .value(serverCacheArtifact.url)).willReturn(zipPath)

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
        given(downloader).download(item: .any, url: .value(serverCacheArtifact.url)).willReturn(zipPath)

        // When/Then
        let got = try await subject.fetch(
            Set([.init(name: "target", hash: "hash")]), cacheCategory: .binaries
        )
        #expect(got == [:])

        #expect(AlertController.current.warnings().map(\.message)
            .map { $0.plain() } ==
            ["The following artifacts do not exist in the remote cache: target"]
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
            .map { $0.plain() } ==
            ["The remote cache server is currently unavailable. These artifacts could not be fetched: target"]
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
            .map { $0.plain() } == ["The network is unreachable. The following cached artifacts remain out of grasp: target"]
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
            .map { $0.plain() } ==
            ["The remote cache server is currently unavailable. These artifacts could not be fetched: target"]
        )
    }

    @Test(.inTemporaryDirectory, .withMockedLogger(), .withScopedAlertController())
    func fetch_when_client_throws_server_payment_required_error() async throws {
        // Given
        let serverErrorMessage = "Payment method required"
        let error = ClientError(
            operationID: "some-id",
            operationInput: {} as Sendable,
            response: HTTPResponse(status: HTTPResponse.Status(code: 402)),
            responseBody: HTTPBody(stringLiteral: "{ \"message\": \"\(serverErrorMessage)\"}"),
            causeDescription: "cause",
            underlyingError: TestError(
                "Could not connect to the server"
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
            ["Your subscription limits have been reached. Unable to retrieve the following cached artifacts: target"]
        )
    }

    @Test(.inTemporaryDirectory, .withMockedLogger(), .withScopedAlertController())
    func fetch_when_client_throws_server_payment_required_error_without_error_in_body() async throws {
        // Given
        let error = ClientError(
            operationID: "some-id",
            operationInput: {} as Sendable,
            response: HTTPResponse(status: HTTPResponse.Status(code: 402)),
            responseBody: HTTPBody(stringLiteral: "{}"),
            causeDescription: "cause",
            underlyingError: TestError(
                "Could not connect to the server"
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
            ["Your subscription limits have been reached. Unable to retrieve the following cached artifacts: target"]
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
            ["The remote cache server is currently unavailable. These artifacts could not be fetched: target"]
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
        given(downloader).download(item: .any, url: .value(serverCacheArtifact.url)).willThrow(error)

        // When
        let got = try await subject.fetch(
            Set([.init(name: "target", hash: "hash")]), cacheCategory: .binaries
        )

        // Then
        #expect(got.isEmpty == true)
        #expect(AlertController.current.warnings().map(\.message)
            .map { $0.plain() } ==
            ["The remote cache server is currently unavailable. These artifacts could not be fetched: target"]
        )
    }

    @Test(.inTemporaryDirectory, .withScopedAlertController())
    func fetch_when_downloader_returns_nil_for_not_found() async throws {
        // Given
        let serverCacheArtifact = ServerCacheArtifact.test()

        given(getCacheService).getCache(
            serverURL: .value(Constants.URLs.production),
            projectId: .value(fullHandle),
            hash: .value("hash"),
            name: .value("target"),
            cacheCategory: .value(.binaries)
        ).willReturn(serverCacheArtifact)
        given(downloader).download(item: .any, url: .value(serverCacheArtifact.url)).willReturn(nil)

        // When
        let got = try await subject.fetch(
            Set([.init(name: "target", hash: "hash")]), cacheCategory: .binaries
        )

        // Then
        #expect(got.isEmpty == true)
        #expect(AlertController.current.warnings().isEmpty == true)
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
        given(multipartUploadArtifactService)
            .multipartUploadArtifact(
                artifactPath: .any,
                generateUploadURL: .any,
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

        // When
        let result = try await subject.store(
            [.init(name: "target", hash: "hash"): [macroPath]], cacheCategory: .binaries
        )

        // Then
        #expect(result.count == 1)
        #expect(result.first?.name == "target")
        #expect(result.first?.hash == "hash")
    }

    @Test(.inTemporaryDirectory, .withScopedAlertController())
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

        // When
        let result = try await subject.store(
            [.init(name: "target", hash: "hash"): [binaryPath]], cacheCategory: .binaries
        )

        // Then
        #expect(result.isEmpty)
        #expect(AlertController.current.warnings()
            .contains { $0.message.plain().contains("Failed to upload target with hash hash due to unexpected error:") }
        )
    }

    @Test(.inTemporaryDirectory)
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
        let result = try await subject.store(
            [.init(name: "target", hash: "hash"): [binaryPath]], cacheCategory: .binaries
        )

        // Then
        #expect(result.isEmpty)
    }

    @Test(.inTemporaryDirectory)
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
        let result = try await subject.store(
            [.init(name: "target", hash: "hash"): [binaryPath]], cacheCategory: .binaries
        )

        // Then
        #expect(result.isEmpty)
    }

    @Test(.inTemporaryDirectory, .withScopedAlertController())
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
        let result = try await subject.store(
            [.init(name: "target", hash: "hash"): [binaryPath]], cacheCategory: .binaries
        )

        // Then
        #expect(result.isEmpty)
        #expect(AlertController.current.warnings()
            .contains { $0.message.plain().contains("Failed to upload target with hash hash due to unexpected error:") }
        )
    }

    // MARK: - Upload Error Handling Tests

    @Test(.inTemporaryDirectory) func store_returns_successfully_uploaded_items() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let macroPath1 = temporaryDirectory.appending(component: "macro1.macro")
        let macroPath2 = temporaryDirectory.appending(component: "macro2.macro")
        try FileHandler.shared.touch(macroPath1)
        try FileHandler.shared.touch(macroPath2)

        let items = [
            CacheStorableItem(name: "target1", hash: "hash1"): [macroPath1],
            CacheStorableItem(name: "target2", hash: "hash2"): [macroPath2],
        ]

        // Mock successful upload for both items
        given(multipartUploadStartCacheService).uploadCache(
            serverURL: .any,
            projectId: .any,
            hash: .any,
            name: .any,
            cacheCategory: .any
        ).willReturn("upload-id")

        given(multipartUploadGenerateURLCacheService).uploadCache(
            serverURL: .any,
            projectId: .any,
            hash: .any,
            name: .any,
            cacheCategory: .any,
            uploadId: .any,
            partNumber: .any,
            contentLength: .any
        ).willReturn("https://tuist.dev/upload")

        given(multipartUploadArtifactService).multipartUploadArtifact(
            artifactPath: .any,
            generateUploadURL: .any,
            updateProgress: .any
        ).willReturn([(etag: "etag", partNumber: 1)])

        given(multipartUploadCompleteCacheService).uploadCache(
            serverURL: .any,
            projectId: .any,
            hash: .any,
            name: .any,
            cacheCategory: .any,
            uploadId: .any,
            parts: .any
        ).willReturn(())

        // When
        let result = try await subject.store(items, cacheCategory: .binaries)

        // Then
        #expect(result.count == 2)
        #expect(result.contains(where: { $0.name == "target1" && $0.hash == "hash1" }))
        #expect(result.contains(where: { $0.name == "target2" && $0.hash == "hash2" }))
    }

    @Test(.inTemporaryDirectory, .withScopedAlertController())
    func store_handles_individual_upload_failures_gracefully() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let macroPath1 = temporaryDirectory.appending(component: "macro1.macro")
        let macroPath2 = temporaryDirectory.appending(component: "macro2.macro")
        try FileHandler.shared.touch(macroPath1)
        try FileHandler.shared.touch(macroPath2)

        let items = [
            CacheStorableItem(name: "target1", hash: "hash1"): [macroPath1],
            CacheStorableItem(name: "target2", hash: "hash2"): [macroPath2],
        ]

        // Mock successful upload for target2, but failure for target1
        given(multipartUploadStartCacheService).uploadCache(
            serverURL: .any,
            projectId: .any,
            hash: .value("hash1"),
            name: .value("target1"),
            cacheCategory: .any
        ).willThrow(MultipartUploadStartCacheServiceError.unknownError(500))

        given(multipartUploadStartCacheService).uploadCache(
            serverURL: .any,
            projectId: .any,
            hash: .value("hash2"),
            name: .value("target2"),
            cacheCategory: .any
        ).willReturn("upload-id")

        given(multipartUploadGenerateURLCacheService).uploadCache(
            serverURL: .any,
            projectId: .any,
            hash: .value("hash2"),
            name: .value("target2"),
            cacheCategory: .any,
            uploadId: .any,
            partNumber: .any,
            contentLength: .any
        ).willReturn("https://tuist.dev/upload")

        given(multipartUploadArtifactService).multipartUploadArtifact(
            artifactPath: .any,
            generateUploadURL: .any,
            updateProgress: .any
        ).willReturn([(etag: "etag", partNumber: 1)])

        given(multipartUploadCompleteCacheService).uploadCache(
            serverURL: .any,
            projectId: .any,
            hash: .value("hash2"),
            name: .value("target2"),
            cacheCategory: .any,
            uploadId: .any,
            parts: .any
        ).willReturn(())

        // When
        let result = try await subject.store(items, cacheCategory: .binaries)

        // Then
        #expect(result.count == 1)
        #expect(result.first?.name == "target2")
        #expect(result.first?.hash == "hash2")

        // Verify warning was logged for failed upload
        #expect(AlertController.current.warnings()
            .contains { $0.message.plain().contains("Failed to upload target1 with hash hash1 due to unexpected error:") }
        )
    }
}
