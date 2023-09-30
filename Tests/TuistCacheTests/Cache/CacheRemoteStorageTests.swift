import TSCBasic
import TuistCacheTesting
import TuistCloud
import TuistCloudTesting
import TuistCore
import TuistGraph
import TuistGraphTesting
import TuistSupport
import XCTest

@testable import TuistCache
@testable import TuistCacheTesting
@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class CacheRemoteStorageTests: TuistUnitTestCase {
    private var subject: CacheRemoteStorage!
    private var cloudConfig: Cloud!
    private var fileArchiverFactory: MockFileArchivingFactory!
    private var fileArchiver: MockFileArchiver!
    private var fileUnarchiver: MockFileUnarchiver!
    private var fileClient: MockFileClient!
    private var zipPath: AbsolutePath!
    private var cacheExistsService: MockCacheExistsService!
    private var getCacheService: MockGetCacheService!
    private var uploadCacheService: MockUploadCacheService!
    private var verifyCacheUploadService: MockVerifyCacheUploadService!
    private let receivedUploadURL = URL(string: "https://remote.storage.com/upload")!
    private var cacheDirectoriesProvider: MockCacheDirectoriesProvider!

    override func setUpWithError() throws {
        try super.setUpWithError()

        zipPath = fixturePath(path: try RelativePath(validating: "uUI.xcframework.zip"))

        cloudConfig = .test()
        cacheExistsService = MockCacheExistsService()
        getCacheService = MockGetCacheService()
        uploadCacheService = MockUploadCacheService()
        verifyCacheUploadService = MockVerifyCacheUploadService()
        fileArchiverFactory = MockFileArchivingFactory()
        fileArchiver = MockFileArchiver()
        fileUnarchiver = MockFileUnarchiver()
        fileArchiver.stubbedZipResult = zipPath
        fileArchiverFactory.stubbedMakeFileArchiverResult = fileArchiver
        fileArchiverFactory.stubbedMakeFileUnarchiverResult = fileUnarchiver
        fileClient = MockFileClient()
        fileClient.stubbedDownloadResult = zipPath

        cacheDirectoriesProvider = try MockCacheDirectoriesProvider()
        cacheDirectoriesProvider.cacheDirectoryStub = try temporaryPath()

        subject = CacheRemoteStorage(
            cloudConfig: cloudConfig,
            fileArchiverFactory: fileArchiverFactory,
            fileClient: fileClient,
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            cacheExistsService: cacheExistsService,
            getCacheService: getCacheService,
            uploadCacheService: uploadCacheService,
            verifyCacheUploadService: verifyCacheUploadService
        )
    }

    override func tearDown() {
        subject = nil
        cloudConfig = nil
        fileArchiver = nil
        fileArchiverFactory = nil
        fileClient = nil
        zipPath = nil
        cacheExistsService = nil
        getCacheService = nil
        uploadCacheService = nil
        verifyCacheUploadService = nil
        cacheDirectoriesProvider = nil
        super.tearDown()
    }

    // - exists

    func test_exists_whenClientReturnsAnError() async throws {
        // Given
        cacheExistsService.cacheExistsStub = { _, _, _, _ in
            throw CacheExistsServiceError.unauthorized("Unauthorized")
        }

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.exists(name: "targetName", hash: "acho tio"),
            CacheExistsServiceError.unauthorized("Unauthorized")
        )
    }

    func test_exists_whenClientReturnsASuccess() async throws {
        // When
        let result = try await subject.exists(name: "targetName", hash: "acho tio")

        // Then
        XCTAssertTrue(result)
    }

    func test_exists_whenArtifactDoesNotExist() async throws {
        // Given
        cacheExistsService.cacheExistsStub = { _, _, _, _ in
            throw CacheExistsServiceError.notFound("Artifact not found")
        }

        // When
        let result = try await subject.exists(name: "targetName", hash: "acho tio")

        // Then
        XCTAssertFalse(result)
    }

    // - fetch

    func test_fetch_whenClientReturnsAnError() async throws {
        // Given
        getCacheService.getCacheStub = { _, _, _, _ in
            throw GetCacheServiceError.paymentRequired("Payment required")
        }

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.fetch(name: "targetName", hash: "acho tio"),
            GetCacheServiceError.paymentRequired("Payment required")
        )
    }

    func test_fetch_whenArchiveContainsIncorrectRootFolderAfterUnzipping_expectErrorThrown() async throws {
        // Given
        let hash = "foobar"
        let paths = try createFolders(["Unarchived/\(hash)/IncorrectRootFolderAfterUnzipping"])
        fileUnarchiver.stubbedUnzipResult = paths.first

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.fetch(name: "targetName", hash: hash),
            CacheRemoteStorageError.artifactNotFound(hash: hash)
        )
    }

    func test_fetch_whenClientReturnsASuccess_returnsCorrectRootFolderAfterUnzipping() async throws {
        // Given
        let hash = "bar_foo"
        let paths = try createFolders(["Unarchived/\(hash)/myFramework.xcframework"])
        fileUnarchiver.stubbedUnzipResult = paths.first?.parentDirectory

        // When
        let result = try await subject.fetch(name: "targetName", hash: hash)

        // Then
        let expectedPath = cacheDirectoriesProvider.cacheDirectory(for: .builds)
            .appending(try RelativePath(validating: "\(hash)/myFramework.xcframework"))
        XCTAssertEqual(result, expectedPath)
    }

    func test_fetch_whenClientReturnsASuccess_givesFileClientTheCorrectURL() async throws {
        // Given
        let url = URL(string: "https://tuist.io/acho/tio")!
        getCacheService.getCacheStub = { _, _, _, _ in
            .test(url: url)
        }

        let hash = "foo_bar"
        let paths = try createFolders(["Unarchived/\(hash)/myFramework.xcframework"])
        fileUnarchiver.stubbedUnzipResult = paths.first!.parentDirectory

        // When
        _ = try await subject.fetch(name: "targetName", hash: hash)

        // Then
        XCTAssertEqual(fileClient.invokedDownloadParameters?.url, url)
    }

    func test_fetch_whenClientReturnsASuccess_givesFileArchiverTheCorrectDestinationPath() async throws {
        // Given
        let paths = try createFolders(["Unarchived/\(hash)/Framework.framework"])
        fileUnarchiver.stubbedUnzipResult = paths.first?.parentDirectory

        let hash = "foo_bar"

        // When
        _ = try await subject.fetch(name: "targetName", hash: hash)

        // Then
        XCTAssertTrue(fileUnarchiver.invokedUnzip)
    }

    // - store

    func test_store_whenClientReturnsAnError() async throws {
        // Given
        var verifyCacheUploadWasCalled = false
        verifyCacheUploadService.verifyCacheUploadStub = { _, _, _, _, _ in
            verifyCacheUploadWasCalled = true
        }
        uploadCacheService.uploadCacheStub = { _, _, _, _, _ in
            throw UploadCacheServiceError.unknownError(500)
        }

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.store(name: "targetName", hash: "acho tio", paths: [.root]),
            UploadCacheServiceError.unknownError(500)
        )
        XCTAssertFalse(verifyCacheUploadWasCalled)
    }

    func test_store_whenClientReturnsASuccess() async throws {
        // Given
        let storeURL = URL(string: "https://tuist.cache.io/store")!
        uploadCacheService.uploadCacheStub = { _, _, _, _, _ in
            .test(
                url: storeURL
            )
        }
        fileArchiver.stubbedZipResult = zipPath

        // When
        _ = try await subject.store(name: "targetName", hash: "foo_bar", paths: [.root])

        // Then
        if let tuple = fileClient.invokedUploadParameters {
            XCTAssertEqual(tuple.url, storeURL)
            XCTAssertEqual(tuple.hash, "foo_bar")
            XCTAssertEqual(tuple.file, zipPath)
        } else {
            XCTFail("Could not unwrap the file uploader input tuple")
        }
    }

    func test_store_whenFileUploaderReturnsAnErrorFileArchiverIsCalled() async throws {
        // Given
        fileClient.stubbedUploadError = TestError("Error uploading file")

        // When
        _ = try? await subject.store(name: "targetName", hash: "acho tio", paths: [.root])

        // Then
        XCTAssertEqual(fileArchiver.invokedDeleteCount, 1)
    }

    func test_store_whenFileUploaderReturnsAnErrorVerifyIsNotCalled() async throws {
        // Given
        fileClient.stubbedUploadError = TestError("Error uploading file")
        var verifyCacheUploadWasCalled = false
        verifyCacheUploadService.verifyCacheUploadStub = { _, _, _, _, _ in
            verifyCacheUploadWasCalled = true
        }

        // When
        _ = try? await subject.store(name: "targetName", hash: "acho tio", paths: [.root])

        // Then
        XCTAssertFalse(verifyCacheUploadWasCalled)
    }

    func test_store_whenVerifyFailsTheZipArchiveIsDeleted() async throws {
        // Given
        verifyCacheUploadService.verifyCacheUploadStub = { _, _, _, _, _ in
            throw VerifyCacheUploadServiceError.notFound("Not found")
        }

        // When
        _ = try? await subject.store(name: "targetName", hash: "verify fails hash", paths: [.root])

        // Then
        XCTAssertEqual(fileArchiver.invokedDeleteCount, 1)
    }
}
