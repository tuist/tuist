import FileSystem
import FileSystemTesting
import Foundation
import HTTPTypes
import Mockable
import OpenAPIRuntime
import Path
import Testing
import TuistAlert
import TuistCache
import TuistConstants
import TuistCore
import TuistServer
import TuistSupport
import XcodeGraph

@testable import TuistCacheEE
@testable import TuistSupport
@testable import TuistTesting

struct ModuleCacheRemoteStorageTests {
    private struct TestError: Equatable, Error, LocalizedError {
        var description: String

        init(_ description: String = "") {
            self.description = description
        }
    }

    private var subject: ModuleCacheRemoteStorage!
    private let fullHandle = "tuist/tuist"
    private var cacheDirectoriesProvider: MockCacheDirectoriesProviding!
    private var downloadModuleCacheService: MockDownloadModuleCacheServicing!
    private var getCacheActionItemService: MockGetCacheActionItemServicing!
    private var uploadCacheActionItemService: MockUploadCacheActionItemServicing!
    private var multipartUploadService: MockMultipartModuleCacheUploadServicing!
    private var serverAuthenticationController: MockServerAuthenticationControlling!
    private var artifactSigner: ArtifactSigner!
    private var retryProvider: RetryProviding!
    private var fileSystem: FileSysteming!

    init() throws {
        cacheDirectoriesProvider = .init()
        downloadModuleCacheService = .init()
        getCacheActionItemService = .init()
        uploadCacheActionItemService = .init()
        multipartUploadService = .init()
        serverAuthenticationController = .init()
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .any)
            .willReturn(temporaryDirectory)
        artifactSigner = ArtifactSigner()
        retryProvider = RetryProvider()
        fileSystem = FileSystem()

        subject = ModuleCacheRemoteStorage(
            fullHandle: fullHandle,
            cacheURL: Constants.URLs.production,
            serverURL: Constants.URLs.production,
            serverAuthenticationController: serverAuthenticationController,
            fileArchiverFactory: FileArchivingFactory(),
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            multipartUploadService: multipartUploadService,
            downloadModuleCacheService: downloadModuleCacheService,
            getCacheActionItemService: getCacheActionItemService,
            uploadCacheActionItemService: uploadCacheActionItemService,
            artifactSigner: artifactSigner,
            fileHandler: FileHandler.shared,
            fileSystem: fileSystem,
            retryProvider: retryProvider,
            concurrencyLimit: 15
        )
    }

    // MARK: - Authentication Failure Tests (401/403)

    @Test(.inTemporaryDirectory, .withMockedLogger(), .withScopedAlertController())
    func fetch_when_download_service_returns_unauthorized() async throws {
        // Given
        given(downloadModuleCacheService)
            .downloadModuleCacheArtifact(
                accountHandle: .any,
                projectHandle: .any,
                hash: .any,
                name: .any,
                cacheCategory: .any,
                serverURL: .any,
                authenticationURL: .any,
                serverAuthenticationController: .any
            )
            .willThrow(DownloadModuleCacheServiceError.unauthorized("Unauthorized"))

        // When
        let got = try await subject.fetch(
            Set([.init(name: "target", hash: "hash")]),
            cacheCategory: .binaries
        )

        // Then
        #expect(got.isEmpty == true)
        #expect(AlertController.current.warnings().map(\.message)
            .map { $0.plain() } ==
            ["Authentication failed. Unable to retrieve the following cached artifacts: target"]
        )
    }

    @Test(.inTemporaryDirectory, .withMockedLogger(), .withScopedAlertController())
    func fetch_when_download_service_returns_forbidden() async throws {
        // Given
        given(downloadModuleCacheService)
            .downloadModuleCacheArtifact(
                accountHandle: .any,
                projectHandle: .any,
                hash: .any,
                name: .any,
                cacheCategory: .any,
                serverURL: .any,
                authenticationURL: .any,
                serverAuthenticationController: .any
            )
            .willThrow(DownloadModuleCacheServiceError.forbidden("Forbidden"))

        // When
        let got = try await subject.fetch(
            Set([.init(name: "target", hash: "hash")]),
            cacheCategory: .binaries
        )

        // Then
        #expect(got.isEmpty == true)
        #expect(AlertController.current.warnings().map(\.message)
            .map { $0.plain() } ==
            ["Authentication failed. Unable to retrieve the following cached artifacts: target"]
        )
    }

    @Test(.inTemporaryDirectory, .withMockedLogger(), .withScopedAlertController())
    func fetch_cache_action_items_when_get_cache_action_item_returns_unauthorized() async throws {
        // Given
        given(getCacheActionItemService)
            .getCacheActionItem(
                serverURL: .any,
                fullHandle: .any,
                hash: .any
            )
            .willThrow(GetCacheActionItemServiceError.unauthorized("Unauthorized"))

        // When
        let got = try await subject.fetch(
            Set([.init(name: "target", hash: "hash")]),
            cacheCategory: .selectiveTests
        )

        // Then
        #expect(got.isEmpty == true)
        #expect(AlertController.current.warnings().map(\.message)
            .map { $0.plain() } ==
            ["Authentication failed. Unable to retrieve the following cached artifacts: target"]
        )
    }

    @Test(.inTemporaryDirectory, .withMockedLogger(), .withScopedAlertController())
    func fetch_cache_action_items_when_get_cache_action_item_returns_forbidden() async throws {
        // Given
        given(getCacheActionItemService)
            .getCacheActionItem(
                serverURL: .any,
                fullHandle: .any,
                hash: .any
            )
            .willThrow(GetCacheActionItemServiceError.forbidden("Forbidden"))

        // When
        let got = try await subject.fetch(
            Set([.init(name: "target", hash: "hash")]),
            cacheCategory: .selectiveTests
        )

        // Then
        #expect(got.isEmpty == true)
        #expect(AlertController.current.warnings().map(\.message)
            .map { $0.plain() } ==
            ["Authentication failed. Unable to retrieve the following cached artifacts: target"]
        )
    }

    @Test(.inTemporaryDirectory, .withMockedLogger(), .withScopedAlertController())
    func fetch_when_client_throws_401_error() async throws {
        // Given
        let error = ClientError(
            operationID: "some-id",
            operationInput: {} as Sendable,
            response: HTTPResponse(status: HTTPResponse.Status(code: 401)),
            responseBody: HTTPBody(stringLiteral: "{ \"message\": \"Unauthorized\"}"),
            causeDescription: "cause",
            underlyingError: TestError("Unauthorized")
        )
        given(downloadModuleCacheService)
            .downloadModuleCacheArtifact(
                accountHandle: .any,
                projectHandle: .any,
                hash: .any,
                name: .any,
                cacheCategory: .any,
                serverURL: .any,
                authenticationURL: .any,
                serverAuthenticationController: .any
            )
            .willThrow(error)

        // When
        let got = try await subject.fetch(
            Set([.init(name: "target", hash: "hash")]),
            cacheCategory: .binaries
        )

        // Then
        #expect(got.isEmpty == true)
        #expect(AlertController.current.warnings().map(\.message)
            .map { $0.plain() } ==
            ["Authentication failed. Unable to retrieve the following cached artifacts: target"]
        )
    }

    @Test(.inTemporaryDirectory, .withMockedLogger(), .withScopedAlertController())
    func fetch_when_client_throws_403_error() async throws {
        // Given
        let error = ClientError(
            operationID: "some-id",
            operationInput: {} as Sendable,
            response: HTTPResponse(status: HTTPResponse.Status(code: 403)),
            responseBody: HTTPBody(stringLiteral: "{ \"message\": \"Forbidden\"}"),
            causeDescription: "cause",
            underlyingError: TestError("Forbidden")
        )
        given(downloadModuleCacheService)
            .downloadModuleCacheArtifact(
                accountHandle: .any,
                projectHandle: .any,
                hash: .any,
                name: .any,
                cacheCategory: .any,
                serverURL: .any,
                authenticationURL: .any,
                serverAuthenticationController: .any
            )
            .willThrow(error)

        // When
        let got = try await subject.fetch(
            Set([.init(name: "target", hash: "hash")]),
            cacheCategory: .binaries
        )

        // Then
        #expect(got.isEmpty == true)
        #expect(AlertController.current.warnings().map(\.message)
            .map { $0.plain() } ==
            ["Authentication failed. Unable to retrieve the following cached artifacts: target"]
        )
    }

    // MARK: - Payment Required Tests (402)

    @Test(.inTemporaryDirectory, .withMockedLogger(), .withScopedAlertController())
    func fetch_when_client_throws_402_payment_required_error() async throws {
        // Given
        let error = ClientError(
            operationID: "some-id",
            operationInput: {} as Sendable,
            response: HTTPResponse(status: HTTPResponse.Status(code: 402)),
            responseBody: HTTPBody(stringLiteral: "{ \"message\": \"Payment required\"}"),
            causeDescription: "cause",
            underlyingError: TestError("Payment required")
        )
        given(downloadModuleCacheService)
            .downloadModuleCacheArtifact(
                accountHandle: .any,
                projectHandle: .any,
                hash: .any,
                name: .any,
                cacheCategory: .any,
                serverURL: .any,
                authenticationURL: .any,
                serverAuthenticationController: .any
            )
            .willThrow(error)

        // When
        let got = try await subject.fetch(
            Set([.init(name: "target", hash: "hash")]),
            cacheCategory: .binaries
        )

        // Then
        #expect(got.isEmpty == true)
        #expect(AlertController.current.warnings().map(\.message)
            .map { $0.plain() } ==
            ["Your subscription limits have been reached. Unable to retrieve the following cached artifacts: target"]
        )
    }

    @Test(.inTemporaryDirectory, .withScopedAlertController())
    func fetch_when_download_service_returns_not_found_does_not_retry() async throws {
        // Given
        given(downloadModuleCacheService)
            .downloadModuleCacheArtifact(
                accountHandle: .any,
                projectHandle: .any,
                hash: .any,
                name: .any,
                cacheCategory: .any,
                serverURL: .any,
                authenticationURL: .any,
                serverAuthenticationController: .any
            )
            .willThrow(DownloadModuleCacheServiceError.notFound("Artifact not found"))

        // When
        let got = try await subject.fetch(
            Set([.init(name: "target", hash: "hash")]),
            cacheCategory: .binaries
        )

        // Then
        #expect(got.isEmpty == true)
        #expect(AlertController.current.warnings().isEmpty == true)
        verify(downloadModuleCacheService)
            .downloadModuleCacheArtifact(
                accountHandle: .any,
                projectHandle: .any,
                hash: .any,
                name: .any,
                cacheCategory: .any,
                serverURL: .any,
                authenticationURL: .any,
                serverAuthenticationController: .any
            )
            .called(1)
    }

    @Test(.inTemporaryDirectory, .withMockedLogger(), .withScopedAlertController())
    func fetch_cache_action_items_when_get_cache_action_item_returns_payment_required() async throws {
        // Given
        given(getCacheActionItemService)
            .getCacheActionItem(
                serverURL: .any,
                fullHandle: .any,
                hash: .any
            )
            .willThrow(GetCacheActionItemServiceError.paymentRequired("Payment required"))

        // When
        let got = try await subject.fetch(
            Set([.init(name: "target", hash: "hash")]),
            cacheCategory: .selectiveTests
        )

        // Then
        #expect(got.isEmpty == true)
        #expect(AlertController.current.warnings().map(\.message)
            .map { $0.plain() } ==
            ["Your subscription limits have been reached. Unable to retrieve the following cached artifacts: target"]
        )
    }
}
